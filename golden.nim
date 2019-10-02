import os
import times
import oids
import asyncfutures
import asyncdispatch
import strutils
import osproc
import selectors
import terminal
import logging

import cligen

import spec
import db

type
  GoldenDatabase = ref object of GoldObject
    path: string
    db: DatabaseImpl

proc close(database: GoldenDatabase) {.async.} =
  ## close the database
  waitfor database.db.close

proc invoke(binary: FileDetail, args: seq[string]): Future[InvocationInfo] {.async.} =
  type
    HandleKind = enum Input, Output, Errors, Finished
  echo "invoke against ", binary
  var
    invocation = newInvocationInfo(binary, args = args)
    process = startProcess(binary.path, args = args, options = {})
    watcher = newSelector[HandleKind]()
    events: seq[ReadyKey]

  echo "process running"
  invocation.output = newOutputInfo()

  #watcher.registerHandle(process.outputHandle.int, {Read}, Output)
  #watcher.registerHandle(process.errorHandle.int, {Read}, Errors)
  watcher.registerProcess(process.processId, Finished)

  echo "registered"
  while true:
    echo "select"
    let count = watcher.selectInto(1000, events)
    echo $count, " events"
    for n in events:
      echo n.fd, " ", n.errorCode.repr, " ", n.events.repr

  invocation.output.code = process.waitForExit
  echo "invoke code ", invocation.output.code
  result = invocation

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
  comp.invocation = waitfor invoke(compiler.binary, @["c", comp.source.path])
  comp.binary = newFileDetailWithInfo(target)
  result = comp

proc benchmark(gold: Golden; filename: string): Future[BenchmarkResult] {.async.} =
  ## benchmark a file
  var bench = newBenchmarkResult()
  var db = waitfor loadDatabaseForFile(filename)
  let compilation = waitfor compileFile(filename)
  result = bench
  waitfor db.close

proc goldenCommand(args: seq[string]) =
  ## cli entry
  var gold = newGolden()
  echo "golden on " & $gold.compiler

  # capture interrupts
  proc sigInt() {.noconv.} =
    quit(0)
  setControlCHook(sigInt)

  for filename in args.items:
    if not filename.appearsBenchmarkable:
      warn "i don't know how to benchmark `" & filename & "`"
      continue
    let bench = waitfor gold.benchmark(filename)
    echo $bench

when isMainModule:
  # log only warnings in release
  when defined(release) or defined(danger):
    let level = lvlWarn
  else:
    let level = lvlAll
  let logger = newConsoleLogger(useStderr=true, levelThreshold=level)
  addHandler(logger)

  dispatch goldenCommand
