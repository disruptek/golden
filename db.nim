import os
import asyncdispatch
import asyncfutures
import strutils

import db_sqlite

import fsm

type
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
    let row = self.db.getRow sql"""select value from meta
                              where name = "version""""
    result = cast[ModelVersion](row[0].parseInt)
  except Exception:
    # blow up the database if we can't read a version from it
    discard

proc setModelVersion(self: DatabaseImpl; version: ModelVersion) =
  self.db.exec sql"begin"
  self.db.exec sql"""delete from meta where name = "version""""
  self.db.exec sql"""insert into meta (name, value)
                    values (?, ?)""", "version", $ord(version)
  self.db.exec sql"commit"

proc upgradeDatabase*(self: DatabaseImpl) =
  var currently = self.getModelVersion
  if currently == ModelVersion.high:
    return
  var mach = newMachine[ModelVersion, Event](currently)
  mach.addTransition v0, Upgrade, v1, proc () =
    self.db.exec sql"""create table meta (
      name varchar(100) not null,
      value varchar(100) not null )"""
    self.setModelVersion(v1)

  while currently != ModelVersion.high:
    mach.process Upgrade
    currently = mach.getCurrentState

proc storagePath(filename: string): string =
  ## make up a good path for the database file
  assert not filename.startsWith "."
  var (head, tail) = filename.absolutePath.normalizedPath.splitPath
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
