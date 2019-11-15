version = "3.0.4"
author = "disruptek"
description = "a benchmark tool"
license = "MIT"
requires "nim >= 0.20.0"

requires "foreach >= 1.0.2"
requires "bump >= 1.8.3"
requires "nimetry#1db37f9508bfbd9ee2bde2e1485c5d0026fea5b4"
#requires "plotly >= 0.1.0"
requires "msgpack4nim 0.2.9"
requires "https://github.com/disruptek/nim-terminaltables#59ea26e64db5680e3a6c20329e32c0e297343e1a"
requires "nimgit2 0.1.0"

# we need this one for csize reasons
requires "lmdb 0.1.2"
# we need this one for csize reasons
requires "cligen >= 0.9.40"

bin = @["golden"]

srcDir = "src"
