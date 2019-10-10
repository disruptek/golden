import os
import asyncfutures
import asyncdispatch
import strutils
import sequtils

import spec
import invoke

type
  CompilerInfo* = ref object of GoldObject
    binary*: FileDetail
    version*: string
    major*: int
    minor*: int
    patch*: int
    chash*: string

  CompilationInfo* = ref object of GoldObject
    compiler*: CompilerInfo
    invocation*: InvocationInfo
    source*: FileDetail
    binary*: FileDetail

proc newCompilerInfo*(hint: string = ""): CompilerInfo =
  var path: string
  new result
  result.init "compiler"
  result.version = NimVersion
  result.major = NimMajor
  result.minor = NimMinor
  result.patch = NimPatch
  if hint == "":
    path = getCurrentCompilerExe()
  else:
    path = hint
  result.binary = newFileDetailWithInfo(path)

proc okay*(compilation: CompilationInfo): bool =
  result = compilation.invocation.okay

proc pathToCompilationTarget(filename: string): string =
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
    for line in invocation.output.stdout.splitLines:
      if line.startsWith(pattern):
        let commit = line[pattern.len .. ^1]
        if commit.len == 40:
          result = commit
          break

proc argumentsForCompilation*(args: seq[string]): seq[string] =
  # support lazy folks
  if args.len == 0:
    result = @["c", "-d:danger"]
  elif args[0] notin ["c", "cpp", "js"]:
    result = @["c"].concat(args)
  else:
    result = args

proc newCompilationInfo*(compiler: CompilerInfo = nil): CompilationInfo =
  new result
  result.init "compile"
  result.compiler = compiler
  if result.compiler == nil:
    result.compiler = newCompilerInfo()

proc newCompilationInfo*(filename: string; compiler: CompilerInfo = nil): CompilationInfo =
  let
    target = pathToCompilationTarget(filename)

  result = newCompilationInfo(compiler)
  result.source = newFileDetailWithInfo(filename)
  result.binary = newFileDetail(target)
  # i'm lazy, okay?  cache your compiler to avoid this.
  if compiler == nil:
    result.compiler.chash = waitfor result.compiler.sniffCompilerGitHash

proc compileFile*(filename: string; arguments: seq[string]): Future[CompilationInfo] {.deprecated, async.} =
  ## compile a source file and yield details of the event
  var
    comp = newCompilationInfo()
    args = arguments
  let
    target = pathToCompilationTarget(filename)
    compiler = comp.compiler

  # support lazy folks
  if arguments.len == 0:
    args = @["c", "-d:danger"]
  elif arguments[0] notin ["c", "cpp", "js"]:
    args = @["c"].concat(args)

  comp.source = newFileDetailWithInfo(filename)
  args.add comp.source.path
  comp.invocation = await invoke(compiler.binary, args)
  if comp.invocation.okay:
    comp.binary = newFileDetailWithInfo(target)
  result = comp
