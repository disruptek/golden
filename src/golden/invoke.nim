import strutils
import asyncdispatch
import asyncfutures
import streams
import times
import osproc
import selectors

import foreach

import spec

type
  Monitor = enum
    Output = "the process has some data for us on stdout"
    Errors = "the process has some data for us on stderr"
    Finished = "the process has finished"

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

when declared(Tms):
  from posix import nil
  template cpuMark(gold: typed; invocation: typed) =
    discard posix.times(addr invocation.cpu)
  template cpuPreWait(gold: typed; invocation: typed) =
    var tms = Tms()
    discard posix.times(addr tms)
    invocation.cpu.tms_utime = tms.tms_utime - invocation.cpu.tms_utime
    invocation.cpu.tms_stime = tms.tms_stime - invocation.cpu.tms_stime
    invocation.cpu.tms_cutime = tms.tms_cutime - invocation.cpu.tms_cutime
    invocation.cpu.tms_cstime = tms.tms_cstime - invocation.cpu.tms_cstime
  template cpuPostWait(gold: typed; invocation: typed) = discard
else:
  from posix import Rusage, Timeval, getrusage, RUSAGE_CHILDREN
  proc cpuMark(gold: Gold; invocation: var InvocationInfo) =
    invocation.cpu = Rusage()
    let ret = getrusage(RUSAGE_CHILDREN, addr invocation.cpu)
    assert ret == 0

  proc `$`*(t: Timeval): string =
    ## convenience
    result = $(t.tv_sec.float64 + (t.tv_usec.float64 / 1_000_000) )

  proc sub(a: Timeval; b: Timeval): Timeval =
    result.tv_sec = posix.Time(a.tv_sec.int - b.tv_sec.int)
    result.tv_usec = a.tv_usec.int - b.tv_usec.int
    if result.tv_usec < 0:
      result.tv_sec.dec
      result.tv_usec.inc 1_000_000

  proc cpuPreWait(gold: Gold; invocation: var InvocationInfo) =
    discard

  proc cpuPostWait(gold: Gold; invocation: var InvocationInfo) =
    var
      ru = Rusage()
    let ret = getrusage(RUSAGE_CHILDREN, addr ru)
    assert ret == 0
    invocation.cpu.ru_utime = sub(ru.ru_utime, invocation.cpu.ru_utime)
    invocation.cpu.ru_stime = sub(ru.ru_stime, invocation.cpu.ru_utime)

proc monitor(gold: var Gold; process: Process) =
  ## keep a process's output streams empty, saving them into the
  ## invocation with other runtime details
  var
    clock = getTime()
    watcher = newSelector[Monitor]()
    invocation = gold.invokation

  # monitor whether the process has finished or produced output
  when defined(useProcessSignal):
    let signal = watcher.registerProcess(process.processId, Finished)
  watcher.registerHandle(process.outputHandle.int, {Event.Read}, Output)
  watcher.registerHandle(process.errorHandle.int, {Event.Read}, Errors)

  block running:
    try:
      while true:
        let events = watcher.select(1000)
        foreach ready in events.items of ReadyKey:
          var kind: Monitor = watcher.getData(ready.fd)
          case kind:
          of Output:
            # keep the output stream from blocking
            ready.drain(process.outputStream, invocation.stdout)
          of Errors:
            # keep the errors stream from blocking
            ready.drain(process.errorStream, invocation.stderr)
          of Finished:
            # check the clock and cpu early
            cpuPreWait(gold, invocation)
            invocation.wall = getTime() - clock
            # drain any data in the streams
            process.outputStream.drainStreamInto invocation.stdout
            process.errorStream.drainStreamInto invocation.stderr
            break running
        when not defined(useProcessSignal):
          if process.peekExitCode != -1:
            # check the clock and cpu early
            cpuPreWait(gold, invocation)
            invocation.wall = getTime() - clock
            process.outputStream.drainStreamInto invocation.stdout
            process.errorStream.drainStreamInto invocation.stderr
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
  # and in fact is needed for Rusage
  invocation.code = process.waitForExit
  cpuPostWait(gold, invocation)

proc invoke*(exe: Gold, args: seq[string] = @[]): Future[Gold] {.async.} =
  ## run a binary and yield info about its invocation
  var
    gold = newInvocation(exe, args = nil)
    binary = gold.binary

  # mark the current cpu time
  cpuMark(gold, gold.invokation)

  var
    process = startProcess(binary.file.path, args = args, options = {})

  # watch the process to gather i/o and runtime details
  gold.monitor(process)
  # cleanup the process
  process.close

  result = gold

proc invoke*(path: string; args: varargs[string, `$`]): Future[Gold] =
  ## convenience invoke()
  var
    arguments: seq[string]
    binary = newFileDetailWithInfo(path)
  for a in args.items:
    arguments.add a
  result = binary.invoke(arguments)
