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

proc `$`*(runtime: RuntimeInfo): string =
  result = runtime.wall.render

proc `$`*(invocation: InvocationInfo): string =
  result = invocation.commandLine

proc toJson(output: OutputInfo): JsonNode =
  result = newJObject()
  result["stdout"] = newJString output.stdout
  result["stderr"] = newJString output.stderr
  result["code"] = newJInt output.code

proc `$`*(output: OutputInfo): string =
  if output.stdout.len != 0:
    result &= output.stdout
  if output.stderr.len != 0:
    if result != "":
      result &= "\n"
    result &= output.stderr
  if result != "":
    result &= "\n"
  result &= "exit code: " & $output.code

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

proc output*(golden: Golden; output: OutputInfo) =
  if ColorConsole in golden.options.flags:
    if output.stdout.len > 0:
      golden.output output.stdout, fg = fgCyan
    if output.stderr.len > 0:
      golden.output output.stderr, fg = fgRed
    if output.code != 0:
      golden.output "exit code: " & $output.code
  if jsonOutput(golden):
    golden.output output.toJson

proc output*(golden: Golden; invocation: InvocationInfo; desc: string = "";
             arguments: seq[string] = @[]) =
  ## generally used to output a failed invocation
  golden.output invocation.output
  if invocation.output.code != 0:
    new invocation.arguments
    for n in arguments:
      invocation.arguments[].add n
    golden.output "command-line:\n  " & invocation.commandLine
    invocation.arguments = nil
