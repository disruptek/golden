version = "2.5.2"
author = "disruptek"
description = "a benchmark tool"
license = "MIT"
requires "nim >= 0.20.0"

requires "foreach >= 1.0.2"
requires "nimetry 0.1.2"
#requires "plotly >= 0.1.0"
requires "msgpack4nim 0.2.9"
requires "terminaltables 0.1.1"
requires "nimgit2 0.1.0"

# we need this one for csize reasons
requires "lmdb 0.1.2"
# we need this one for csize reasons
requires "cligen >= 0.9.39"

bin = @["golden"]

srcDir = "src"
