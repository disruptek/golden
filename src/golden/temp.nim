import os

proc createTemporaryFile*(prefix: string; suffix: string): string =
  ## it should create the file, but so far, it doesn't
  let temp = getTempDir()
  result = temp / "golden-" & $getCurrentProcessId() & prefix & suffix
