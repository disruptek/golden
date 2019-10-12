#[

we're not gonna do much error checking, etc.

]#
import os
import times
import asyncdispatch
import asyncfutures
import strutils
import options
import posix

import msgpack4nim
import lmdb

import fsm
import spec
import benchmark
import running
import linkedlists

const ISO8601forDB* = initTimeFormat "yyyy-MM-dd\'T\'HH:mm:ss\'.\'fff"

const LongWayHome = true

type
  GoldenDatabase* = ref object
    path: string
    store: FileInfo
    version: ModelVersion
    env: Env
    db: LMDBEnv
    flags: set[GoldenFlag]

  Storable = FileDetail

# these should only be used for assertions; not for export
proc isOpen(self: GoldenDatabase): bool {.inline.} = self.db != nil
proc isClosed(self: GoldenDatabase): bool {.inline.} = self.db == nil

proc close*(self: var GoldenDatabase) =
  ## close the database
  if self != nil:
    if self.isOpen:
      when defined(debugDoubleFree):
        {.warning: "this build for debugging double free in database".}
        # FIXME: free(): double free detected in tcache 2
        envClose(self.db)
      self.db = nil

proc removeDatabase*(self: var GoldenDatabase; flags: set[GoldenFlag]) =
  ## remove the database from the filesystem
  self.close
  assert self.isClosed
  if DryRun notin flags:
    if existsDir(self.path):
      removeDir(self.path)

proc open(self: var GoldenDatabase; path: string) =
  ## open the database
  assert self.isClosed
  var
    flags: cuint = 0
    #mode: Mode = umask(0) xor 0x
    mode: Mode = S_IWUSR.Mode or S_IRUSR.Mode

  if DryRun in self.flags:
    flags = RdOnly
  else:
    if not path.existsDir:
      createDir path
  # we probably only need one, but
  # we might need as many as two for a migration

  when LongWayHome:
    self.env = Env()
    self.db = addr self.env
    assert envCreate(addr self.db) == 0
    self.db.setMaxDBs(2)
    assert self.db.envOpen(path.cstring, flags, mode) == 0
  else:
    self.db = newLMDBEnv(path, maxdbs = 2, openflags = flags.int)
  assert self.isOpen

proc newTransaction(self: GoldenDatabase): LMDBTxn =
  assert self.isOpen
  var flags: cuint
  if DryRun in self.flags:
    flags = RdOnly
  else:
    flags = 0
  when LongWayHome:
    var
      parent: LMDBTxn
      txn = Txn()
    result = addr txn
    assert parent == nil
    assert txnBegin(self.db, parent, flags = flags, addr result) == 0
  else:
    result = newTxn(self.db)
  assert result != nil

proc newHandle(self: GoldenDatabase; transaction: LMDBTxn;
               version: ModelVersion): Dbi =
  assert self.isOpen
  var flags: cuint
  if DryRun in self.flags:
    flags = 0
  else:
    flags = Create
  result = dbiOpen(transaction, $ord(version), flags)

proc newHandle(self: GoldenDatabase; transaction: LMDBTxn): Dbi =
  result = self.newHandle(transaction, self.version)

proc getModelVersion(self: GoldenDatabase): ModelVersion =
  assert self.isOpen
  result = ModelVersion.low
  let
    transaction = self.newTransaction
  defer:
    abort(transaction)

  for version in countDown(ModelVersion.high, ModelVersion.low):
    try:
      # just try to open all the known versions
      discard self.newHandle(transaction, version)
      # if we were successful, that's our version
      result = version
      break
    except Exception:
      discard

proc setModelVersion(self: GoldenDatabase; version: ModelVersion) =
  ## noop; the version is set by any write
  assert self.isOpen

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

  proc utcTzInfo(time: Time): ZonedTime =
    result = ZonedTime(utcOffset: 0 * 3600, isDst: false, time: time)

  let tzUTC* = newTimezone("Somewhere/UTC", utcTzInfo, utcTzInfo)

proc fetchViaOid(transaction: LMDBTxn;
                 handle: Dbi; oid: Oid): Option[string] =
  defer:
    abort(transaction)
  return some(transaction.get(handle, $oid))

proc fetchVia*(self: GoldenDatabase; oid: Oid): Option[string] =
  assert self.isOpen
  let
    transaction = self.newTransaction
    handle = self.newHandle(transaction)
  result = fetchViaOid(transaction, handle, oid)

proc read*[T: Storable](self: GoldenDatabase; gold: var T) =
  assert self.isOpen
  assert not gold.dirty
  var
    transaction = self.newTransaction
    handle = self.newHandle(transaction)
  defer:
    abort(transaction)
  let existing = transaction.get(handle, $gold.oid)
  unpack(existing, gold)
  gold.dirty = false

proc write*[T: Storable](self: GoldenDatabase; gold: var T) =
  assert self.isOpen
  assert gold.dirty
  let
    transaction = self.newTransaction
    handle = self.newHandle(transaction)
  defer:
    abort(transaction)
  transaction.put(handle, $gold.oid, pack(gold), NoOverWrite)
  commit(transaction)
  gold.dirty = false

proc storagePath(filename: string): string =
  ## make up a good path for the database file
  var (head, tail) = filename.absolutePath.normalizedPath.splitPath
  # we're gonna assume that if you are pointing to a .golden-lmdb,
  # and you named/renamed it, that you might not want the leading `.`
  if not filename.endsWith(".golden-lmdb"):
    tail = "." & tail & ".golden-lmdb"
  result = head / tail

proc open*(filename: string; flags: set[GoldenFlag]): Future[GoldenDatabase] {.async.} =
  ## instantiate a database using the filename
  new result
  result.db = nil
  result.path = storagePath(filename)
  result.flags = flags
  result.open(result.path)
  result.version = result.upgradeDatabase()
  result.store = getFileInfo(result.path)
