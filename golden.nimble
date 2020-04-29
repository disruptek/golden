version = "3.0.13"
author = "disruptek"
description = "a benchmark tool"
license = "MIT"
requires "nim >= 1.0.4"

requires "foreach >= 1.0.2"
requires "bump >= 1.8.15"
requires "msgpack4nim 0.2.9"
requires "terminaltables#82ee5890c13e381de0f11c8ba6fe484d7c0c2f19"
requires "https://github.com/disruptek/gittyup >= 2.1.13"

# we need this one for csize reasons
requires "cligen >= 0.9.40"

bin = @["golden"]
srcDir = "src"

proc execCmd(cmd: string) =
  echo "execCmd:" & cmd
  exec cmd

proc execTest(test: string) =
  execCmd "nim c           -f -r " & test
  execCmd "nim c   -d:release -r " & test
  execCmd "nim c   -d:danger  -r " & test
  execCmd "nim cpp            -r " & test
  execCmd "nim cpp -d:danger  -r " & test
  when NimMajor >= 1 and NimMinor >= 1:
    execCmd "nim c --useVersion:1.0 -d:danger -r " & test
    execCmd "nim c   --gc:arc -r " & test
    execCmd "nim cpp --gc:arc -r " & test

task test, "run tests for travis":
  execTest("tests/tstats.nim")
  execTest("tests/tspec.nim")
  execTest("tests/tdb.nim")
  execTest("tests/tinvoke.nim")
