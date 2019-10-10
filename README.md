# golden

A benchmarking tool that measures and records runtime of any executable and
also happens to know how to compile Nim.

Currently pretty crude, but things are coming together.

## Installation
```
$ nimble install golden
```

## Usage
```
$ golden --truth=0.01 bench.nim
# It will compile your code with -d:danger and run it many times.
# It will dump runtime statistics with fibonacci frequency.
# It will continue to run the benchmark until the stddev is
# within `truth` (think percentage) of mean runtime.
# Ctrl-C when you've had enough.
bench:5d9e54f2f93ca663167cb2df entry 2019-10-09T17:45:22-04:00
/home/adavidoff/git/golden/benchmarks/dumb/bench
invocations:
┌────────┬──────────┬──────────┬──────────┬──────────┐
│ #      │ Min      │ Max      │ Mean     │ StdDev   │
├────────┼──────────┼──────────┼──────────┼──────────┤
│    530 │ 0.100460 │ 0.101993 │ 0.101165 │ 0.000542 │
└────────┴──────────┴──────────┴──────────┴──────────┘
```

Benchmarking the compilation of Nim itself:
```
$ cd ~/git/Nim
$ golden koch -- boot -d:danger
...
bench:5d9e544bc197dd2569de3b80 entry 2019-10-09T17:42:35-04:00
/home/adavidoff/git/Nim/koch boot -d:danger
invocations:
┌────────┬──────────┬──────────┬──────────┬──────────┐
│ #      │ Min      │ Max      │ Mean     │ StdDev   │
├────────┼──────────┼──────────┼──────────┼──────────┤
│     12 │ 8.846606 │ 9.485832 │ 8.945023 │ 0.165638 │
└────────┴──────────┴──────────┴──────────┴──────────┘
```

Benchmarking compilation of slow-to-compile Nim:

```
$ golden --compilation openapi.nim
bench:5d9e7496380fa518469ca5c4 entry 2019-10-09T20:00:22-04:00
/home/adavidoff/git/Nim/bin/nim c --forceBuild /home/adavidoff/git/golden/benchmarks/openapi/openapi.nim
invocations:
┌────────┬───────────┬───────────┬───────────┬──────────┐
│      # │ Min       │ Max       │ Mean      │ StdDev   │
├────────┼───────────┼───────────┼───────────┼──────────┤
│      1 │ 91.946370 │ 91.946370 │ 91.946370 │ 0.000000 │
└────────┴───────────┴───────────┴───────────┴──────────┘
bench:5d9e7496380fa518469ca5c4 entry 2019-10-09T20:00:22-04:00
/home/adavidoff/git/Nim/bin/nim c --forceBuild /home/adavidoff/git/golden/benchmarks/openapi/openapi.nim
invocations:
┌────────┬───────────┬───────────┬───────────┬───────────┐
│      # │ Min       │ Max       │ Mean      │ StdDev    │
├────────┼───────────┼───────────┼───────────┼───────────┤
│      2 │ 29.271556 │ 91.946370 │ 60.608963 │ 31.337407 │
└────────┴───────────┴───────────┴───────────┴───────────┘
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
 - `compilation-only` benchmark the Nim compiler on the given source(s)
 - `--` the following arguments are passed to the compiler and runtime. Note that if you supply `-- cpp` for compilation via C++, you will need to supply your own defines such as `-d:danger`.

## License
MIT
