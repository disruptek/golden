#[

we're not gonna do much error checking, etc.

]#
import os
import times
import asyncdispatch
import asyncfutures
import strutils

import db_sqlite

import fsm
import spec

const ISO8601forDB* = initTimeFormat "yyyy-MM-dd\'T\'HH:mm:ss\'.\'fff"

type
  SyncResult* = enum
    SyncOkay
    SyncRead
    SyncWrite

  DatabaseTables* = enum
    Meta
    Compilers = "CompilerInfo"
    Files = "FileDetail"

  DatabaseImpl* = ref object
    path: string
    store: FileInfo
    db: DbConn

proc close*(self: DatabaseImpl) {.async.} =
  ## close the database
  self.db.close()

type
  ModelVersion* = enum
    v0 = "(none)"
    v1 = "dragons; really alpha"

  Event = enum
    Upgrade
    Downgrade

proc getModelVersion(self: DatabaseImpl): ModelVersion =
  result = v0
  try:
    let row = self.db.getRow sql"""select value from Meta
                              where name = "version""""
    result = cast[ModelVersion](row[0].parseInt)
  except Exception:
    # blow up the database if we can't read a version from it
    discard

proc setModelVersion(self: DatabaseImpl; version: ModelVersion) =
  self.db.exec sql"begin"
  self.db.exec sql"""delete from Meta where name = "version""""
  self.db.exec sql"""insert into Meta (name, value)
                    values (?, ?)""", "version", $ord(version)
  self.db.exec sql"commit"

proc upgradeDatabase*(self: DatabaseImpl) =
  var currently = self.getModelVersion
  if currently == ModelVersion.high:
    return
  var mach = newMachine[ModelVersion, Event](currently)
  mach.addTransition v0, Upgrade, v1, proc () =
    for name in DatabaseTables.low .. DatabaseTables.high:
      self.db.exec sql"""
        drop table if exists ?
      """, $name
    self.db.exec sql"""
      create table Meta (
        name varchar(100) not null,
        value varchar(100) not null )
    """
    self.db.exec sql"""
      create table FileDetail (
        oid char(24),
        entry datetime,
        digest char(16),
        size int(4),
        path varchar(2048)
      )
    """
    self.db.exec sql"""
      create table CompilerInfo (
        oid char(24),
        entry datetime,
        binary char(24),
        major int(4),
        minor int(4),
        patch int(4),
        chash char(40)
      )
    """
    self.setModelVersion(v1)

  while currently != ModelVersion.high:
    mach.process Upgrade
    currently = mach.getCurrentState

method sync(self: DatabaseImpl; gold: var GoldObject): SyncResult {.base.} =
  raise newException(Defect, "sync not implemented")

method renderTimestamp(gold: GoldObject): string {.base.} =
  ## turn a datetime into a string for the db
  gold.entry.inZone(utc()).format(ISO8601forDB)

template loadTimestamp(gold: typed; datetime: string) =
  ## parse a db timestamp into a datetime
  gold.entry = datetime.parse(ISO8601forDB).inZone(local())

method sync(self: DatabaseImpl; detail: var FileDetail): SyncResult {.base.} =
  if not detail.dirty:
    return SyncOkay

  var row: Row
  row = self.db.getRow(sql"""select oid, entry, digest
    from FileDetail where digest = ?""", $detail.digest)
  if row[0] != "":
    result = SyncRead
    detail.oid = row[0].parseOid
    detail.loadTimestamp(row[1])
  else:
    result = SyncWrite
    self.db.exec sql"""
      insert into FileDetail
        (oid, entry, digest, size, path)
      values
        (?,   ?,     ?,      ?,    ?)
    """,
      $detail.oid,
      detail.renderTimestamp,
      detail.digest,
      detail.size,
      detail.path

method sync*(self: DatabaseImpl; compiler: var CompilerInfo): SyncResult {.base.} =
  discard self.sync(compiler.binary)
  if not compiler.dirty:
    return SyncOkay

  var row: Row
  row = self.db.getRow(sql"""
    select oid, entry, major, minor, patch, chash
    from CompilerInfo
    where binary = ?
  """, compiler.binary.oid)

  if row[0] != "":
    result = SyncRead
    compiler.oid = row[0].parseOid
    compiler.loadTimestamp(row[1])

    compiler.major = row[2].parseInt
    compiler.minor = row[3].parseInt
    compiler.patch = row[4].parseInt
    compiler.chash = row[5]
  else:
    result = SyncWrite
    self.db.exec sql"""
      insert into CompilerInfo
        (oid, entry, binary, major, minor, patch, chash)
      values
        (?,   ?,     ?,      ?,     ?,     ?,     ?)
    """,
      $compiler.oid,
      compiler.renderTimestamp,
      $compiler.binary.oid,
      $compiler.major,
      $compiler.minor,
      $compiler.patch,
      $compiler.chash

proc storagePath(filename: string): string =
  ## make up a good path for the database file
  var (head, tail) = filename.absolutePath.normalizedPath.splitPath
  if not filename.endsWith(".golden-db"):
    tail = "." & tail & ".golden-db"
  result = head / tail

proc newDatabaseImpl*(filename: string): Future[DatabaseImpl] {.async.} =
  ## instantiate a database using the filename
  new result
  result.path = storagePath(filename)
  result.db = open(result.path, "", "", "")
  if not result.path.fileExists:
    waitfor result.close
    return await newDatabaseImpl(filename)
  result.store = getFileInfo(result.path)
  result.upgradeDatabase()
