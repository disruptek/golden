#[

stuff related to the BenchmarkResult and benchmarking in a broad sense

]#
import os
import times
import strutils
import asyncdispatch
import asyncfutures

import spec
import running
import compilation
import invoke

when defined(plotGraphs):
  import osproc
  import plot

proc `$`*(bench: BenchmarkResult): string =
  if bench.invocations.len > 0:
    let invocation = bench.invocations.first
    result = invocation.commandLine
  if bench.invocations.len > 0:
    result &= "\ninvocations:\n" & $bench.invocations

proc newBenchmarkResult*(): Gold =
  result = newGold(aBenchmark)
  result.benchmark = BenchmarkResult()
  result.benchmark.invocations = newRunningResult[Gold]()

proc output*(golden: Golden; benchmark: BenchmarkResult; started: Time;
             desc: string = "") =
  ## generally used to output a benchmark result periodically
  let since = getTime() - started
  golden.output desc & " after " & $since.inSeconds & "s"
  if benchmark.invocations.len > 0:
    var name: string
    let invocation = benchmark.invocations.first
    if invocation.kind == aCompilation:
      name = "Builds"
    else:
      name = "Runs"
    if not invocation.okay:
      golden.output invocation
    golden.output benchmark.invocations, name
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

proc benchmark*(golden: Golden; binary: Gold;
                arguments: seq[string]): Future[Gold] {.async.} =
  ## benchmark an arbitrary executable
  let
    wall = getTime()
    timeLimit = int( 1000 * golden.options.timeLimit )
  var
    bench = newBenchmarkResult()
    invocation: Gold
    runs, outputs, fib = 0
    lastOutputTime = getTime()
    truthy = false
    secs: Duration

  bench.terminated = Terminated.Success
  try:
    while true:
      when defined(debugFdLeak):
        {.warning: "this build is for debugging fd leak".}
        invocation = await invoke("/usr/bin/lsof", "-p", getCurrentProcessId())
        golden.output invocation.output.stdout
      invocation = await invoke(binary, arguments, timeLimit = timeLimit)
      runs.inc
      if invocation.okay:
        bench.invocations.add invocation
        if DumpOutput in golden.options.flags:
          golden.output invocation, "invocation", arguments = arguments
      else:
        golden.output invocation, "failed invocation", arguments = arguments
      secs = getTime() - wall
      truthy = bench.invocations.truthy(golden.options.honesty)
      if RunLimit in golden.options.flags:
        if runs >= golden.options.runLimit:
          truthy = true
      when false:
        # we use the time limit to limit runtime of each invocation now
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
      if not invocation.okay:
        bench.terminated = Terminated.Failure
        break
      if truthy:
        break
      if Brief notin golden.options.flags:
        golden.output bench.benchmark, started = bench.created, "benchmark"
  except BenchmarkusInterruptus as e:
    bench.terminated = Terminated.Interrupt
    raise e
  except Exception as e:
    bench.terminated = Terminated.Failure
    raise e
  finally:
    result = bench
    var
      name = "execution"
    if not bench.invocations.isEmpty:
      var
        first = bench.invocations.first
      if first.kind == aCompilation:
        name = "compilation"
      else:
        name = "invocation"
    case bench.terminated:
    of Terminated.Interrupt:
      name &= " halted"
    of Terminated.Failure:
      name &= " failed"
    of Terminated.Success:
      name &= " complete"
    golden.output bench.benchmark, started = bench.created, name

proc benchmark*(golden: Golden; filename: string;
                arguments: seq[string]): Future[Gold] {.async.} =
  result = await golden.benchmark(newFileDetailWithInfo(filename), arguments)

proc benchmarkCompiler*(golden: Golden;
                        filename: string): Future[Gold] {.async.} =
  assert CompileOnly in golden.options.flags
  var
    compiler = newCompiler()
    gold = newCompilation(compiler, filename)
    args = gold.argumentsForCompilation(golden.options.arguments)
  # add the source filename to compilation arguments
  for source in gold.sources:
    args.add source.file.path
  result = await golden.benchmark(compiler.binary, args)

iterator benchmarkNim*(golden: Golden; gold: var Gold;
                       filename: string): Future[Gold] =
  ## benchmark a source file
  assert CompileOnly notin golden.options.flags
  var
    future = newFuture[Gold]()
    compilation = waitfor compileFile(filename, golden.options.arguments)
    bench = gold.benchmark

  # the compilation is pretty solid; let's add it to the benchmark
  bench.invocations.add compilation
  # and yield it so the user can see the compilation result
  future.complete(gold)
  yield future

  # if the compilation was successful,
  # we go on to yield a benchmark of the executable we just built
  if compilation.okay:
    yield golden.benchmark(compilation.target, golden.options.arguments)
