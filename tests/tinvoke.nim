import os
import asyncdispatch
import unittest

import golden
import golden/spec
import golden/invoke
import golden/compilation

suite "compile and invoke":
  setup:
    let
      exampleNim = newFileDetailWithInfo("tests/example.nim")
      compilation = newCompilationInfo(exampleNim.path)
      binary {.used.} = compilation.binary

  test "assumptions":
    check compilation.compiler.chash != ""
    check compilation.compiler.version != ""
    check argumentsForCompilation(@[]) == @["c", "-d:danger"]
    check argumentsForCompilation(@["umm"]) == @["c", "umm"]
    check argumentsForCompilation(@["cpp", "-d:debug"]) == @["cpp", "-d:debug"]

  test "compilation":
    let
      target = pathToCompilationTarget(exampleNim.path)
    if fileExists(target):
      removeFile(target)
    let
      simple = waitfor compileFile(exampleNim.path)
    check simple.okay
    check compilation.binary.path == target
    check compilation.binary.path.fileExists

  test "invocation":
    var invocation = waitfor invoke(binary)
    check invocation.okay
    invocation = waitfor invoke(binary, @["quit"])
    check not invocation.okay
    check invocation.output.code == 3
    invocation = waitfor invoke(binary, @["hello"])
    check invocation.okay
    check invocation.output.stdout == "world\n"
    invocation = waitfor invoke(binary, @["goodbye"])
    check invocation.output.stderr == "cruel world\n"
