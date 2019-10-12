import os
import asyncdispatch
import unittest
import strutils

import golden
import golden/spec
import golden/lm

suite "database":
  setup:
    var
      golden = newGolden()
      db: GoldenDatabase = nil
      exampleNim = newFileDetailWithInfo("tests/example.nim")

    let
      targets = @[exampleNim.path]
      storage {.used.} = golden.storageForTargets(targets)

  teardown:
    db.close

  test "assumptions":
    check exampleNim.dirty
    check storage.endsWith "/example"

  test "create, destroy":
    let
      paths = storage.rsplit("/example", maxSplit=1)
      storagePath = paths.join("") & "/.example.golden-lmdb"
    db = waitfor golden.openDatabase(targets)
    db.close
    db = nil
    check existsDir(storagePath)
    golden.removeDatabase(targets)
    check not existsDir(storagePath)

  test "write, read":
    var
      foo = newFileDetail("foo")
    db = waitfor golden.openDatabase(targets)

    exampleNim.dirty = true
    db.write(exampleNim)
    check not exampleNim.dirty

    # make sure we can't write duplicates
    expect Exception:
      exampleNim.dirty = true
      db.write(exampleNim)

    foo.oid = exampleNim.oid
    foo.dirty = false
    db.read(foo)
    check not foo.dirty

    check foo.path == exampleNim.path
    check foo.digest == exampleNim.digest
    check foo.size == exampleNim.size
    check foo.mtime == exampleNim.mtime

    test "dry run":
      golden.options.flags.incl DryRun

      db = waitfor golden.openDatabase(targets)

      exampleNim.dirty = true
      expect Exception:
        db.write(exampleNim)
      check exampleNim.dirty
