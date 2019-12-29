version = "3.0.12"
author = "disruptek"
description = "a benchmark tool"
license = "MIT"
requires "nim >= 0.20.0"

requires "foreach >= 1.0.2"
requires "bump >= 1.8.15"
#requires "nimetry >= 0.4.0"
#requires "plotly >= 0.1.0"
requires "https://github.com/disruptek/msgpack4nim#golden"
requires "terminaltables#82ee5890c13e381de0f11c8ba6fe484d7c0c2f19"
requires "nimgit2 >= 0.1.0"

# we need this one for csize reasons
#requires "lmdb 0.1.2"
# we need this one for csize reasons
requires "cligen >= 0.9.40"

bin = @["golden"]
srcDir = "src"
