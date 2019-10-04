import strutils
import asyncdispatch
import asyncfutures
import streams
import times
import osproc
import selectors

import foreach

import spec

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
  if not invocation.okay:
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
    let signal = watcher.registerProcess(process.processId, Finished)
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
    when defined(useProcessSignal) and not defined(debugFdLeak):
      watcher.unregister signal
    watcher.close
  except Exception as e:
    # merely report errors for database safety
    stdmsg().writeLine e.msg

  # the process has exited, but this could be useful to Process
  invocation.output.code = process.waitForExit

proc invoke*(binary: FileDetail, args: seq[string] = @[]): Future[InvocationInfo] {.async.} =
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
  if not invocation.okay:
    invocation.dumpFailure(commandline)
  result = invocation

proc invoke*(path: string; args: varargs[string, `$`]): Future[InvocationInfo] =
  ## convenience invoke()
  var
    arguments: seq[string]
    binary = newFileDetailWithInfo(path)
  for a in args:
    arguments.add a
  result = binary.invoke(arguments)
