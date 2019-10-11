import os

# whatfer testing params and failed invocations
if paramCount() == 1 and paramStr(1) == "quit":
  quit(3)

if paramCount() == 1 and paramStr(1) == "hello":
  echo "world"

if paramCount() == 1 and paramStr(1) == "goodbye":
  stderr.writeLine "cruel world"

sleep 100
