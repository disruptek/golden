import os
import asyncfutures
import asyncdispatch
import strutils
import logging

import cligen

import golden/spec
import golden/invoke
import golden/db
import golden/output
import golden/benchmark
import golden/running

when defined(git2SetVer):
  import golden/git as git

type
  BenchmarkusInterruptus = IOError

  GoldenDatabase = ref object of GoldObject
    path: string
    db: DatabaseImpl

proc close(database: GoldenDatabase) {.async.} =
  ## close the database
  waitfor database.db.close
  when defined(git2SetVer):
    git.shutdown()

proc loadDatabaseForFile(filename: string): Future[GoldenDatabase] {.async.} =
  ## load a database using a filename
  new result
  result.init "db"
  result.path = filename
  result.db = await newDatabaseImpl(result.path)
  when defined(git2SetVer):
    git.init()

proc pathToCompilationTarget(filename: string): string =
  ## calculate the path of a source file's compiled binary output
  assert filename.endsWith ".nim"
  var (head, tail) = filename.absolutePath.normalizedPath.splitPath
  tail.removeSuffix ".nim"
  result = head / tail

proc compileFile*(filename: string): Future[CompilationInfo] {.async.} =
  ## compile a source file and yield details of the event
  var
    comp = newCompilationInfo()
  let
    target = pathToCompilationTarget(filename)
    compiler = comp.compiler

  comp.source = newFileDetailWithInfo(filename)
  comp.invocation = waitfor invoke(compiler.binary,
                                   @["c", "-d:danger", comp.source.path])
  if comp.invocation.okay:
    comp.binary = newFileDetailWithInfo(target)
  result = comp

proc benchmark*(golden: Golden; filename: string; args: seq[string] = @[]): Future[BenchmarkResult] {.async.} =
  ## benchmark a source file
  var
    bench = newBenchmarkResult()
    invocation: InvocationInfo
    db = waitfor loadDatabaseForFile(filename)
  defer:
    waitfor db.close
  try:
    let compilation = waitfor compileFile(filename)
    if compilation.okay:
      bench.compilations.add compilation
    invocation = compilation.invocation
    var
      outputs, fib = 0
      clock = getTime()
      secs: Duration
    while invocation.okay:
      when defined(debugFdLeak):
        {.warning: "this build is for debugging fd leak".}
        invocation = waitfor invoke("/usr/bin/lsof", "-p", getCurrentProcessId())
        golden.output invocation.output.stdout
      invocation = waitfor invoke(compilation.binary, args)
      if invocation.okay:
        bench.invocations.add invocation
      else:
        golden.output invocation, "failed invocation"
      secs = getTime() - clock
      let truthy = bench.invocations.truthy(golden.options.honesty)
      when not defined(debug):
        if not truthy and secs.inSeconds < fib:
          continue
      outputs.inc
      fib = fibonacci(outputs)
      clock = getTime()
      if bench.invocations.isEmpty and bench.compilations.isEmpty:
        continue
      golden.output bench, "benchmark"
      if truthy:
        break
  except Exception as e:
    golden.output bench, "benchmark"
    golden.output e.msg & "\ncleaning up..."
  result = bench

proc golden(sources: seq[string]; args: string = "";
            color_forced: bool = false; pipe_json: bool = false;
            interactive_forced: bool = false; graphs_in_console: bool = false;
            prune_outliers: float = 0.01; classes_for_histogram: int = 10;
            honesty: float = 0.01) =
  ## Nim benchmarking tool;
  ## pass 1+ .nim source files to compile and benchmark
  var
    arguments: seq[string]
    golden = newGolden()

  if pipe_json:
    golden.options.flags.incl PipeOutput
  if interactive_forced:
    golden.options.flags.incl Interactive
  if Interactive in golden.options.flags and color_forced:
    golden.options.flags.incl ColorConsole
  if graphs_in_console:
    golden.options.flags.incl ConsoleGraphs

  golden.options.honesty = honesty
  golden.options.prune = prune_outliers
  golden.options.classes = classes_for_histogram

  golden.output golden.compiler, "current compiler"

  # capture interrupts
  if Interactive in golden.options.flags:
    proc sigInt() {.noconv.} =
      raise newException(BenchmarkusInterruptus, "")
    setControlCHook(sigInt)

  if args != "":
    arguments = args.split(" ")

  for filename in sources.items:
    if not filename.appearsBenchmarkable:
      quit "don't know how to benchmark `" & filename & "`"
    discard waitfor golden.benchmark(filename, arguments)

when isMainModule:
  # log only warnings in release
  when defined(release) or defined(danger):
    let level = lvlWarn
  else:
    let level = lvlAll
  let logger = newConsoleLogger(useStderr=true, levelThreshold=level)
  addHandler(logger)

  dispatch golden
