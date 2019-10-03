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
import lists

import cligen
import foreach

import spec
import db

type
  BenchmarkusInterruptus = IOError

  GoldenDatabase = ref object of GoldObject
    path: string
    db: DatabaseImpl

proc close(database: GoldenDatabase) {.async.} =
  ## close the database
  waitfor database.db.close

proc drainStreamInto(stream: Stream; output: var string) =
  while not stream.atEnd:
    output &= stream.readChar

proc drain(ready: ReadyKey; stream: Stream; output: var string) =
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
    stdmsg().writeLine "command-line:\n" & commandline

proc invoke(binary: FileDetail, args: seq[string] = @[]): Future[InvocationInfo] {.async.} =
  type
    Monitor = enum
      Output = "the process has some data for us on stdout"
      Errors = "the process has some data for us on stderr"
      Finished = "the process has finished"
  let
    commandline = binary.path & " " & args.join(" ")
  var
    invocation = newInvocationInfo(binary, args = args)
    process = startProcess(binary.path, args = args, options = {})
    clock = getTime()
    watcher = newSelector[Monitor]()

  # monitor whether the process has finished or produced output
  watcher.registerHandle(process.outputHandle.int, {Read}, Output)
  watcher.registerHandle(process.errorHandle.int, {Read}, Errors)
  watcher.registerProcess(process.processId, Finished)

  block running:
    try:
      while true:
        let events = watcher.select(1000)
        foreach ready in events.items of ReadyKey:
          var kind: Monitor = watcher.getData(ready.fd)
          case kind:
          of Output:
            # keep the output stream from blocking
            ready.drain(process.outputStream, invocation.output.stdout)
          of Errors:
            # keep the errors stream from blocking
            ready.drain(process.errorStream, invocation.output.stderr)
          of Finished:
            # check the clock early
            invocation.runtime.wall = getTime() - clock
            # drain any data in the streams
            process.outputStream.drainStreamInto invocation.output.stdout
            process.errorStream.drainStreamInto invocation.output.stderr
            break running
    except IOSelectorsException as e:
      # merely report errors for database safety
      stdmsg().writeLine "error talkin' to process: " & e.msg

  try:
    # cleanup the selector
    watcher.close
  except Exception as e:
    # merely report errors for database safety
    stdmsg().writeLine e.msg

  # cleanup the process
  invocation.output.code = process.waitForExit
  process.close

  # if it failed, dump the stdout/stderr we collected,
  # report the exit code, and provide the command-line
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
  ## benchmark a source file
  var bench = newBenchmarkResult()
  var db = waitfor loadDatabaseForFile(filename)
  defer:
    waitfor db.close
  try:
    let compilation = waitfor compileFile(filename)
    bench.compilations.append compilation
    while compilation.invocation.output.code == 0:
      let invocation = waitfor invoke(compilation.binary)
      bench.invocations.append invocation
      if invocation.output.code != 0:
        break
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

  for filename in args.items:
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
