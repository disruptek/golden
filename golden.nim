import os
import times
import oids
import asyncfutures
import asyncdispatch
import strutils
import logging
import lists
import terminal

import cligen
import foreach

import spec
import invoke
import db

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
  result.initGold "db"
  result.path = filename
  result.db = await newDatabaseImpl(result.path)

proc pathToCompilationTarget(filename: string): string =
  ## calculate the path of a source file's compiled binary output
  assert filename.endsWith ".nim"
  var (head, tail) = filename.absolutePath.normalizedPath.splitPath
  tail.removeSuffix ".nim"
  result = head / tail

proc compileFile(filename: string): Future[CompilationInfo] {.async.} =
  ## compile a source file and yield details of the event
  var
    comp = newCompilationInfo()
  let
    target = pathToCompilationTarget(filename)
    compiler = comp.compiler

  comp.source = newFileDetailWithInfo(filename)
  comp.invocation = waitfor invoke(compiler.binary,
                                   @["c", "-d:danger", comp.source.path])
  if comp.invocation.output.code == 0:
    comp.binary = newFileDetailWithInfo(target)
  result = comp

proc benchmark(gold: Golden; filename: string): Future[BenchmarkResult] {.async.} =
  ## benchmark a source file
  var
    bench = newBenchmarkResult()
    invocation: InvocationInfo
    db = waitfor loadDatabaseForFile(filename)
  defer:
    waitfor db.close
  try:
    let compilation = waitfor compileFile(filename)
    bench.compilations.append compilation
    invocation = compilation.invocation
    while invocation.output.code == 0:
      when defined(debugFdLeak):
        {.warning: "this build is for debugging fd leak".}
        invocation = waitfor invoke("/usr/bin/lsof", "-p", getCurrentProcessId())
        stdmsg().writeLine invocation.output.stdout
      invocation = waitfor invoke(compilation.binary)
      bench.invocations.append invocation
      stdmsg().writeLine $invocation.runtime
  except Exception as e:
    stdmsg().writeLine e.msg & "\ncleaning up..."
  result = bench

proc goldenCommand(args: seq[string]) =
  ## cli entry
  var gold = newGolden()
  stdmsg().writeLine "golden on " & $gold.compiler

  # capture interrupts
  if stdmsg().isatty:
    proc sigInt() {.noconv.} =
      raise newException(BenchmarkusInterruptus, "")
    setControlCHook(sigInt)

  foreach filename in args.items of string:
    if not filename.appearsBenchmarkable:
      warn "i don't know how to benchmark `" & filename & "`"
      continue
    stdmsg().writeLine waitfor gold.benchmark(filename)

when isMainModule:
  # log only warnings in release
  when defined(release) or defined(danger):
    let level = lvlWarn
  else:
    let level = lvlAll
  let logger = newConsoleLogger(useStderr=true, levelThreshold=level)
  addHandler(logger)

  dispatch goldenCommand
