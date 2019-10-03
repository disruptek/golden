import os
import times
import streams
import oids
import asyncfutures
import asyncdispatch
import strutils
import osproc
import selectors
import terminal
import logging

import cligen
import foreach

import spec
import db

type
  BenchmarkusInterruptus = Exception

  GoldenDatabase = ref object of GoldObject
    path: string
    db: DatabaseImpl

proc close(database: GoldenDatabase) {.async.} =
  ## close the database
  waitfor database.db.close

proc drainStreamInto(stream: Stream; output: var string) =
  while not stream.atEnd:
    output &= stream.readChar

proc drainReadyKey(ready: ReadyKey; stream: Stream; output: var string) =
  if Event.Read in ready.events:
    stream.drainStreamInto(output)
  elif {Event.Error} == ready.events:
    #stdmsg().writeLine "comms error: " & ready.errorCode.osErrorMsg
    discard
  else:
    assert ready.events.card == 0

proc dumpFailure(invocation: InvocationInfo; commandline: string) =
  if invocation.output.code != 0:
    if invocation.output.stdout.len != 0:
      stdmsg().writeLine invocation.output.stdout
    if invocation.output.stderr.len != 0:
      stdmsg().writeLine invocation.output.stderr
    stdmsg().writeLine "exit code: " & $invocation.output.code
    stdmsg().writeLine "our command-line:\n" & commandline

proc invoke(binary: FileDetail, args: seq[string] = @[]): Future[InvocationInfo] {.async.} =
  type
    Watch = enum Input, Output, Errors, Finished
  let
    commandline = binary.path & " " & args.join(" ")
  var
    invocation = newInvocationInfo(binary, args = args)
    process = startProcess(binary.path, args = args, options = {})
    clock = getTime()
    watcher = newSelector[Watch]()

  invocation.output = newOutputInfo()
  invocation.runtime = newRuntimeInfo()

  watcher.registerHandle(process.outputHandle.int, {Read}, Output)
  watcher.registerHandle(process.errorHandle.int, {Read}, Errors)
  watcher.registerProcess(process.processId, Finished)

  while true:
    try:
      let events = watcher.select(1000)
      foreach ready in events.items of ReadyKey:
        var kind: Watch = watcher.getData(ready.fd)
        case kind:
        of Output:
          drainReadyKey(ready, process.outputStream, invocation.output.stdout)
        of Errors:
          drainReadyKey(ready, process.errorStream, invocation.output.stderr)
        of Finished:
          process.outputStream.drainStreamInto invocation.output.stdout
          process.errorStream.drainStreamInto invocation.output.stderr
          watcher.close
        of Input:
          raise newException(Defect, "what are you doing here, little friend?")
      if process.peekExitCode != -1:
        break
    except IOSelectorsException as e:
      stdmsg().writeLine "error talkin' to process: " & e.msg
      break

  # i had to move this here.  go figure.
  invocation.output.code = process.waitForExit
  invocation.runtime.wall = getTime() - clock

  try:
    watcher.close
  except:
    discard

  if invocation.output.code != 0:
    invocation.dumpFailure(commandline)
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
  comp.invocation = waitfor invoke(compiler.binary,
                                   @["c", "-d:danger", comp.source.path])
  if comp.invocation.output.code == 0:
    comp.binary = newFileDetailWithInfo(target)
  result = comp

proc benchmark(gold: Golden; filename: string): Future[BenchmarkResult] {.async.} =
  ## benchmark a file
  var bench = newBenchmarkResult()
  var db = waitfor loadDatabaseForFile(filename)
  defer:
    await db.close
  try:
    let compilation = waitfor compileFile(filename)
    while compilation.invocation.output.code == 0:
      let invocation = waitfor invoke(compilation.binary)
      if invocation.output.code != 0:
        break
      stdmsg().writeLine $invocation.runtime
  except BenchmarkusInterruptus:
    echo "cleaning up..."
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

  for filename in args.items:
    if not filename.appearsBenchmarkable:
      warn "i don't know how to benchmark `" & filename & "`"
      continue
    discard waitfor gold.benchmark(filename)

when isMainModule:
  # log only warnings in release
  when defined(release) or defined(danger):
    let level = lvlWarn
  else:
    let level = lvlAll
  let logger = newConsoleLogger(useStderr=true, levelThreshold=level)
  addHandler(logger)

  dispatch goldenCommand
