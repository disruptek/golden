import os
import asyncdispatch
import unittest

import golden/spec
import golden/invoke
import golden/compilation

suite "compile and invoke":
  setup:
    let
      exampleNim = newFileDetailWithInfo("tests/example.nim")
    var
      compiler = newCompiler()
      gold {.used.} = newCompilation(compiler, exampleNim.file.path)

  test "assumptions":
    check gold.compiler.chash != ""
    check gold.compiler.version != ""
    check gold.argumentsForCompilation(@[]) == @["c", "-d:danger"]
    check gold.argumentsForCompilation(@["umm"]) == @["c", "umm"]
    check gold.argumentsForCompilation(@["cpp", "-d:debug"]) == @["cpp", "-d:debug"]

  test "compilation":
    let
      target = pathToCompilationTarget(exampleNim.file.path)
    if fileExists(target):
      removeFile(target)
    let
      args = @["c", "--outdir=" & target.parentDir]
      simple = waitfor compileFile(exampleNim.file.path, args)
    check simple.okay
    check simple.target.file.path == target
    check simple.target.file.path.fileExists

  test "invocation":
    var binary = gold.target
    var invocation = waitfor invoke(binary)
    check invocation.okay
    invocation = waitfor invoke(binary, @["quit"])
    check not invocation.okay
    check invocation.invokation.code == 3
    invocation = waitfor invoke(binary, @["hello"])
    check invocation.okay
    check invocation.invokation.stdout == "world\n"
    invocation = waitfor invoke(binary, @["goodbye"])
    check invocation.invokation.stderr == "cruel world\n"
