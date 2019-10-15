import os
import asyncfutures
import asyncdispatch
import strutils

import cligen

import golden/spec
import golden/benchmark
import golden/running
import golden/compilation

import golden/lm as dbImpl

when defined(git2SetVer):
  import golden/git as git

when false:
  proc shutdown(golden: Golden) {.async.} =
    when defined(git2SetVer):
      git.shutdown()

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
    result = gold.name & ":" & $gold.oid & " entry " & $gold.created

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

proc golden(sources: seq[string];
            compilation_only: bool = false; dump_output: bool = false;
            iterations: int = 0; runtime: float = 0.0; never_output: bool = false;
            color_forced: bool = false; json_output: bool = false;
            interactive_forced: bool = false; graphs_in_console: bool = false;
            prune_outliers: float = 0.0; histogram_classes: int = 10;
            truth: float = 0.0; dry_run: bool = false; storage_path: string = "") {.used.} =
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

  for b in golden.performBenchmarks(targets):
    try:
      let
        mark = waitfor b
        bench = mark.benchmark
      # output compilation info here for now
      if not bench.compilations.isEmpty and bench.invocations.isEmpty:
        if not bench.compilations.first.okay:
          golden.output bench.compilations.first.invocation, "failed compilation"
        else:
          golden.output bench, started = mark.created, "compilations"
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

  dispatch(golden, stopWords = @["--"])
