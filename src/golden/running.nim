#[

stuff related to the RunningResult and statistics in a broad sense

]#
import stats
import lists

import spec

export stats

type
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

proc len*(running: RunningResult): int =
  result = running.wall.n

proc isEmpty*(running: RunningResult): bool =
  result = running.list.isEmpty

proc first*(running: RunningResult): InvocationInfo =
  assert running.len > 0
  result = running.list.head.value

converter toSeconds(wall: WallDuration): float64 =
  result = wall.inNanoSeconds.float64 / 1_000_000_000

proc add*[T: InvocationInfo](running: RunningResult[T]; value: T) =
  ## for stats, pull out the invocation duration from invocation info
  running.list.append value
  running.wall.push value.runtime.wall.toSeconds

proc add*[T: CompilationInfo](running: RunningResult[T]; value: T) =
  ## for stats, pull out the invocation duration from compilation info
  running.list.append value
  running.wall.push value.invocation.runtime.wall.toSeconds

proc newRunningResult*[T](): RunningResult[T] =
  new result
  result.init "running"
  result.list = initSinglyLinkedList[T]()

proc standardScore*(stat: RunningStat; value: float64): float64 =
  result = (value - stat.mean) / stat.standardDeviation
