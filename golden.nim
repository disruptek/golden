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

proc monitor(process: Process; invocation: var InvocationInfo) =
  ## keep a process's output streams empty, saving them into the
  ## invocation with other runtime details
  type
    Monitor = enum
      Output = "the process has some data for us on stdout"
      Errors = "the process has some data for us on stderr"
      Finished = "the process has finished"

  var
    clock = getTime()
    watcher = newSelector[Monitor]()

  # monitor whether the process has finished or produced output
  when defined(useProcessSignal):
    watcher.registerProcess(process.processId, Finished)
  watcher.registerHandle(process.outputHandle.int, {Read}, Output)
  watcher.registerHandle(process.errorHandle.int, {Read}, Errors)

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
        when not defined(useProcessSignal):
          if process.peekExitCode != -1:
            invocation.runtime.wall = getTime() - clock
            process.outputStream.drainStreamInto invocation.output.stdout
            process.errorStream.drainStreamInto invocation.output.stderr
            break
    except IOSelectorsException as e:
      # merely report errors for database safety
      stdmsg().writeLine "error talkin' to process: " & e.msg

  try:
    # cleanup the selector
    watcher.close
  except Exception as e:
    # merely report errors for database safety
    stdmsg().writeLine e.msg

  # the process has exited, but this could be useful to Process
  invocation.output.code = process.waitForExit

proc invoke(binary: FileDetail, args: seq[string] = @[]): Future[InvocationInfo] {.async.} =
  ## run a binary and yield info about its invocation
  let
    commandline = binary.path & " " & args.join(" ")
  when not defined(release) and not defined(danger):
    stdmsg().writeLine commandline
  var
    invocation = newInvocationInfo(binary, args = args)
    process = startProcess(binary.path, args = args, options = {})

  # watch the process to gather i/o and runtime details
  process.monitor(invocation)
  # cleanup the process
  process.close

  # if it failed, dump the stdout/stderr we collected,
  # report the exit code, and provide the command-line
  if invocation.output.code != 0:
    invocation.dumpFailure(commandline)
  result = invocation

proc invoke(path: string; args: varargs[string, `$`]): Future[InvocationInfo] =
  ## convenience invoke()
  var
    arguments: seq[string]
    binary = newFileDetailWithInfo(path)
  for a in args:
    arguments.add a
  result = binary.invoke(arguments)

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
        if bench.invocations.len > 4000:
          echo "sleeping for awhile"
          sleep 60*1000
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
