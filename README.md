# golden

A benchmark for compile-time and/or runtime Nim.

Currently pretty crude, but things are coming together.

## Installation
```
$ nimble install golden
```

## Usage
```
$ golden somesource.nim
# compiles your code with -d:danger and runs it many times
# it will dump runtime statistics with fibonacci frequency
# ctrl-c when you've had enough
# ...
bench:5d9652e4615eca6d3e35c38a entry 2019-10-03T15:58:28-04:00
/some/path/to/a/binary
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

## Theory of Operation

### Measure something, anything

We don't currently measure anything, so the bar is pretty low, here.

### Tell me something true, and as cheaply as possible

Provide answers commensurate with the complexity of the request.

### The more money I put in, the more truth I want

You pour; I'll say "when".

### The more I spend, the more valuable your memory

Truth is hardwon, and probably moreso than memory.

### Be useful to humans

Your user is interactive.

### Be useful to code

Oh, let them eat cake!

### I don't want to know how the sausage is made

Nothing good ever came of it.

### But I might want to provide some of the ingredients

Sure, sure, we'll use 'em.

## License
MIT
