import strformat
import strutils
import terminal
import json

import spec

# output json alongside interactive output
when defined(dumpJson):
  const dumpJson = true
else:
  const dumpJson = false

const ISO8601 = initTimeFormat "yyyy-MM-dd\'T\'HH:mm:ss\'.\'fff\'Z\'"

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
  result &= " built " & $compiler.binary.info.lastWriteTime

proc `$`*(runtime: RuntimeInfo): string =
  result = runtime.wall.render

proc `$`*(invocation: InvocationInfo): string =
  result = $invocation.binary
  result &= invocation.arguments.join(" ")

proc `$`*(running: RunningResult): string =
  result = $running.wall

proc `$`*(bench: BenchmarkResult): string =
  result = $bench.GoldObject
  if bench.invocations.len > 0:
    let invocation = bench.invocations.first
    result &= "\n" & $invocation
  result &= "\ncompilation(s) -- " & $bench.compilations
  result &= "\n invocation(s) -- " & $bench.invocations

proc toJson(entry: DateTime): JsonNode =
  result = newJString entry.format(ISO8601)

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
  result = dumpJson or golden.pipingOutput or not golden.interactive

proc output*(golden: Golden; content: string) =
  stdmsg().writeLine content

proc output*(golden: Golden; content: JsonNode) =
  var ugly: string
  ugly.toUgly(content)
  stdout.writeLine ugly

template output*(golden: Golden; gold: GoldObject; desc: string = "") =
  if desc != "":
    gold.description = desc
  if golden.interactive:
    golden.output $gold
  if jsonOutput(golden):
    golden.output gold.toJson

proc output*(golden: Golden; output: OutputInfo; desc: string = "") =
  if golden.interactive:
    golden.output output.stdout
    golden.output output.stderr
    golden.output "exit code: " & $output.code
  if jsonOutput(golden):
    golden.output output.toJson

proc output*(golden: Golden; invocation: InvocationInfo; desc: string = "") =
  ## generally used to output a failed invocation
  let message = "command-line:\n  " & invocation.commandLine
  golden.output invocation.output, desc
  golden.output message
