import os
import options
import asyncfutures
import asyncdispatch
import strutils

import bump
import cligen
import gittyup

import golden/spec
import golden/benchmark
import golden/compilation

import golden/lm as dbImpl

when false:
  proc shutdown(golden: Golden) {.async.} =
    gittyup.shutdown()

proc `$`*(gold: Gold): string =
  case gold.kind:
  of aCompiler:
    result = $gold.compiler
  of anInvocation:
    result = $gold.invocation
  of aBenchmark:
    result = $gold.benchmark
  of aFile:
    result = $gold.file
  else:
    result = $gold.kind & $gold.oid & " entry " & $gold.created

proc output*(golden: Golden; gold: Gold; desc: string = "") =
  if desc != "":
    gold.description = desc
  if Interactive in golden.options.flags:
    golden.output $gold
  if jsonOutput(golden):
    golden.output gold.toJson

proc storageForTarget*(golden: Golden; target: string): string =
  if golden.options.storage != "":
    result = golden.options.storage
  elif target.endsWith ".nim":
    result = pathToCompilationTarget(target)
  else:
    result = target

proc storageForTargets*(golden: Golden; targets: seq[string]): string =
  # see if we need to hint at a specific storage site
  if golden.options.storage != "":
    result = golden.options.storage
  elif targets.len == 1:
    result = golden.storageForTarget(targets[0])
  else:
    quit "specify --storage to benchmark multiple programs"

proc openDatabase*(golden: Golden; targets: seq[string]): Future[GoldenDatabase] {.async.} =
  ## load a database using a filename
  let storage = golden.storageForTargets(targets)
  result = await dbImpl.open(storage, golden.options.flags)

proc removeDatabase*(db: var GoldenDatabase; flags: set[GoldenFlag]) =
  ## remove a database
  dbImpl.removeDatabase(db, flags)

proc removeDatabase*(golden: Golden; targets: seq[string]) =
  ## remove a database without a database handle by opening it first
  var db = waitfor golden.openDatabase(targets)
  removeDatabase(db, golden.options.flags)

iterator performBenchmarks(golden: Golden; targets: seq[string]): Future[Gold] =
  var
    db: GoldenDatabase

  db = waitfor golden.openDatabase(targets)
  # setup the db and prepare to close it down again
  defer:
    dbImpl.close(db)

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

proc golden(sources: seq[string]; brief = false; compilation_only = false;
            dump_output = false; iterations = 0; runtime = 0.0;
            never_output = false; color_forced = false; json_output = false;
            interactive_forced = false; prune_outliers = 0.0;
            histogram_classes = 10; truth = 0.0; dry_run = false;
            storage_path = "") {.used.} =
  ## Nim benchmarking tool;
  ## pass 1+ .nim source files to compile and benchmark
  var
    targets: seq[string]
    golden = newGolden()

  if not gittyup.init():
    raise newException(OSError, "unable to init git")
  defer:
    if not gittyup.shutdown():
      raise newException(OSError, "unable to shut git")

  if json_output:
    golden.options.flags.incl PipeOutput
  if interactive_forced:
    golden.options.flags.incl Interactive
  if Interactive in golden.options.flags and color_forced:
    golden.options.flags.incl ColorConsole
  when defined(plotGraphs):
    golden.options.flags.incl ConsoleGraphs
  if dry_run:
    golden.options.flags.incl DryRun
  if compilation_only:
    golden.options.flags.incl CompileOnly
  if dump_output:
    golden.options.flags.incl DumpOutput
  if never_output:
    golden.options.flags.incl NeverOutput
  if brief:
    golden.options.flags.incl Brief
    golden.output "in brief mode, you will only receive output at termination..."

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

  for b in golden.performBenchmarks(targets):
    try:
      let mark = waitfor b
      if mark.terminated != Terminated.Success:
        quit(1)
    except BenchmarkusInterruptus:
      break
    except Exception as e:
      golden.output e.msg

when isMainModule:
  import logging
  # log only warnings in release
  when defined(release) or defined(danger):
    let level = lvlWarn
  else:
    let level = lvlAll
  let logger = newConsoleLogger(useStderr=true, levelThreshold=level)
  addHandler(logger)

  const
    version = projectVersion()
  if version.isSome:
    clCfg.version = $version.get
  else:
    clCfg.version = "(unknown version)"

  dispatchCf(golden, cf = clCfg, stopWords = @["--"])
