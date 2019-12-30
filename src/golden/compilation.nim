import os
import asyncfutures
import asyncdispatch
import strutils
import sequtils

import spec
import invoke

proc pathToCompilationTarget*(filename: string): string =
  ## calculate the path of a source file's compiled binary output
  assert filename.endsWith ".nim"
  var (head, tail) = filename.absolutePath.normalizedPath.splitPath
  tail.removeSuffix ".nim"
  result = head / tail

proc sniffCompilerGitHash*(compiler: Gold): Future[string] {.async.} =
  ## determine the git hash of the compiler binary if possible;
  ## this should ideally compile a file to measure the version constants, too.
  const pattern = "git hash: "
  var binary = newFileDetailWithInfo(compiler.binary)
  let invocation = await invoke(binary, @["--version"])
  echo invocation.invokation.stdout
  if invocation.okay:
    for line in invocation.invokation.stdout.splitLines:
      if line.startsWith(pattern):
        let commit = line[pattern.len .. ^1]
        if commit.len == 40:
          result = commit
          break

proc newCompiler*(hint: string = ""): Gold =
  var path: string
  if hint == "":
    path = getCurrentCompilerExe()
  else:
    path = hint
  # i know, it's expensive, but this is what we have right now
  result = newGold(aCompiler)
  var binary = newFileDetailWithInfo(path)
  result.binary = binary
  result.version = NimVersion
  result.major = NimMajor
  result.minor = NimMinor
  result.patch = NimPatch
  result.chash = waitfor result.sniffCompilerGitHash()

proc newCompilation*(): Gold =
  var compiler = newGold(aCompiler)
  result = newGold(aCompilation)
  result.compilation = CompilationInfo()
  result.compiler = compiler

proc newCompilation*(compiler: var Gold): Gold =
  result = newGold(aCompilation)
  result.compilation = CompilationInfo()
  result.compiler = compiler

proc newCompilation*(compiler: var Gold; source: var Gold): Gold =
  let
    output = pathToCompilationTarget(source.file.path)

  result = newCompilation(compiler)
  var
    target = newFileDetail(output)
  result.source = source
  result.target = target

proc newCompilation*(compiler: var Gold; filename: string): Gold =
  let
    target = pathToCompilationTarget(filename)

  result = newCompilation(compiler)
  var
    source = newFileDetailWithInfo(filename)
    binary = newFileDetail(target)
  result.source = source
  result.target = binary

proc argumentsForCompilation*(compilation: var Gold; args: seq[string]): seq[string] =
  # support lazy folks
  if args.len == 0:
    result = @["c", "-d:danger"]
  elif args[0] notin ["c", "cpp", "js"]:
    result = @["c"].concat(args)
  else:
    result = args

proc compileFile*(filename: string; arguments: seq[string] = @[]): Future[Gold] {.async.} =
  ## compile a source file and yield details of the event
  var
    compiler = newCompiler()
    gold = newCompilation(compiler, filename)
    # the compilation binary (the target output) is only partially built here
    # but at least the source detail is fully built
    args = gold.argumentsForCompilation(arguments)

  # add the source filenames to compilation arguments
  for source in gold.sources:
    args.add source.file.path

  # perform the compilation
  var
    binary = newFileDetailWithInfo(compiler.binary)
    invocation = await invoke(binary, args)
  gold.invocation = invocation
  if invocation.okay:
    # populate this partially-built file detail
    var target = newFileDetailWithInfo(gold.target)
    gold.target = target
  result = gold
