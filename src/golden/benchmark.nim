#[

stuff related to the BenchmarkResult and benchmarking in a broad sense

]#
import os
import times
import strutils
import asyncdispatch
import asyncfutures

import spec
#import output
import running
import compilation
import invoke

when defined(plotGraphs):
  import osproc
  import plot

proc `$`*(bench: BenchmarkResult): string =
  if bench.invocations.len > 0:
    let invocation = bench.invocations.first
    result = $invocation.invocation
  if bench.invocations.len == 0:
    if bench.compilations.len > 0:
      result &= "\ncompilations:\n" & $bench.compilations
  else:
    result &= "\ninvocations:\n" & $bench.invocations

proc newBenchmarkResult*(): Gold =
  result = newGold(aBenchmark)
  result.benchmark = BenchmarkResult()
  result.benchmark.compilations = newRunningResult[Gold]()
  result.benchmark.invocations = newRunningResult[Gold]()

proc output*(golden: Golden; benchmark: BenchmarkResult; started: Time;
             desc: string = "") =
  ## generally used to output a benchmark result periodically
  let since = getTime() - started
  golden.output desc & " after " & $since.inSeconds & "s"
  if benchmark.invocations.len > 0:
    let invocation = benchmark.invocations.first
    if not invocation.okay:
      golden.output invocation.invocation
  if benchmark.invocations.len == 0:
    if benchmark.compilations.len > 0:
      golden.output benchmark.compilations, "Builds"
  else:
    golden.output benchmark.invocations, "Runs"
  when defined(debug):
    goldenDebug()
  when defined(plotGraphs):
    while ConsoleGraphs in golden.options.flags:
      var
        dims = benchmark.invocations.stat.makeDimensions(golden.options.classes)
        histo = benchmark.invocations.crudeHistogram(dims)
      if benchmark.invocations.maybePrune(histo, dims, golden.options.prune):
        continue
      golden.output $histo
      # hangs if histo.len == 1 due to max-min == 0
      if histo.len <= 1:
        break
      let filename = plot.consolePlot(benchmark.invocations.stat, histo, dims)
      if os.getEnv("TERM", "") == "xterm-kitty":
        let kitty = "/usr/bin/kitty"
        if kitty.fileExists:
          var process = startProcess(kitty, args = @["+kitten", "icat", filename], options = {poInteractive, poParentStreams})
          discard process.waitForExit
      break

const
  executable = {fpUserExec, fpGroupExec, fpOthersExec}
  readable = {fpUserRead, fpGroupRead, fpOthersRead}

proc appearsToBeReadable(path: string): bool =
  ## see if a file is readable
  var file: File
  result = file.open(path, mode = fmRead)
  if result:
    file.close

proc veryLikelyRunnable(path: string; info: FileInfo): bool =
  ## weirdly, we don't seem to have a way to test if a file
  ## is going to be executable, so just estimate if we are
  ## likely able to execute the file
  let
    user = {fpUserExec, fpUserRead} * info.permissions
    group = {fpGroupExec, fpGroupRead} * info.permissions
    others = {fpOthersExec, fpOthersRead} * info.permissions
    r = readable * info.permissions
    x = executable * info.permissions

  if info.kind notin {pcFile, pcLinkToFile}:
    return false

  # if you can't read it, you can't run it
  if r.len == 0:
    return false
  # if you really can't read it, you can't run it
  if not path.appearsToBeReadable:
    return false

  # assume that something in readable is giving us read permissions
  # assume that we are in "Others"
  if fpOthersRead in r and fpOthersExec in x:
    return true

  # let's see if there's only one readable flag and it shares
  # a class with an executable flag...
  if r.len == 1:
    for r1 in r.items:
      for c in [user, group, others]:
        if r1 in c:
          if (x * c).len > 0:
            return true
    # okay, so it doesn't share the class, but if Others has Exec,
    # assume that we are in "Others"
    if fpOthersExec in x:
      return true

  # we might be able to execute it, but we might not!
  result = false

