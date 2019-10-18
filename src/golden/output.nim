import strformat
import times
import strutils
import terminal
import json

export terminal

proc render*(d: Duration): string {.raises: [].} =
  ## cast a duration to a nice string
  let
    n = d.inNanoseconds
    ss = (n div 1_000_000_000) mod 1_000
    ms = (n div 1_000_000) mod 1_000
    us = (n div 1_000) mod 1_000
    ns = (n div 1) mod 1_000
  try:
    return fmt"{ss:>3}s {ms:>3}ms {us:>3}μs {ns:>3}ns"
  except:
    return [$ss, $ms, $us, $ns].join(" ")

proc `$`*(detail: FileDetail): string =
  result = detail.path

proc toJson(invokation: InvocationInfo): JsonNode =
  result = newJObject()
  result["stdout"] = newJString invokation.stdout
  result["stderr"] = newJString invokation.stderr
  result["code"] = newJInt invokation.code

proc output*(golden: Golden; content: string; style: set[terminal.Style] = {}; fg: ForegroundColor = fgDefault; bg: BackgroundColor = bgDefault) =
  let
    flags = golden.options.flags
    fh = stdmsg()
  if NeverOutput in golden.options.flags:
    return
  if ColorConsole in flags or PipeOutput notin flags:
    fh.setStyle style
    fh.setForegroundColor fg
    fh.setBackgroundColor bg
  fh.writeLine content

proc output*(golden: Golden; content: JsonNode) =
  var ugly: string
  if NeverOutput in golden.options.flags:
    return
  ugly.toUgly(content)
  stdout.writeLine ugly

proc output*(golden: Golden; invocation: Gold; desc: string = "";
             arguments: seq[string] = @[]) =
  ## generally used to output a failed invocation
  let invokation = invocation.invokation
  if ColorConsole in golden.options.flags:
    if invokation.stdout.len > 0:
      golden.output invokation.stdout, fg = fgCyan
    if invokation.stderr.len > 0:
      golden.output invokation.stderr, fg = fgRed
    if invokation.code != 0:
      golden.output "exit code: " & $invokation.code
  if jsonOutput(golden):
    golden.output invokation.toJson
  if invokation.code != 0:
    new invokation.arguments
    for n in arguments:
      invokation.arguments[].add n
    golden.output "command-line:\n  " & invocation.commandLine
    invokation.arguments = nil
