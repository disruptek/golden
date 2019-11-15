version = "3.0.2"
author = "disruptek"
description = "a benchmark tool"
license = "MIT"
requires "nim >= 0.20.0"

requires "foreach >= 1.0.2"
requires "bump >= 1.8.3"
requires "nimetry 0.1.2"
#requires "plotly >= 0.1.0"
requires "msgpack4nim 0.2.9"
requires "https://github.com/disruptek/nim-terminaltables#nim111"
requires "nimgit2 0.1.0"

# we need this one for csize reasons
requires "lmdb 0.1.2"
# we need this one for csize reasons
requires "cligen >= 0.9.40"

bin = @["golden"]

srcDir = "src"
