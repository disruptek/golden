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

  GoldenDatabase = DatabaseImpl

when false:
  proc shutdown(golden: Golden) {.async.} =
    when defined(git2SetVer):
      git.shutdown()

proc loadDatabaseForFile(filename: string): Future[GoldenDatabase] {.async.} =
  ## load a database using a filename
  result = await newDatabaseImpl(filename)

proc pathToCompilationTarget(filename: string): string =
  ## calculate the path of a source file's compiled binary output
  assert filename.endsWith ".nim"
  var (head, tail) = filename.absolutePath.normalizedPath.splitPath
  tail.removeSuffix ".nim"
  result = head / tail

proc sniffCompilerGitHash*(compiler: CompilerInfo): Future[string] {.async.} =
  ## determine the git hash of the compiler binary if possible;
  ## this should ideally compile a file to measure the version constants, too.
  const pattern = "git hash: "
  let invocation = await invoke(compiler.binary, @["--version"])
  if invocation.okay:
    for line in invocation.output.stdout.splitLines:
      if line.startsWith(pattern):
        let commit = line[pattern.len .. ^1]
        if commit.len == 40:
          result = commit
          break

proc compileFile*(filename: string): Future[CompilationInfo] {.async.} =
  ## compile a source file and yield details of the event
  var
    comp = newCompilationInfo()
  let
    target = pathToCompilationTarget(filename)
    compiler = comp.compiler

  comp.source = newFileDetailWithInfo(filename)
  comp.invocation = await invoke(compiler.binary,
                                   @["c", "-d:danger", comp.source.path])
  if comp.invocation.okay:
    comp.binary = newFileDetailWithInfo(target)
  result = comp

proc benchmark*(golden: Golden; filename: string; args: seq[string] = @[]): Future[BenchmarkResult] {.async.} =
  ## benchmark a source file
  var
    compiler: CompilerInfo
    compilerHash: Future[string]
    bench = newBenchmarkResult()
    invocation: InvocationInfo
    storage: string
    outputs, fib = 0
    clock = getTime()
    secs: Duration

  # see if we need to hint at a specific storage site
  if golden.options.storage != "":
    storage = golden.options.storage
  else:
    storage = filename

  # setup the db and prepare to close it down again
  var
    db = await loadDatabaseForFile(storage)
  defer:
    clock = getTime()
    await db.close
    secs = getTime() - clock
    when not defined(release) and not defined(danger):
      golden.output "close took " & secs.render, fg = fgMagenta

  # do an initial compilation
  var
    compilation = await compileFile(filename)
  if compilation.okay:
    compiler = compilation.compiler
    bench.compilations.add compilation
    compilerHash = compiler.sniffCompilerGitHash
  invocation = compilation.invocation

  # now we loop on invocations of the compiled binary,
  # if it was successfully built above
  clock = getTime()
  try:
    while invocation.okay:
      when defined(debugFdLeak):
        {.warning: "this build is for debugging fd leak".}
        invocation = await invoke("/usr/bin/lsof", "-p", getCurrentProcessId())
        golden.output invocation.output.stdout
      invocation = await invoke(compilation.binary, args)
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
      golden.output bench, "benchmark"
      if truthy:
        break
  except Exception as e:
    if not bench.invocations.isEmpty or not bench.compilations.isEmpty:
      golden.output bench, "benchmark"
    golden.output e.msg & "\ncleaning up..."

  # we should have the git commit hash of the compiler by now
  compiler.chash = await compilerHash

  # here we will synchronize the benchmark to the database if needed
  if DryRun notin golden.options.flags:
    clock = getTime()
    discard db.sync(compiler)
    secs = getTime() - clock
    when not defined(release) and not defined(danger):
      golden.output "sync took " & secs.render, fg = fgMagenta

  result = bench

proc golden(sources: seq[string]; args: string = "";
            color_forced: bool = false; json_output: bool = false;
            interactive_forced: bool = false; graphs_in_console: bool = false;
            prune_outliers: float = 0.0; histogram_classes: int = 10;
            truth: float = 0.01; dry_run: bool = false; storage_path: string = "") =
  ## Nim benchmarking tool;
  ## pass 1+ .nim source files to compile and benchmark
  var
    arguments: seq[string]
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

  golden.options.honesty = truth
  golden.options.prune = prune_outliers
  golden.options.classes = histogram_classes
  golden.options.storage = storage_path

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
