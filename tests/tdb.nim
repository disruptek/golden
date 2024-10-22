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
      targets = @[exampleNim.file.path]
      storage {.used.} = golden.storageForTargets(targets)

  teardown:
    db.close

  test "assumptions":
    check exampleNim.dirty
    check storage.endsWith "/example"

  test "create, destroy once":
    let
      paths = storage.rsplit("/example", maxSplit=1)
      storagePath = paths.join("") & "/.example.golden-lmdb"
    db = waitfor golden.openDatabase(targets)
    db.close
    check existsDir(storagePath)
    golden.removeDatabase(targets)
    check not existsDir(storagePath)

  test "write":
    db = waitfor golden.openDatabase(targets)

    exampleNim.dirty = true
    db.write(exampleNim)
    check not exampleNim.dirty

    expect AssertionError:
      # because it's not dirty
      db.write(exampleNim)

  test "write, dupe, read, write":
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

    expect AssertionError:
      # because it's not dirty
      db.write(foo)

    #check foo.file.path == exampleNim.file.path
    check foo.oid == exampleNim.oid
    when defined(StoreEntry):
      check foo.entry == exampleNim.entry
    check foo.created == exampleNim.created
    check foo.file.digest == exampleNim.file.digest
    check foo.file.size == exampleNim.file.size
    check foo.file.mtime == exampleNim.file.mtime

  test "dry run":
    golden.options.flags.incl DryRun

    db = waitfor golden.openDatabase(targets)

    exampleNim.dirty = true
    expect Exception:
      db.write(exampleNim)
    check exampleNim.dirty

    # remove flag for future tests
    golden.options.flags.excl DryRun

  test "create, destroy, leak":
    let
      d = 6
      opens = d * 80

    checkpoint "expecting a leak of 2312 bytes"
    var leak = 0
    for j in 0 ..< d:
      var start = quiesceMemory("starting memory:")
      let k = opens div d
      for n in 0 ..< k:
        db = waitfor golden.openDatabase(targets)
        db.close
      var occupied = quiesceMemory("ending memory:")
      # measure the first and second values
      if leak == 0 or k < 2:
        leak = occupied - start
        continue
      checkpoint "memory leak " & $leak & " for " & $k & " opens " & $(occupied - start)
      # to see if it's changing over iteration
      check occupied - start <= opens * sizeof(pointer)

    # recreate the file so we can confirm permissions
    db = waitfor golden.openDatabase(targets)
