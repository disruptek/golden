import unittest

import golden/spec
import golden/running

suite "statistics":
  test "basic histogram pruning":
    var running = newRunningResult[Gold]()
    for t in [2, 3, 4, 5, 6]:
      var i = newInvocation()
      i.invokation.wall = initDuration(seconds = t)
      running.add i
      if t == 2:
        check running.stat.classSize(1) == 2.0
      if t == 5:
        check running.stat.classSize(2) == 1.5
    check running.len == 5
    for i in [2, 4, 8]:
      let dims = running.stat.makeDimensions(i)
      if i == 8:
        check dims.count == 5
        check dims.size == 0.8
      else:
        check dims.count == i

    check running.stat.max == 6.0
    check running.stat.min == 2.0
    var
      dims = running.stat.makeDimensions(3)
      histo = running.crudeHistogram dims
    check histo == @[2, 1, 2]

    for t in [2, 3, 4]:
      for u in 0 .. 10_000:
        var i = newInvocation()
        i.invokation.wall = initDuration(seconds = t)
        running.add i
    dims = running.stat.makeDimensions(9)
    histo = running.crudeHistogram dims
    check histo == @[10002, 0, 10002, 0, 10002, 0, 1, 0, 1]
    check true == running.maybePrune(histo, dims, 0.001)
    check histo == @[10002, 0, 10002, 0, 10002]
