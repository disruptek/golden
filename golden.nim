import os
import times
import oids
import asyncfutures
import asyncdispatch
import strutils
import logging

import cligen

import spec
import db

type
  GoldenDatabase = ref object of GoldObject
    path: string
    db: DatabaseImpl

proc close(database: GoldenDatabase) {.async.} =
  ## close the database
  waitfor database.db.close

proc loadDatabaseForFile(filename: string): Future[GoldenDatabase] {.async.} =
  ## load a database using a filename
  new result
  result.initGold "db"
  result.path = filename
  result.db = await newDatabaseImpl(result.path)

proc benchmark(gold: Golden; filename: string): Future[BenchmarkResult] {.async.} =
  ## benchmark a file
  var bench = newBenchmarkResult()
  var db = waitfor loadDatabaseForFile(filename)
  result = bench
  waitfor db.close

proc goldenCommand(args: seq[string]) =
  ## cli entry
  var gold = newGolden()
  echo "golden on " & $gold.compiler

  # capture interrupts
  proc sigInt() {.noconv.} =
    quit(0)
  setControlCHook(sigInt)

  for filename in args.items:
    if not filename.appearsBenchmarkable:
      warn "i don't know how to benchmark `" & filename & "`"
      continue
    let bench = waitfor gold.benchmark(filename)
    echo $bench

when isMainModule:
  # log only warnings in release
  when defined(release) or defined(danger):
    let level = lvlWarn
  else:
    let level = lvlAll
  let logger = newConsoleLogger(useStderr=true, levelThreshold=level)
  addHandler(logger)

  dispatch goldenCommand
