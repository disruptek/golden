import os
import asyncfutures
import asyncdispatch
import strutils
import sequtils

import spec
import invoke

proc newCompilerInfo*(hint: string = ""): Gold =
  var path: string
  result = newGold(aCompiler)
  result.compiler = CompilerInfo(version: NimVersion,
                                 major: NimMajor,
                                 minor: NimMinor,
                                 patch: NimPatch)
  if hint == "":
    path = getCurrentCompilerExe()
  else:
    path = hint
  result.compiler.binary = newFileDetailWithInfo(path)

proc pathToCompilationTarget*(filename: string): string =
  ## calculate the path of a source file's compiled binary output
  assert filename.endsWith ".nim"
  var (head, tail) = filename.absolutePath.normalizedPath.splitPath
  tail.removeSuffix ".nim"
  result = head / tail

proc sniffCompilerGitHash*(compiler: CompilerInfo): Future[string] {.async.} =
  ## determine the git hash of the compiler binary if possible;
  ## this should ideally compile a file to measure the version constants, too.
  const pattern = "git hash: "
  let invocation = await invoke(compiler.binary, @["--version"])
  if invocation.okay:
    for line in invocation.invocation.output.stdout.splitLines:
      if line.startsWith(pattern):
        let commit = line[pattern.len .. ^1]
        if commit.len == 40:
          result = commit
          break

proc sniffCompilerGitHash*(gold: Gold): Future[string] {.async.} =
  ## determine the git hash of the compiler binary if possible;
  ## this should ideally compile a file to measure the version constants, too.
  assert gold.compiler != nil
  result = await sniffCompilerGitHash(gold.compiler)

proc argumentsForCompilation*(args: seq[string]): seq[string] =
  # support lazy folks
  if args.len == 0:
    result = @["c", "-d:danger"]
  elif args[0] notin ["c", "cpp", "js"]:
    result = @["c"].concat(args)
  else:
    result = args

proc `compiler=`*(compilation: var CompilationInfo; compiler: Gold) =
  if compiler == nil:
    compilation.compiler = newCompilerInfo()
  else:
    assert compiler.kind == aCompiler
    assert compiler.compiler != nil
    compilation.compiler = compiler
  assert compilation.compiler != nil
  assert compilation.compiler.compiler != nil

proc `invocation=`*(compilation: var CompilationInfo; invocation: Gold) =
  assert invocation != nil
  assert invocation.kind == anInvocation
  assert invocation.invocation != nil
  compilation.invocation = invocation

proc `source=`*(compilation: var CompilationInfo; source: Gold) =
  assert source != nil
  assert source.kind == aFile
  assert source.file != nil
  compilation.source = source

proc `binary=`*(compilation: var CompilationInfo; binary: Gold) =
  assert binary != nil
  assert binary.kind == aFile
  assert binary.file != nil
  compilation.binary = binary

proc newCompilationInfo*(compiler: Gold = nil): Gold =
  result = newGold(aCompilation)
  result.compilation = CompilationInfo()
  `compiler=`(result.compilation, compiler)

proc fetchHash(gold: var Gold) =
  assert gold != nil
  assert gold.kind == aCompiler
  assert gold.compiler != nil
  gold.compiler.chash = waitfor sniffCompilerGitHash(gold)

proc newCompilationInfo*(filename: string; compiler: Gold = nil): Gold =
  let
    target = pathToCompilationTarget(filename)

  result = newCompilationInfo(compiler)
  result.compilation.source = newFileDetailWithInfo(filename)
  result.compilation.binary = newFileDetail(target)
  # i'm lazy, okay?  cache your compiler to avoid this.
  if compiler == nil:
    result.compilation.compiler.fetchHash()

proc compileFile*(filename: string; arguments: seq[string] = @[]): Future[Gold] {.async.} =
  ## compile a source file and yield details of the event
  var
    gold = newCompilationInfo(filename)
    compilation = gold.compilation
    compiler = compilation.compiler.compiler
    # the compilation binary (the target output) is only partially built here
    # but at least the source detail is fully built
    args = argumentsForCompilation(arguments)

  # add the source filename to compilation arguments
  args.add compilation.source.file.path

  # perform the compilation
  compilation.invocation = await invoke(compiler.binary, args)
  if compilation.invocation.okay:
    # populate this partially-built file detail
    compilation.binary = newFileDetailWithInfo(compilation.binary.file.path)
  result = gold
