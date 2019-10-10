# golden

A benchmarking tool that measures and records runtime of any executable and
also happens to know how to compile Nim.

Currently pretty crude, but things are coming together.

## Installation

### Lightning Memory-Mapped Database

You will need to install LMDB so that the Nim wrapper can bind to it. [This
is a link to the Nim wrapper](https://github.com/FedericoCeratto/nim-lmdb)
and [this is a link to the Symas web-page with more information on
LMDB](https://symas.com/lmdb/).

It may sound like I'm asking you to install a behemoth closed-source binary.
**This is not that**. It's open, _very_ small, _very_ fast, and I was already
using it on my system for `postfix` and `neomutt` when I decided to use it here.

### Nimble

If LMDB is installed, you can simply
```
$ nimble install golden
```

## Usage

If you pass it a binary, it'll run it a bunch of times and report some runtime
statistics periodically.

If you pass it some Nim source, it will compile it for you and report some
compilation and runtime statistics periodically.

It will keep running until the standard deviation is within `truth` (think
percentage) of mean runtime. It handles a SIGINT more gracefully than my
ex-wife.

```
$ golden --truth=0.002 bench.nim
compilations after 0s
┌────────┬──────────┬──────────┬──────────┬──────────┐
│ Builds │ Min      │ Max      │ Mean     │ StdDev   │
├────────┼──────────┼──────────┼──────────┼──────────┤
│      1 │ 0.396129 │ 0.396129 │ 0.396129 │ 0.000000 │
└────────┴──────────┴──────────┴──────────┴──────────┘
benchmark after 1s
┌────────┬──────────┬──────────┬──────────┬──────────┐
│ Runs   │ Min      │ Max      │ Mean     │ StdDev   │
├────────┼──────────┼──────────┼──────────┼──────────┤
│      1 │ 1.959187 │ 1.959187 │ 1.959187 │ 0.000000 │
└────────┴──────────┴──────────┴──────────┴──────────┘
benchmark after 3s
┌────────┬──────────┬──────────┬──────────┬──────────┐
│ Runs   │ Min      │ Max      │ Mean     │ StdDev   │
├────────┼──────────┼──────────┼──────────┼──────────┤
│      2 │ 1.958892 │ 1.959187 │ 1.959039 │ 0.000147 │
└────────┴──────────┴──────────┴──────────┴──────────┘
completed benchmark after 5s
┌────────┬──────────┬──────────┬──────────┬──────────┐
│ Runs   │ Min      │ Max      │ Mean     │ StdDev   │
├────────┼──────────┼──────────┼──────────┼──────────┤
│      3 │ 1.958892 │ 1.961293 │ 1.959791 │ 0.001069 │
└────────┴──────────┴──────────┴──────────┴──────────┘
```

Benchmarking the compilation of Nim itself:
```
$ cd ~/git/Nim
$ golden koch -- boot -d:danger
# ...
┌────────┬──────────┬──────────┬──────────┬──────────┐
│ #      │ Min      │ Max      │ Mean     │ StdDev   │
├────────┼──────────┼──────────┼──────────┼──────────┤
│     12 │ 8.846606 │ 9.485832 │ 8.945023 │ 0.165638 │
└────────┴──────────┴──────────┴──────────┴──────────┘
```

Benchmarking compilation of slow-to-compile Nim:

```
$ golden --compilation openapi.nim
┌────────┬───────────┬───────────┬───────────┬──────────┐
│      # │ Min       │ Max       │ Mean      │ StdDev   │
├────────┼───────────┼───────────┼───────────┼──────────┤
│      1 │ 91.946370 │ 91.946370 │ 91.946370 │ 0.000000 │
└────────┴───────────┴───────────┴───────────┴──────────┘
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
