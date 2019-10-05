import asyncdispatch
import unittest

import golden
import golden/spec
import golden/invoke

suite "invoke":
  setup:
    let compilation = waitfor compileFile("tests/example.nim")
    check compilation.okay

  test "compilation":
    check compilation.okay

  test "invocation":
    var invocation = waitfor invoke(compilation.binary)
    check invocation.okay
    invocation = waitfor invoke(compilation.binary, @["quit"])
    check not invocation.okay
    check invocation.output.code == 3