proc appearsToBeCompileableSource*(path: string): bool =
  result = path.endsWith(".nim") and path.appearsToBeReadable

proc appearsToBeExecutable*(path: string; info: FileInfo): bool =
  result = veryLikelyRunnable(path, info)
  result = result or (executable * info.permissions).len > 0 # lame

proc appearsBenchmarkable*(path: string): bool =
  ## true if the path looks like something we can bench
  try:
    let info = getFileInfo(path)
    var detail = newFileDetail(path, info)
    if detail.file.kind notin {pcFile, pcLinkToFile}:
      return false
    if detail.file.path.appearsToBeCompileableSource:
      return true
    result = detail.file.path.appearsToBeExecutable(info)
  except OSError as e:
    stdmsg().writeLine(path & ": " & e.msg)
    return false

proc benchmark*(golden: Golden; filename: string;
                arguments: seq[string]): Future[Gold] {.async.} =
  ## benchmark an arbitrary executable
  let
    target = newFileDetailWithInfo(filename)
    wall = getTime()
  var
    bench = newBenchmarkResult()
    invocation: Gold
    runs, outputs, fib = 0
    lastOutputTime = getTime()
    truthy = false
    secs: Duration

  var termination = "completed benchmark"
  try:
    while true:
      when defined(debugFdLeak):
        {.warning: "this build is for debugging fd leak".}
        invocation = await invoke("/usr/bin/lsof", "-p", getCurrentProcessId())
        golden.output invocation.output.stdout
      invocation = await invoke(target, arguments)
      runs.inc
      if invocation.okay:
        bench.benchmark.invocations.add invocation
        if DumpOutput in golden.options.flags:
          golden.output invocation.invocation, "invocation",
                        arguments = arguments
      else:
        golden.output invocation.invocation, "failed invocation",
                      arguments = arguments
      secs = getTime() - wall
      truthy = bench.benchmark.invocations.truthy(golden.options.honesty)
      if RunLimit in golden.options.flags:
        if runs >= golden.options.runLimit:
          truthy = true
      if TimeLimit in golden.options.flags:
        if secs.toSeconds >= golden.options.timeLimit:
          truthy = true
      when not defined(debug):
        secs = getTime() - lastOutputTime
        if not truthy and secs.inSeconds < fib:
          continue
        lastOutputTime = getTime()
        outputs.inc
        fib = fibonacci(outputs)
      if truthy or not invocation.okay:
        break
      golden.output bench.benchmark, started = bench.created, "benchmark"
  except BenchmarkusInterruptus as e:
    termination = "interrupted benchmark"
    result = bench
    raise e
  except Exception as e:
    termination = "benchmark failed"
    result = bench
    raise e
  finally:
    if not bench.benchmark.invocations.isEmpty or not bench.benchmark.compilations.isEmpty:
      golden.output bench.benchmark, started = bench.created, termination
  result = bench

proc benchmarkCompiler*(golden: Golden;
                        filename: string): Future[Gold] {.async.} =
  assert CompileOnly in golden.options.flags
  var
    gold = newCompilationInfo(filename)
    compiler = gold.compilation.compiler.compiler
    args = argumentsForCompilation(golden.options.arguments)
  # add the source filename to compilation arguments
  args.add gold.compilation.source.file.path
  result = await golden.benchmark(compiler.binary.file.path, args)

iterator benchmarkNim*(golden: Golden; gold: var Gold;
                       filename: string): Future[Gold] =
  ## benchmark a source file
  assert CompileOnly notin golden.options.flags
  var
    future = newFuture[Gold]()
    compilation = waitfor compileFile(filename, golden.options.arguments)
    bench = gold.benchmark

  # the compilation is pretty solid; let's add it to the benchmark
  bench.compilations.add compilation
  # and yield it so the user can see the compilation result
  future.complete(gold)
  yield future

  # if the compilation was successful,
  # we go on to yield a benchmark of the executable we just built
  if compilation.okay:
    yield golden.benchmark(compilation.compilation.binary.file.path,
                           golden.options.arguments)
