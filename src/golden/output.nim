import strformat
import strutils
import terminal
import json

import spec
import compilation

export terminal

# output json alongside interactive output
when defined(dumpJson):
  const dumpJson = true
else:
  const dumpJson = false

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

method `$`*(gold: GoldObject): string {.base.} =
  result = gold.name & ":" & $gold.oid & " entry " & $gold.entry

proc `$`*(detail: FileDetail): string =
  result = detail.path

proc `$`*(compiler: CompilerInfo): string =
  let digest = $compiler.binary.digest
  result = "Nim " & compiler.version
  if digest != "00000000000000000000000000000000":
    result &= " digest " & digest
  result &= " built " & $compiler.binary.mtime

proc `$`*(runtime: RuntimeInfo): string =
  result = runtime.wall.render

proc `$`*(invocation: InvocationInfo): string =
  result = invocation.commandLine

proc toJson(entry: DateTime): JsonNode =
  result = newJString entry.format(ISO8601noTZ)

method toJson(gold: GoldObject): JsonNode {.base.} =
  result = %* {
    "oid": newJString $gold.oid,
    "name": newJString gold.name,
    "description": newJString gold.description,
    "entry": gold.entry.toJson,
  }

method toJson(output: OutputInfo): JsonNode =
  result = procCall output.GoldObject.toJson
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

proc jsonOutput(golden: Golden): bool =
  let flags = golden.options.flags
  result = dumpJson or PipeOutput in flags or Interactive notin flags

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

template output*(golden: Golden; gold: GoldObject; desc: string = "") =
  if desc != "":
    gold.description = desc
  if Interactive in golden.options.flags:
    golden.output $gold
  if jsonOutput(golden):
    golden.output gold.toJson

proc output*(golden: Golden; output: OutputInfo; desc: string = "") =
  if desc != "":
    output.description = desc
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
  golden.output invocation.output, desc
  if not invocation.okay:
    new invocation.arguments
    for n in arguments:
      invocation.arguments[].add n
    golden.output "command-line:\n  " & invocation.commandLine
    invocation.arguments = nil
