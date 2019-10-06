#[

stuff related to the RunningResult and statistics in a broad sense

]#
import stats
import lists
import math

import spec

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

proc isEmpty[T](list: SinglyLinkedList[T]): bool =
  result = list.head == nil

proc len[T](list: SinglyLinkedList[T]): int =
  var head = list.head
  while head != nil:
    result.inc
    head = head.next

proc removeNext*(head: var SinglyLinkedNode) =
  ## remove the next node in a list
  if head != nil:
    if head.next != nil:
      if head.next.next != nil:
        head.next = head.next.next
      else:
        head.next = nil

proc len*(running: RunningResult): int =
  result = running.wall.n

proc isEmpty*(running: RunningResult): bool =
  result = running.list.isEmpty

proc first*(running: RunningResult): InvocationInfo =
  assert running.len > 0
  result = running.list.head.value

converter toSeconds(wall: WallDuration): StatValue =
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

proc add*[T: CompilationInfo](running: RunningResult[T]; value: T) =
  ## for stats, pull out the invocation duration from compilation info
  running.list.append value
  running.wall.push value.invocation.runtime.wall.toSeconds

proc newRunningResult*[T](): RunningResult[T] =
  new result
  result.init "running"
  result.list = initSinglyLinkedList[T]()
