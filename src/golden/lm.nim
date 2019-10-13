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

const
  ISO8601forDB* = initTimeFormat "yyyy-MM-dd\'T\'HH:mm:ss\'.\'fff"
  # we probably only need one, but
  # we might need as many as two for a migration
  MAXDBS = 2

when defined(LongWayHome):
  import posix
  {.warning: "long way home".}
when defined(Heapster):
  {.warning: "heapster".}

##[

Here's how the database works:

There are three types of objects which have three unique forms of key.

1) GoldObjects
  - every GoldObject has an oid
  - the stringified Oid is used as the key in this key/value store
  - this is a 24-char string
  - use msgpack to unpack the value into the GoldObject

2) File Checksums
  - every FileDetail has a digest representing its contents in SHA or MD5
  - this digest is used as the key in this key/value store
  - this is a 20-(or 16)-char string
  - the value retrieved is the Oid of the FileDetail object

  FileDetail is associated with
    - Compilations (source or binary)
    - Benchmarks (binary)
    - Compilers (binary)
    - Invocations (binary) -- currently NOT saved in the database

3) Git References
  - this is a 40-char string

To get data from the database, you start with any of these three keys, which
gives you your entry. This seems like an extra step, but the fact is, the data
is useless if you cannot associate it to something you have in-hand, and so you
are simply going to end up gathering that content anyway in order to confirm
that it matches a value in the database.

]##

type
  GoldenDatabase* = ref object
    path: string
    store: FileInfo
    version: ModelVersion
    db: LMDBEnv
    flags: set[GoldenFlag]
    when defined(Heapster):
      ## this won't help
      #env: ref Env
      #txn: ref Txn

  Storable = FileDetail

# these should only be used for assertions; not for export
proc isOpen(self: GoldenDatabase): bool {.inline.} = self.db != nil
proc isClosed(self: GoldenDatabase): bool {.inline.} = self.db == nil

proc close*(self: var GoldenDatabase) =
  ## close the database
  if self != nil:
    if self.isOpen:
      when defined(LongWayHome):
        goldenDebug()
        when defined(debug):
          echo "OLD CLOSE"
        envClose(self.db)
        when defined(debug):
          echo "OLD CLOSE complete"
      else:
        when defined(debug):
          echo "NO CLOSE"
      when defined(Heapster):
        when compiles(self.env):
          when defined(debug):
            echo "HEAPSTER env to nil"
          self.env = nil
      # XXX: without setting this to nil, it crashes after a few
      #      iterations...  but why?
      self.db = nil

proc removeStorage(path: string) =
  if existsDir(path):
    removeDir(path)
  assert not existsDir(path)

proc createStorage(path: string) =
  if existsDir(path):
    return
  createDir(path)
  assert existsDir(path)

proc removeDatabase*(self: var GoldenDatabase; flags: set[GoldenFlag]) =
  ## remove the database from the filesystem
  self.close
  assert self.isClosed
  if DryRun notin flags:
    removeStorage(self.path)

proc umaskFriendlyPerms*(executable: bool): Mode =
  ## compute permissions for new files which are sensitive to umask
  var mode: Mode

  # set it to 0 but read the last value
  result = umask(0)
  # set it to that value and discard zero
  discard umask(result)

  if executable:
    result = S_IWUSR.Mode or S_IRUSR.Mode or S_IXUSR.Mode or (0o777 xor result)
  else:
    result = S_IWUSR.Mode or S_IRUSR.Mode or (0o666 xor result)

proc open(self: var GoldenDatabase; path: string) =
  ## open the database
  assert self.isClosed
  when defined(LongWayHome):
    var
      flags: cuint = 0
  else:
    var
      flags: int = 0

  if DryRun in self.flags:
    flags = RdOnly
  else:
    flags = 0
    createStorage(path)
  when defined(LongWayHome):
    when defined(debug):
      echo "OPEN DB"
    let mode = umaskFriendlyPerms(executable = false)
    when defined(Heapster):
      proc heapEnv(): ref Env =
        when defined(debug):
          echo "HEAPSTER heap env"
        new result
      when compiles(self.env):
        self.env = heapEnv()
        GC_ref(self.env)
        self.db = addr self.env[]
      else:
        var env = heapEnv()
        GC_ref(env)
        self.db = addr env[]
    else:
      var e = Env()
      self.db = addr e
    assert envCreate(addr self.db) == 0
    self.db.setMaxDBs(MAXDBS)
    assert self.db.envOpen(path.cstring, flags, mode) == 0
  else:
    self.db = newLMDBEnv(path, maxdbs = MAXDBS, openflags = flags)
  goldenDebug()
  assert self.isOpen

proc newTransaction(self: GoldenDatabase): LMDBTxn =
  assert self.isOpen
  var flags: cuint
  if DryRun in self.flags:
    flags = RdOnly
  else:
    flags = 0
  #
  # i'm labelling this with the `when` simply so i can mark this as another
  # area where a memory change for LongWayHome may end up being relevant
  when true or defined(LongWayHome):
    var
      parent: LMDBTxn

    when defined(Heapster):
      proc heapTxn(): ref Txn =
        when defined(debug):
          echo "HEAPSTER heap txn"
        new result

      when compiles(self.txn):
        self.txn = heapTxn()
        GC_ref(self.txn)
        result = addr self.txn[]
      else:
        var txn = heapTxn()
        GC_ref(txn)
        result = addr txn[]
    else:
      var txn = Txn()
      result = addr txn
    assert parent == nil
    assert txnBegin(self.db, parent, flags = flags, addr result) == 0
  else:
    # but, we cannot use this with DryRun, so it's an error to try
    {.error: "this build doesn't work with DryRun".}
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
  try:
    transaction.put(handle, $gold.oid, pack(gold), NoOverWrite)
    commit(transaction)
    gold.dirty = false
  except Exception as e:
    abort(transaction)
    raise e

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
