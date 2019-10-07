# golden

A benchmark for compile-time and/or runtime Nim.

Currently pretty crude, but things are coming together.

## Installation
```
$ nimble install golden
```

## Usage
```
$ golden --truth=0.01 somesource.nim
# Compile your code with -d:danger and run it many times.
# It will dump runtime statistics with fibonacci frequency.
# It will continue to run the benchmark until the stddev is
# within `truth` (think percentage) of mean runtime.
# Ctrl-C when you've had enough.
# ...
bench:5d9652e4615eca6d3e35c38a entry 2019-10-03T15:58:28-04:00
/some/path/to/somesource
compilation(s) -- RunningStat(
  number of probes: 1
  max: 3.018017831
  min: 3.018017831
  sum: 3.018017831
  mean: 3.018017831
  std deviation: 0.0
)
 invocation(s) -- RunningStat(
  number of probes: 84348
  max: 0.014843757
  min: 0.000195513
  sum: 48.61967556299996
  mean: 0.0005764176455043348
  std deviation: 0.0001040502276687006
)
```

Benchmarking the compilation of Nim itself:
```
$ cd ~/git/Nim
$ golden --args="boot -d:danger" koch.nim
compilation(s) -- RunningStat(
  number of probes: 1
  max: 0.852614852
  min: 0.852614852
  sum: 0.852614852
  mean: 0.852614852
  std deviation: 0.0
)
 invocation(s) -- RunningStat(
  number of probes: 16
  max: 9.345349467
  min: 8.659001024
  sum: 141.675704772
  mean: 8.854731548249999
  std deviation: 0.1878308778737006
)
```

## Command Line Options

 - `truth` a float percentage indicating how much jitter you'll accept
 - `storage` the path to a database file you wish to use; must end in `.golden-db`
 - `interactive-forced` assume output friendly to humans
 - `json-output` assume output friendly to machines _(work in progress)_
 - `color-forced` enable color output when not in `interactive` mode
 - `graphs-in-console` periodically produce graphs (PNG) and display them in a Kitty console
 - `prune-outliers` throw out this percentage of aberrant invocations with long runtime in order to clean up the histogram
 - `dry-run` don't write any results to the database
 - `histogram-classes` the number of points in the histogram

## License
MIT
