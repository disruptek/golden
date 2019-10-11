import os
import asyncfutures
import asyncdispatch
import strutils
import logging

import cligen

import golden/spec
import golden/output
import golden/benchmark
import golden/running

import golden/lm as dbImpl

when defined(git2SetVer):
  import golden/git as git

when false:
  proc shutdown(golden: Golden) {.async.} =
    when defined(git2SetVer):
      git.shutdown()

proc loadDatabase(golden: Golden; targets: seq[string]): Future[GoldenDatabase] {.async.} =
  ## load a database using a filename
  var storage: string
  # see if we need to hint at a specific storage site
  if golden.options.storage != "":
    storage = golden.options.storage
  elif targets.len == 1:
    storage = targets[0]
  else:
    storage = parentDir(targets[0]) / $targets.join("").toMD5
  result = await dbImpl.open(storage, golden.options.flags)

iterator performBenchmarks(golden: Golden; targets: seq[string]): Future[BenchmarkResult] =
  var
    db: GoldenDatabase

  db = waitfor golden.loadDatabase(targets)
  # setup the db and prepare to close it down again
  defer:
    waitfor db.close

  # compile-only mode, for benchmarking the compiler
  if CompileOnly in golden.options.flags:
    for filename in targets.items:
      if not filename.appearsToBeCompileableSource:
        quit filename & ": does not appear to be compileable Nim source"
    for filename in targets.items:
      yield golden.benchmarkCompiler(filename)

  # mostly-run mode, for benchmarking runtimes
  else:
    for filename in targets.items:
      if filename.appearsToBeCompileableSource:
        var bench = newBenchmarkResult()
        # compile it, then benchmark it
        for b in golden.benchmarkNim(bench, filename):
          # first is the compilations, next is binary benches
          yield b
      else:
        # just benchmark it; it's already executable, we hope
        yield golden.benchmark(filename, golden.options.arguments)

proc golden(sources: seq[string];
            compilation_only: bool = false; dump_output: bool = false;
            iterations: int = 0; runtime: float = 0.0; never_output: bool = false;
            color_forced: bool = false; json_output: bool = false;
            interactive_forced: bool = false; graphs_in_console: bool = false;
            prune_outliers: float = 0.0; histogram_classes: int = 10;
            truth: float = 0.0; dry_run: bool = false; storage_path: string = "") =
  ## Nim benchmarking tool;
  ## pass 1+ .nim source files to compile and benchmark
  var
    targets: seq[string]
    golden = newGolden()

  when defined(git2SetVer):
    git.init()
    defer:
      git.shutdown()

  if json_output:
    golden.options.flags.incl PipeOutput
  if interactive_forced:
    golden.options.flags.incl Interactive
  if Interactive in golden.options.flags and color_forced:
    golden.options.flags.incl ColorConsole
  if graphs_in_console:
    golden.options.flags.incl ConsoleGraphs
  if dry_run:
    golden.options.flags.incl DryRun
  if compilation_only:
    golden.options.flags.incl CompileOnly
  if dump_output:
    golden.options.flags.incl DumpOutput
  if never_output:
    golden.options.flags.incl NeverOutput

  golden.options.honesty = truth
  golden.options.prune = prune_outliers
  golden.options.classes = histogram_classes
  golden.options.storage = storage_path
  if runtime != 0.0:
    golden.options.flags.incl TimeLimit
    golden.options.timeLimit = runtime
  if iterations != 0:
    golden.options.flags.incl RunLimit
    golden.options.runLimit = iterations

  # work around cligen --stopWords support
  for index in 1 .. paramCount():
    targets.add paramStr(index)
  let dashdash = targets.find("--")
  if dashdash == -1:
    targets = sources
  else:
    golden.options.arguments = targets[dashdash + 1 .. ^1]
    targets = sources[0 ..< sources.len - golden.options.arguments.len]

  for filename in targets.items:
    if not filename.appearsBenchmarkable:
      quit "don't know how to benchmark `" & filename & "`"

  if targets.len == 0:
    quit "provide some files to benchmark, or\n" & paramStr(0) & " --help"

  # capture interrupts
  if Interactive in golden.options.flags:
    proc sigInt() {.noconv.} =
      raise newException(BenchmarkusInterruptus, "")
    setControlCHook(sigInt)

  for bench in golden.performBenchmarks(targets):
    try:
      let mark = waitfor bench
      # output compilation info here for now
      if not mark.compilations.isEmpty and mark.invocations.isEmpty:
        if not mark.compilations.first.invocation.okay:
          golden.output mark.compilations.first.invocation, "failed compilation"
        else:
          golden.output mark, "compilations"
    except BenchmarkusInterruptus:
      break
    except Exception as e:
      golden.output e.msg

when isMainModule:
  # log only warnings in release
  when defined(release) or defined(danger):
    let level = lvlWarn
  else:
    let level = lvlAll
  let logger = newConsoleLogger(useStderr=true, levelThreshold=level)
  addHandler(logger)

  dispatch(golden, stopWords = @["--"])
