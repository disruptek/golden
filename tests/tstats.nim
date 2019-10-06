import unittest

import golden/spec
import golden/running

suite "statistics":
  test "basic histogram pruning":
    var running = newRunningResult[InvocationInfo]()
    for t in [2, 3, 4, 5, 6]:
      var i = newInvocationInfo()
      i.runtime = newRuntimeInfo()
      i.runtime.wall = initDuration(seconds = t)
      running.add i
      if t == 2:
        check running.wall.classSize(1) == 2.0
      if t == 5:
        check running.wall.classSize(2) == 1.5
    check running.len == 5
    for i in [2, 4, 8]:
      let dims = running.wall.makeDimensions(i)
      if i == 8:
        check dims.count == 5
        check dims.size == 0.8
      else:
        check dims.count == i

    check running.wall.max == 6.0
    check running.wall.min == 2.0
    var
      dims = running.wall.makeDimensions(3)
      histo = running.crudeHistogram dims
    check histo == @[2, 1, 2]

    for t in [2, 3, 4]:
      for u in 0 .. 10_000:
        var i = newInvocationInfo()
        i.runtime = newRuntimeInfo()
        i.runtime.wall = initDuration(seconds = t)
        running.add i
    dims = running.wall.makeDimensions(9)
    histo = running.crudeHistogram dims
    check histo == @[10002, 0, 10002, 0, 10002, 0, 1, 0, 1]
    check true == running.maybePrune(histo, dims, 0.001)
    check histo == @[10002, 0, 10002, 0, 10002]
