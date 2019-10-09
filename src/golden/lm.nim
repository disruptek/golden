#[

we're not gonna do much error checking, etc.

]#
import os
import times
import asyncdispatch
import asyncfutures
import strutils
import options

import msgpack4nim
import lmdb

import fsm
import spec
import benchmark
import running
import linkedlists

const ISO8601forDB* = initTimeFormat "yyyy-MM-dd\'T\'HH:mm:ss\'.\'fff"

type
  GoldenDatabase* = ref object
    path: string
    store: FileInfo
    version: ModelVersion
    db: LMDBEnv

  Storable = FileDetail

proc close*(self: GoldenDatabase) {.async.} =
  ## close the database
  envClose(self.db)

proc open(self: GoldenDatabase; path: string) {.async.} =
  ## open the database
  if not path.existsDir:
    createDir path
  # we probably only need one, but
  # we might need as many as two for a migration
  self.db = newLMDBEnv(path, maxdbs = 2)

proc getModelVersion(self: GoldenDatabase): ModelVersion =
  result = ModelVersion.low
  let transaction = newTxn(self.db)
  defer:
    abort(transaction)

  for version in countDown(ModelVersion.high, ModelVersion.low):
    try:
      # just try to open all the known versions
      discard transaction.dbiOpen($ord(version), 0.cuint)
      # if we were successful, that's our version
      result = version
      break
    except Exception:
      discard

proc setModelVersion(self: GoldenDatabase; version: ModelVersion) =
  ## noop; the version is set by any write
  return

proc upgradeDatabase*(self: GoldenDatabase): ModelVersion =
  result = self.getModelVersion
  if result == ModelVersion.high:
    return
  var mach = newMachine[ModelVersion, ModelEvent](result)
  mach.addTransition v0, Upgrade, v1, proc () =
    self.setModelVersion(v1)

  while result != ModelVersion.high:
    mach.process Upgrade
    result = mach.getCurrentState

when false:
  proc parseDuration(text: string): Duration =
    let f = text.parseFloat
    result = initDuration(nanoseconds = int64(billion * f))

  method renderTimestamp(gold: GoldObject): string {.base.} =
    ## turn a datetime into a string for the db
    gold.entry.inZone(utc()).format(ISO8601forDB)

  template loadTimestamp(gold: typed; datetime: string) =
    ## parse a db timestamp into a datetime
    gold.entry = datetime.parse(ISO8601forDB).inZone(local())

#proc pack_type*[ByteStream](s: ByteStream; x: GoldObject) =
#  s.pack(x.oid)
#  s.pack(x.entry)

proc utcTzInfo(time: Time): ZonedTime =
  result = ZonedTime(utcOffset: 0 * 3600, isDst: false, time: time)

let tzUTC* = newTimezone("Somewhere/UTC", utcTzInfo, utcTzInfo)

proc pack_type*[ByteStream](s: ByteStream; x: Timezone) =
  s.pack(x.name)

proc unpack_type*[ByteStream](s: ByteStream; x: var Timezone) =
  s.unpack_type(x.name)
  case x.name:
  of "LOCAL":
    x = local()
  of "UTC":
    x = utc()
  else:
    raise newException(Defect, "dunno how to unpack timezone `" & x.name & "`")

proc fetchViaOid(transaction: LMDBTxn;
                   handle: Dbi; oid: Oid): Option[string] =
  defer:
    abort(transaction)
  try:
    return some(transaction.get(handle, $oid))
  except Exception as e:
    stdmsg().writeLine "read: " & e.msg

proc fetchViaOid(self: GoldenDatabase; oid: Oid): Option[string] =
  let
    transaction = newTxn(self.db)
    handle = transaction.dbiOpen($ord(self.version), CREATE)
  result = fetchViaOid(transaction, handle, oid)

#template write*(self: GoldenDatabase; gold: typed) =
proc read*[T: Storable](self: GoldenDatabase; gold: var T) =
  if not gold.dirty:
    return
  let
    transaction = newTxn(self.db)
    handle = transaction.dbiOpen($ord(self.version), CREATE)
  defer:
    abort(transaction)
  try:
    let existing = transaction.get(handle, $gold.oid)
    unpack(existing, gold)
  except Exception as e:
    stdmsg().writeLine "read: " & e.msg

proc write*[T: Storable](self: GoldenDatabase; gold: var T) =
  if not gold.dirty:
    return
  let
    transaction = newTxn(self.db)
    handle = transaction.dbiOpen($ord(self.version), CREATE)
  try:
    transaction.put(handle, $gold.oid, pack(gold), 0)
    commit(transaction)
    gold.dirty = false
  except Exception as e:
    stdmsg().writeLine "write: " & e.msg
    abort(transaction)

proc storagePath(filename: string): string =
  ## make up a good path for the database file
  var (head, tail) = filename.absolutePath.normalizedPath.splitPath
  if not filename.endsWith(".golden-lmdb"):
    tail = "." & tail & ".golden-lmdb"
  result = head / tail

proc open*(filename: string): Future[GoldenDatabase] {.async.} =
  ## instantiate a database using the filename
  new result
  result.path = storagePath(filename)
  await result.open(result.path)
  result.version = result.upgradeDatabase()
  result.store = getFileInfo(result.path)
