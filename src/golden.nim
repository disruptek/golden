import os
import asyncfutures
import asyncdispatch
import strutils
import logging

import cligen
import foreach

import golden/spec
import golden/invoke
import golden/db
import golden/output

when defined(git2SetVer):
  import golden/git as ggit

type
  BenchmarkusInterruptus = IOError

  GoldenDatabase = ref object of GoldObject
    path: string
    db: DatabaseImpl

proc close(database: GoldenDatabase) {.async.} =
  ## close the database
  waitfor database.db.close

proc loadDatabaseForFile(filename: string): Future[GoldenDatabase] {.async.} =
  ## load a database using a filename
  new result
  result.init "db"
  result.path = filename
  result.db = await newDatabaseImpl(result.path)
  when defined(git2SetVer):
    ggit.init()

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

proc benchmark*(gold: Golden; filename: string; args: seq[string] = @[]): Future[BenchmarkResult] {.async.} =
  ## benchmark a source file
  let wall = getTime()
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
        gold.output invocation.output.stdout
      invocation = waitfor invoke(compilation.binary, args)
      if invocation.okay:
        bench.invocations.add invocation
      else:
        gold.output invocation, "failed invocation"
      secs = getTime() - clock
      let since = getTime() - wall
      if secs.inSeconds < fib:
        continue
      outputs.inc
      fib = fibonacci(outputs)
      clock = getTime()
      if not bench.invocations.isEmpty or not bench.compilations.isEmpty:
        gold.output bench, "benchmark after " & $since.inSeconds & "s"
  except Exception as e:
    gold.output e.msg & "\ncleaning up..."
  result = bench

proc golden(sources: seq[string]; args: string = "") =
  ## Nim benchmarking tool;
  ## pass 1+ .nim source files to compile and benchmark
  var
    arguments: seq[string]
    gold = newGolden()
  gold.output gold.compiler, "current compiler"

  # capture interrupts
  if gold.interactive:
    proc sigInt() {.noconv.} =
      raise newException(BenchmarkusInterruptus, "")
    setControlCHook(sigInt)

  if args != "":
    arguments = args.split(" ")

  foreach filename in sources.items of string:
    if not filename.appearsBenchmarkable:
      quit "don't know how to benchmark `" & filename & "`"
    discard waitfor gold.benchmark(filename, arguments)

when isMainModule:
  # log only warnings in release
  when defined(release) or defined(danger):
    let level = lvlWarn
  else:
    let level = lvlAll
  let logger = newConsoleLogger(useStderr=true, levelThreshold=level)
  addHandler(logger)

  dispatch golden
