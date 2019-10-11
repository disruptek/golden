#[

stuff related to the RunningResult and statistics in a broad sense

]#
import stats
import lists
import math
import strformat
import strutils

import terminaltables
import msgpack4nim

import spec
import linkedlists
import compilation
import output

export stats

const billion = 1_000_000_000

type
  StatValue = float64
  ClassDimensions* = tuple
    count: int
    size: StatValue

  RunningResult*[T] = ref object of GoldObject
    list: SinglyLinkedList[T]
    wall*: RunningStat
    cpu*: RunningStat
    memory*: RunningStat

proc toTerminalTable(running: RunningResult; name: string): ref TerminalTable =
  let
    stat = running.wall
  var
    row: seq[string]
  result = newUnicodeTable()
  result.setHeaders @[name, "Min", "Max", "Mean", "StdDev"]
  result.separateRows = false
  row.add fmt"{stat.n:>6d}"
  row.add fmt"{stat.min:>0.6f}"
  row.add fmt"{stat.max:>0.6f}"
  row.add fmt"{stat.mean:>0.6f}"
  row.add fmt"{stat.standardDeviation:>0.6f}"
  result.addRow row

proc `$`*(running: RunningResult): string =
  let table = running.toTerminalTable("     #")
  result = table.render.strip

proc output*(golden: Golden; running: RunningResult; desc: string = "") =
  if desc != "":
    running.description = desc
  let table = running.toTerminalTable(desc)
  golden.output table.render.strip

proc len*(running: RunningResult): int =
  result = running.wall.n

proc isEmpty*(running: RunningResult): bool =
  result = running.list.isEmpty

proc first*[T](running: RunningResult[T]): T =
  assert not running.isEmpty
  result = running.list.first

converter toSeconds*(wall: WallDuration): StatValue =
  result = wall.inNanoSeconds.StatValue / billion

proc standardScore*(stat: RunningStat; value: StatValue): StatValue =
  result = (value - stat.mean) / stat.standardDeviation

proc add*[T: InvocationInfo](running: RunningResult[T]; value: T) =
  ## for stats, pull out the invocation duration from invocation info
  let seconds = value.runtime.wall.toSeconds
  running.list.append value
  running.wall.push seconds

proc reset*[T: InvocationInfo](running: RunningResult[T]) =
  running.wall.clear
  running.cpu.clear
  running.memory.clear
  var wall: seq[StatValue]
  for invocation in running.list.items:
    wall.add invocation.runtime.wall.toSeconds
  running.wall.push wall

proc classSize*(stat: RunningStat; count: int): StatValue =
  ## the step size for each element in the histogram
  let delta = stat.max - stat.min
  if delta > 0:
    result = delta / count.StatValue
  else:
    result = stat.max

proc makeDimensions*(stat: RunningStat; maximum: int): ClassDimensions =
  ## the best dimensions for a histogram of <= maximum items
  if stat.n == 0:
    return (count: 0, size: 0.0)
  let count = min(maximum, stat.n)
  result = (count: count, size: stat.classSize(count))

proc crudeHistogram*(running: RunningResult; dims: ClassDimensions): seq[int] =
  ## make a simple histogram suitable for a text/image graph
  result = newSeqOfCap[int](dims.count)
  for i in 0 .. dims.count - 1:
    result.add 0
  let (smin, smax) = (running.wall.min, running.wall.max)
  for element in running.list.items:
    var n = 0
    let s = element.runtime.wall.toSeconds
    if s == smin:
      n = 0
    elif s == smax:
      n = dims.count - 1
    else:
      assert dims.size > 0
      n = int((s - smin) / dims.size)
    result[n].inc

proc prunePoint(stat: RunningStat; histogram: var seq[int]; dims: ClassDimensions; outlier: float): StatValue =
  ## find a good value above which we should prune outlier entries
  if stat.n <= 3:
    return
  var totalSum = sum(histogram).float
  while histogram[^1].float < totalSum * outlier:
    result = stat.min + (dims.size * histogram.high.StatValue)
    delete histogram, histogram.high
    totalSum = sum(histogram).float

proc maybePrune*(running: var RunningResult; histogram: var seq[int];
                 dims: ClassDimensions; outlier: float): bool =
  ## maybe prune some outliers from the top of our histogram

  # first, see if we really want to prune anything
  let prunePoint = running.wall.prunePoint(histogram, dims, outlier)
  if prunePoint == 0:
    return

  # okay; turn seconds into a Duration and then prune anything bigger
  let pruneOffset = initDuration(nanoseconds = int(prunePoint * billion))
  var head = running.list.head
  while true:
    while head.next != nil and head.next.value.runtime.wall > pruneOffset:
      head.removeNext
    if head.next == nil:
      break
    head = head.next
  # recompute stats
  running.reset
  # let the world know that we probably did something
  result = true

iterator mitems*[T](running: RunningResult[T]): var T =
  for item in running.list.mitems:
    yield item

iterator items*[T](running: RunningResult[T]): T =
  for item in running.list.items:
    yield item

proc add*[T: CompilationInfo](running: RunningResult[T]; value: T) =
  ## for stats, pull out the invocation duration from compilation info
  running.list.append value
  running.wall.push value.invocation.runtime.wall.toSeconds

proc truthy*(running: RunningResult; honesty: float): bool =
  ## do we think we know enough about the running result to stop running?
  if running.len < 3:
    return
  if running.wall.mean * honesty > running.wall.standardDeviation:
    return true

proc newRunningResult*[T](): RunningResult[T] =
  new result
  result.init "running"
  result.list = initSinglyLinkedList[T]()

proc pack_type*[ByteStream](s: ByteStream; x: RunningResult) =
  s.pack_type(x.oid)
  s.pack_type(x.entry)
  s.pack_type(x.list)
  s.pack_type(x.wall)

proc unpack_type*[ByteStream](s: ByteStream; x: var RunningResult) =
  s.unpack_type(x.oid)
  s.unpack_type(x.entry)
  s.unpack_type(x.list)
  s.unpack_type(x.wall)

proc pack_type*[ByteStream](s: ByteStream; x: RunningResult[CompilationInfo]) =
  s.pack_type(x.oid)
  s.pack_type(x.entry)
  s.pack_type(x.list)
  s.pack_type(x.wall)

proc unpack_type*[ByteStream](s: ByteStream; x: var RunningResult[CompilationInfo]) =
  s.unpack_type(x.oid)
  s.unpack_type(x.entry)
  s.unpack_type(x.list)
  s.unpack_type(x.wall)
