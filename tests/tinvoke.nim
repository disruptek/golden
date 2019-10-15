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
      gold = newCompilationInfo(exampleNim.file.path)
      binary {.used.} = gold.compilation.binary

  test "assumptions":
    check gold.compilation.compiler.compiler.chash != ""
    check gold.compilation.compiler.compiler.version != ""
    check argumentsForCompilation(@[]) == @["c", "-d:danger"]
    check argumentsForCompilation(@["umm"]) == @["c", "umm"]
    check argumentsForCompilation(@["cpp", "-d:debug"]) == @["cpp", "-d:debug"]

  test "compilation":
    let
      target = pathToCompilationTarget(exampleNim.file.path)
    if fileExists(target):
      removeFile(target)
    let
      simple = waitfor compileFile(exampleNim.file.path)
    check simple.okay
    check simple.compilation.binary.file.path == target
    check simple.compilation.binary.file.path.fileExists

  test "invocation":
    var invocation = waitfor invoke(binary)
    check invocation.okay
    invocation = waitfor invoke(binary, @["quit"])
    check not invocation.okay
    check invocation.invocation.output.code == 3
    invocation = waitfor invoke(binary, @["hello"])
    check invocation.okay
    check invocation.invocation.output.stdout == "world\n"
    invocation = waitfor invoke(binary, @["goodbye"])
    check invocation.invocation.output.stderr == "cruel world\n"
