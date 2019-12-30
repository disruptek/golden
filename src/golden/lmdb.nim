import os

import nimterop/[build, cimport]

const
  baseDir = getProjectCacheDir("nimlmdb")

static:
  #cDebug()

  gitPull(
    "https://github.com/LMDB/lmdb",
    outdir = baseDir,
    checkout = "mdb.master"
  )

getHeader(
  "lmdb.h",
  outdir = baseDir / "libraries" / "liblmdb"
)

type
  mode_t = uint32

when defined(lmdbStatic):
  cImport(lmdbPath)
else:
  cImport(lmdbPath, dynlib = "lmdbLPath")
