import times
import strformat
import strutils
import terminal

import spec

proc interactive*(gold: Golden): bool =
  stdmsg().isatty

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

method `$`*(gold: GoldObject): string =
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

proc `$`*(bench: BenchmarkResult): string =
  result = $bench.GoldObject
  if bench.invocations.len > 0:
    let invocation = bench.invocations.first
    result &= "\n" & $invocation
  result &= "\ncompilation(s) -- " & $bench.compilations
  result &= "\n invocation(s) -- " & $bench.invocations

proc dumpOutput*(invocation: InvocationInfo) =
  ## generally used to output a failed invocation
  if invocation.output.stdout.len != 0:
    stdmsg().writeLine invocation.output.stdout
  if invocation.output.stderr.len != 0:
    stdmsg().writeLine invocation.output.stderr
  stdmsg().writeLine "exit code: " & $invocation.output.code
  stdmsg().writeLine "command-line:\n" & invocation.commandLine
