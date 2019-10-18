import os
import asyncdispatch
import unittest
import strutils

import golden
import golden/spec
import golden/compilation

suite "spec":
  setup:
    var
      golden = newGolden()
      exampleNim = newFileDetailWithInfo("tests/example.nim")
      nimPath = newFileDetailWithInfo(getCurrentCompilerExe())
      compiler = newCompiler()
    let
      targets = @[exampleNim.file.path]
      storage {.used.} = golden.storageForTargets(targets)

  test "set compiler":
    nimPath.compiler = compiler
    let c = nimPath[aCompiler]
    check compiler.oid == c.oid
