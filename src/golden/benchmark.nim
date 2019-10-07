#[

stuff related to the BenchmarkResult and benchmarking in a broad sense

]#
import os
import times
import strutils

import spec
import output
import running

when defined(plotGraphs):
  import osproc
  import plot
  import invoke
  import asyncdispatch

type
  BenchmarkResult* = ref object of GoldObject
    binary*: FileDetail
    compilations*: RunningResult[CompilationInfo]
    invocations*: RunningResult[InvocationInfo]

proc `$`*(bench: BenchmarkResult): string =
  result = $bench.GoldObject
  if bench.invocations.len > 0:
    let invocation = bench.invocations.first
    result &= "\n" & $invocation
  result &= "\ncompilation(s) -- " & $bench.compilations
  result &= "\n invocation(s) -- " & $bench.invocations

proc newBenchmarkResult*(): BenchmarkResult =
  new result
  result.init "bench"
  result.compilations = newRunningResult[CompilationInfo]()
  result.invocations = newRunningResult[InvocationInfo]()

proc appearsBenchmarkable*(path: string): bool =
  ## true if the path looks like something we can bench
  var detail = newFileDetailWithInfo(path)
  if not path.endsWith(".nim"):
    return false
  if detail.info.kind notin {pcFile, pcLinkToFile}:
    return false
  result = true

proc output*(golden: Golden; benchmark: BenchmarkResult; desc: string = "") =
  ## generally used to output a benchmark result periodically
  let since = getTime() - benchmark.entry.toTime
  golden.output desc & " after " & $since.inSeconds & "s"
  golden.output $benchmark
  when not defined(plotGraphs):
    return
  else:
    while true:
      var
        dims = benchmark.invocations.wall.makeDimensions(50)
        histo = benchmark.invocations.crudeHistogram(dims)
      if benchmark.invocations.maybePrune(histo, dims, 0.01):
        continue
      golden.output $histo
      # hangs if histo.len == 1 due to max-min == 0
      if histo.len <= 1:
        break
      let filename = plot.consolePlot(benchmark.invocations.wall, histo, dims)
      if os.getEnv("TERM", "") == "xterm-kitty":
        let kitty = "/usr/bin/kitty"
        if kitty.fileExists:
          var process = startProcess(kitty, args = @["+kitten", "icat", filename], options = {poInteractive, poParentStreams})
          discard process.waitForExit
      break
