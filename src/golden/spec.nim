#[

basic types and operations likely shared by all modules

]#
import os
import times
import oids
import strutils
import terminal
import stats
import lists
import json
import tables
import sequtils
import strformat
import terminal

#from posix import Tms

when defined(useSHA):
  import std/sha1
else:
  import md5

import msgpack4nim

import running

export oids
export times
export terminal

const
  ISO8601noTZ* = initTimeFormat "yyyy-MM-dd\'T\'HH:mm:ss\'.\'fff\'Z\'"
  billion* = 1_000_000_000

when declared(Tms):
  export Tms
  type CpuDuration* = Tms
else:
  from posix import Rusage
  type CpuDuration* = Rusage

type
  BenchmarkusInterruptus* = IOError

  ModelVersion* = enum
    v0 = "(none)"
    v1 = "dragons; really alpha"

  ModelEvent* = enum Upgrade, Downgrade

  # ordinal value is used as a magic number!
  GoldKind* = enum
    aFile = "📂"
    #aRuntime = "⏱️"
    #anOutput = "📢"
    aCompiler = "🧰"
    aCompilation = "🎯"
    anInvocation = "🎽"
    aBenchmark = "🏁"
    aGolden = "👑"
    #aPackageOfCourse = "📦"
    #aTestHaHa = "🧪"
    #aRocketDuh = "🚀"
    #aLinkerGetIt = "🔗"

  Gold* = ref object
    oid*: Oid
    description*: string
    links: GoldLinks
    when defined(StoreEntry):
      entry*: DateTime
    dirty*: bool
    case kind*: GoldKind
    of aFile:
      file*: FileDetail
    of aCompiler:
      version*: string
      major*: int
      minor*: int
      patch*: int
      chash*: string
    of aCompilation:
      compilation: CompilationInfo
    of anInvocation:
      invokation*: InvocationInfo
    of aBenchmark:
      benchmark*: BenchmarkResult
      terminated*: Terminated
    of aGolden:
      options*: GoldenOptions

  LinkFlag = enum
    Incoming
    Outgoing
    Unique
    Directory
    Binary
    Source
    Stdout
    Stderr
    Stdin
    Input
    Output

  LinkTarget = ref object
    oid: Oid
    kind: GoldKind

  Link = ref object
    flags: set[LinkFlag]
    source: LinkTarget
    target: LinkTarget
    entry: Time
    dirty: bool

  GoldLinks = ref object
    dad: Gold
    ins: seq[Link]
    outs: seq[Link]
    group: GoldGroup
    flags: TableRef[Oid, set[LinkFlag]]
    dirty: bool

  GoldGroup* = ref object
    cache: TableRef[Oid, Gold]

  LinkPairs = tuple[flags: set[LinkFlag], gold: Gold]

  FileSize* = BiggestInt
  FileDetail* = ref object
    kind*: PathComponent
    digest*: string
    size*: BiggestInt
    path*: string
    mtime*: Time

  WallDuration* = Duration
  MemorySize* = BiggestInt

  InvocationInfo* = ref object
    wall*: WallDuration
    cpu*: CpuDuration
    memory*: MemorySize
    arguments*: ref seq[string]
    stdout*: string
    stderr*: string
    code*: int

  CompilationInfo* = ref object
    compiler*: Gold
    invocation*: Gold
    source*: Gold
    binary*: Gold

  Terminated* {.pure.} = enum
    Success
    Failure
    Interrupt

  BenchmarkResult* = ref object
    binary*: Gold
    compilations* {.deprecated.}: RunningResult[Gold]
    invocations*: RunningResult[Gold]

  GoldenFlag* = enum
    Interactive
    PipeOutput
    ColorConsole
    ConsoleGraphs
    DryRun
    CompileOnly
    TimeLimit
    RunLimit
    DumpOutput
    NeverOutput

  GoldenOptions* = object
    flags*: set[GoldenFlag]
    arguments*: seq[string]
    honesty*: float
    prune*: float
    classes*: int
    storage*: string
    timeLimit*: float
    runLimit*: int

  Golden* = object
    options*: GoldenOptions

proc created*(gold: Gold): Time {.inline.} =
  ## when the object was originally created
  gold.oid.generatedTime

proc `==`(a, b: LinkTarget): bool {.inline.} = a.oid == b.oid

proc newGoldGroup(): GoldGroup =
  result = GoldGroup(cache: newTable[Oid, Gold]())

proc newGoldLinks(gold: Gold): GoldLinks =
  result = GoldLinks(dad: gold, ins: @[], outs: @[])
  result.group = newGoldGroup()
  result.flags = newTable[Oid, set[LinkFlag]]()

proc init(gold: var Gold) =
  gold.links = newGoldLinks(gold)

proc newGold*(kind: GoldKind): Gold =
  ## create a new instance that we may want to save in the database
  when defined(StoreEntry):
    result = Gold(kind: kind, oid: genOid(), entry: now(), dirty: true)
  else:
    result = Gold(kind: kind, oid: genOid(), dirty: true)
  result.init

when defined(StoreEntry):
  proc newGold(kind: GoldKind; oid: Oid; entry: DateTime): Gold =
    ## prep a new Gold object for database paint
    result = Gold(kind: kind, oid: oid, entry: entry, dirty: false)
    result.init
else:
  proc newGold(kind: GoldKind; oid: Oid): Gold =
    ## prep a new Gold object for database paint
    result = Gold(kind: kind, oid: oid, dirty: false)
    result.init

proc digestOf*(content: string): string =
  ## calculate the digest of a string
  when defined(useSHA):
    result = $secureHash(content)
  else:
    result = $toMD5(content)

proc digestOfFileContents(path: string): string =
  ## calculate the digest of a file
  assert path.fileExists
  when defined(useSHA):
    result = $secureHashFile(path)
  else:
    result = digestOf(readFile(path))

proc newFileDetail*(path: string): Gold =
  result = newGold(aFile)
  result.file = FileDetail(path: path)

proc newFileDetail*(path: string; size: FileSize; digest: string): Gold =
  result = newFileDetail(path)
  result.file.size = size
  result.file.digest = digest

proc newFileDetail*(path: string; info: FileInfo): Gold =
  let normal = path.absolutePath.normalizedPath
  result = newFileDetail(normal, info.size, digestOfFileContents(normal))
  result.file.mtime = info.lastWriteTime
  result.file.kind = info.kind

proc newFileDetailWithInfo*(path: string): Gold =
  assert path.fileExists, "path `" & path & "` does not exist"
  result = newFileDetail(path, getFileInfo(path))

proc newFileDetailWithInfo*(gold: Gold): Gold =
  result = newFileDetailWithInfo(gold.file.path)

when defined(GoldenGold):
  proc newGolden*(): Gold =
    result = newGold(aGolden)
    if stdmsg().isatty:
      result.options.flags.incl Interactive
      result.options.flags.incl ColorConsole
    else:
      result.options.flags.incl PipeOutput
else:
  proc newGolden*(): Golden =
    if stdmsg().isatty:
      result.options.flags.incl Interactive
      result.options.flags.incl ColorConsole
    else:
      result.options.flags.incl PipeOutput

proc linkTarget(gold: Gold): LinkTarget =
  result = LinkTarget(oid: gold.oid, kind: gold.kind)

func newLink(source: Gold; flags: set[LinkFlag]; target: Gold;
             dirty = true): Link =
  result = Link(flags: flags, entry: getTime(), dirty: dirty,
                  source: source.linkTarget, target: target.linkTarget)

iterator values(group: GoldGroup): Gold =
  for gold in group.cache.values:
    yield gold

proc `[]`(group: GoldGroup; key: Oid): Gold =
  result = group.cache[key]

iterator pairs(links: GoldLinks): LinkPairs =
  for oid, flags in links.flags.pairs:
    yield (flags: flags, gold: links.group[oid])

iterator `[]`(links: GoldLinks; kind: GoldKind): Gold =
  for gold in links.group.values:
    if gold.kind == kind:
      yield gold

proc `[]`(links: GoldLinks; kind: GoldKind): Gold =
  for gold in links.group.values:
    if gold.kind == kind:
      return gold

proc `[]`*(gold: Gold; kind: GoldKind): Gold =
  result = gold.links[kind]

iterator `{}`*(links: GoldLinks; flag: LinkFlag): Gold =
  if flag == Incoming:
    for link in links.ins:
      yield links.group[link.target.oid]
  elif flag == Outgoing:
    for link in links.outs:
      yield links.group[link.target.oid]
  else:
    for flags, gold in links.pairs:
      if flag in flags:
        yield gold

iterator `{}`*(links: GoldLinks; flags: set[LinkFlag]): Gold =
  for tags, gold in links.pairs:
    if (flags - tags).len == 0:
      yield gold

iterator `{}`*(links: GoldLinks; flags: varargs[LinkFlag]): Gold =
  var tags: set[LinkFlag]
  for flag in flags:
    tags.incl flag
  for gold in links{tags}:
    yield gold

proc contains(group: GoldGroup; oid: Oid): bool =
  result = oid in group.cache

proc contains(group: GoldGroup; gold: Gold): bool =
  result = gold.oid in group

proc contains(links: GoldLinks; kind: GoldKind): bool =
  for gold in links.group.values:
    if gold.kind == kind:
      return true

proc excl(group: GoldGroup; oid: Oid) =
  ## exclude an oid from the group
  group.cache.del oid

proc `==`(a, b: Link): bool {.inline.} =
  ## two links are equal if they refer to the same endpoints
  result = a.source == b.source and a.target == b.target

proc incl(group: GoldGroup; gold: Gold) =
  ## add gold to a group; no duplicate entries
  if gold in group:
    return
  group.cache[gold.oid] = gold

proc excl(links: var GoldLinks; link: Link) =
  ## remove a link
  if link.target.oid notin links.flags:
    return
  if Outgoing in link.flags:
    links.outs = links.outs.filterIt it != link
  if Incoming in link.flags:
    links.ins = links.ins.filterIt it != link
  links.flags.del link.target.oid
  links.group.excl link.target.oid

proc excl(links: var GoldLinks; target: Gold) =
  ## remove a link to the given target
  # construct a mask that matches Incoming and Outgoing
  let mask = newLink(links.dad, {Incoming, Outgoing}, target)
  # and exclude it
  links.excl mask

proc incl(links: var GoldLinks; link: Link; target: Gold) =
  ## link to a target with the given, uh, link
  var existing: set[LinkFlag]
  if target.oid in links.flags:
    existing = links.flags[target.oid]
  if Outgoing in link.flags and Outgoing notin existing:
    links.outs.add link
  if Incoming in link.flags and Incoming notin existing:
    links.ins.add link
  links.flags[target.oid] = existing + link.flags
  links.group.incl target

proc rotateLinkFlags(flags: set[LinkFlag]): set[LinkFlag] =
  result = flags
  if Incoming in result and Outgoing in result:
    discard
  elif Incoming in result:
    result.incl Outgoing
    result.excl Incoming
  elif Outgoing in result:
    result.incl Incoming
    result.excl Outgoing

proc createLink(links: var GoldLinks; flags: set[LinkFlag]; target: var Gold) =
  ## create a link by specifying the flags and the target
  var
    future: set[LinkFlag]
    existing: set[LinkFlag]
  if target.oid in links.flags:
    existing = links.flags[target.oid]
    future = flags + existing
    if future.len == existing.len:
      return
  var tags = flags
  case target.kind:
  of aFile:
    discard
  of aCompiler:
    tags.incl Unique
  of aCompilation:
    discard
  of anInvocation:
    discard
  else:
    raise newException(Defect,
                       &"{links.dad.kind} doesn't link to {target.kind}")
  let link = newLink(links.dad, tags, target)
  if Unique in tags:
    if target.kind in links:
      links.excl links[target.kind]
  links.incl link, target
  tags = rotateLinkFlags(tags)
  createLink(target.links, tags, links.dad)

proc `{}=`(links: var GoldLinks; flags: varargs[LinkFlag]; target: var Gold) =
  ## create a link by specifying the flags and the target
  var tags: set[LinkFlag]
  for flag in flags:
    tags.incl flag
  links.createLink(tags, target)

proc compiler*(gold: Gold): Gold =
  result = gold.links[aCompiler]

proc `compiler=`*(gold: var Gold; compiler: var Gold) =
  ## link to a compiler
  assert compiler.kind == aCompiler
  var flags: set[LinkFlag]
  case gold.kind:
  of aFile:
    flags = {Outgoing}
  of aCompilation:
    flags = {Incoming}
  else:
    raise newException(Defect, "inconceivable!")
  gold.links.createLink(flags, compiler)

proc binary*(gold: Gold): Gold =
  assert gold != nil
  case gold.kind:
  of aCompiler, aCompilation, anInvocation:
    for file in gold.links{Binary}:
      return file
    raise newException(Defect, "unable to find binary for " & $gold.kind)
  else:
    raise newException(Defect, "inconceivable!")

iterator sources*(gold: Gold): Gold =
  for file in gold.links{Source}:
    yield file

proc source*(gold: Gold): Gold {.deprecated.} =
  for file in gold.sources:
    return file

proc target*(gold: Gold): Gold =
  assert gold.kind == aCompilation
  for file in gold.links{Output,Binary}:
    return file

proc compilation*(gold: Gold): Gold =
  for compilation in gold.links{Incoming}:
    if compilation.kind == aCompilation:
      return compilation

proc invocation*(gold: Gold): Gold =
  assert gold.kind != anInvocation
  for invocation in gold.links{Incoming}:
    if invocation.kind == anInvocation:
      return invocation

proc invocations*(gold: var Gold): RunningResult[Gold] =
  result = gold.benchmark.invocations

proc compilations*(gold: var Gold): RunningResult[Gold] =
  result = gold.compilations

proc `source=`*(gold: var Gold; source: var Gold) =
  ## link to a source file
  assert gold.kind == aCompilation
  assert source.kind == aFile
  source.links{Outgoing, Incoming, Input, Source} = gold

proc `binary=`*(gold: var Gold; binary: var Gold) =
  ## link to a binary (executable) file
  assert gold.kind in [anInvocation, aCompiler]
  assert binary.kind == aFile
  binary.links{Outgoing, Input, Binary} = gold

proc `invocation=`*(gold: var Gold; invocation: var Gold) =
  ## link a compilation to its invocation
  assert gold.kind == aCompilation
  assert invocation.kind == anInvocation
  invocation.links{Outgoing} = gold

proc `target=`*(gold: var Gold; target: var Gold) =
  ## link a compilation to its target (binary)
  assert gold.kind == aCompilation
  assert target.kind == aFile
  target.links{Outgoing, Output, Binary} = gold

proc `compilation=`*(gold: var Gold; compilation: CompilationInfo) =
  assert gold.kind == aCompilation
  gold.compilation = compilation

proc commandLine*(invocation: Gold): string =
  ## compose the full commandLine for the given invocation
  result = invocation.binary.file.path
  if invocation.invokation.arguments != nil:
    if invocation.invokation.arguments[].len > 0:
      result &= " " & invocation.invokation.arguments[].join(" ")

proc init*(gold: var Gold; binary: var Gold; args: ref seq[string]) =
  assert gold.kind == anInvocation
  assert binary.kind == aFile
  gold.invokation = InvocationInfo()
  gold.links{Incoming,Outgoing,Binary,Input} = binary
  gold.invokation.arguments = args

proc okay*(gold: Gold): bool =
  ## measure the output code of a completed process
  case gold.kind:
  of aCompilation:
    result = gold.invocation.okay
  of anInvocation:
    result = gold.invokation.code == 0
  else:
    raise newException(Defect, "inconceivable!")

proc newInvocation*(): Gold =
  result = newGold(anInvocation)
  result.invokation = InvocationInfo()

proc newInvocation*(file: Gold; args: ref seq[string]): Gold =
  var binary = newFileDetailWithInfo(file.file.path)
  result = newInvocation()
  result.init(binary, args = args)

proc fibonacci*(x: int): int =
  result = if x <= 2: 1
  else: fibonacci(x - 1) + fibonacci(x - 2)

proc pack_type*[ByteStream](s: ByteStream; x: GoldKind) =
  let v = cast[uint8](ord(x))
  s.pack(v)

proc unpack_type*[ByteStream](s: ByteStream; x: var GoldKind) =
  var v: uint8
  s.unpack_type(v)
  x = cast[GoldKind](v)

proc pack_type*[ByteStream](s: ByteStream; x: Timezone) {.deprecated.} =
  s.pack(x.name)

proc unpack_type*[ByteStream](s: ByteStream; x: var Timezone) {.deprecated.} =
  s.unpack_type(x.name)
  case x.name:
  of "LOCAL":
    x = local()
  of "UTC":
    x = utc()
  else:
    raise newException(Defect, "dunno how to unpack timezone `" & x.name & "`")

proc pack_type*[ByteStream](s: ByteStream; x: NanosecondRange) =
  s.pack(cast[int32](x))

proc unpack_type*[ByteStream](s: ByteStream; x: var NanosecondRange) =
  var y: int32
  s.unpack_type(y)
  x = y

proc pack_type*[ByteStream](s: ByteStream; x: Time) =
  s.pack(x.toUnix)
  s.pack(x.nanosecond)

proc unpack_type*[ByteStream](s: ByteStream; x: var Time) =
  var
    unix: int64
    nanos: NanosecondRange
  s.unpack_type(unix)
  s.unpack_type(nanos)
  x = initTime(unix, nanos)

proc pack_type*[ByteStream](s: ByteStream; x: DateTime) =
  s.pack(x.toTime)

proc unpack_type*[ByteStream](s: ByteStream; x: var DateTime) =
  var t: Time
  s.unpack_type(t)
  x = t.inZone(local())

proc pack_type*[ByteStream](s: ByteStream; x: Oid) =
  s.pack($x)

proc unpack_type*[ByteStream](s: ByteStream; x: var Oid) =
  var oid: string
  s.unpack_type(oid)
  x = parseOid(oid)

proc pack_type*[ByteStream](s: ByteStream; x: FileDetail) =
  s.pack(x.digest)
  s.pack(x.size)
  s.pack(x.path)
  s.pack(x.kind)
  s.pack(x.mtime)

proc unpack_type*[ByteStream](s: ByteStream; x: var FileDetail) =
  s.unpack_type(x.digest)
  s.unpack_type(x.size)
  s.unpack_type(x.path)
  s.unpack_type(x.kind)
  s.unpack_type(x.mtime)

proc pack_type*[ByteStream](s: ByteStream; x: Gold) =
  s.pack(x.kind)
  s.pack(x.oid)
  #s.pack(x.entry)
  case x.kind:
  of aFile:
    s.pack(x.file)
  else:
    raise newException(Defect, "inconceivable!")

proc unpack_type*[ByteStream](s: ByteStream; gold: var Gold) =
  var
    oid: string
    kind: GoldKind
  s.unpack_type(kind)
  s.unpack_type(oid)
  when defined(StoreEntry):
    var entry: DateTime
    s.unpack_type(entry)
    gold = newGold(kind, oid = parseOid(oid), entry = entry)
  else:
    gold = newGold(kind, oid = parseOid(oid))
  case kind:
  of aFile:
    new gold.file
    s.unpack_type(gold.file)
  else:
    raise newException(Defect, "inconceivable!")

proc toJson*(entry: DateTime): JsonNode =
  result = newJString entry.format(ISO8601noTZ)

proc toJson*(gold: Gold): JsonNode =
  result = %* {
    "oid": newJString $gold.oid,
    "description": newJString gold.description,
  }
  when defined(StoreEntry):
    result["entry"] = gold.entry.toJson

proc jsonOutput*(golden: Golden): bool =
  let flags = golden.options.flags
  result = PipeOutput in flags or Interactive notin flags

proc add*[T: InvocationInfo](running: RunningResult[T]; value: T) =
  ## for stats, pull out the invocation duration from invocation info
  let seconds = value.wall.toSeconds
  running.list.append value
  running.stat.push seconds

proc add*[T: Gold](running: RunningResult[T]; value: T) =
  ## for stats, pull out the invocation duration from invocation info
  var v: StatValue
  case value.kind:
  of aCompilation:
    v = value.invocation.invokation.wall.toSeconds
  of anInvocation:
    v = value.invokation.wall.toSeconds
  else:
    raise newException(Defect, "inconceivable!")
  running.list.append value
  running.stat.push v

proc reset*[T: InvocationInfo](running: RunningResult[T]) {.deprecated.} =
  running.stat.clear
  var stat: seq[StatValue]
  for invocation in running.list.items:
    stat.add invocation.runtime.stat.toSeconds
  running.stat.push stat

proc add*[T: CompilationInfo](running: RunningResult[T]; value: T) {.deprecated.} =
  ## for stats, pull out the invocation duration from compilation info
  running.list.append value
  running.stat.push value.invocation.wall.toSeconds

proc quiesceMemory*(message: string): int {.inline.} =
  GC_fullCollect()
  when defined(debug):
    stdmsg().writeLine GC_getStatistics()
  result = getOccupiedMem()

template goldenDebug*() =
  when defined(debug):
    when defined(nimTypeNames):
      dumpNumberOfInstances()
    stdmsg().writeLine "total: " & $getTotalMem()
    stdmsg().writeLine " free: " & $getFreeMem()
    stdmsg().writeLine "owned: " & $getOccupiedMem()
    stdmsg().writeLine "  max: " & $getMaxMem()

proc render*(d: Duration): string {.raises: [].} =
  ## cast a duration to a nice string
  let
    n = d.inNanoseconds
    ss = (n div 1_000_000_000) mod 1_000
    ms = (n div 1_000_000) mod 1_000
    us = (n div 1_000) mod 1_000
    ns = (n div 1) mod 1_000
  try:
    return fmt"{ss:>3}s {ms:>3}ms {us:>3}μs {ns:>3}ns"
  except:
    return [$ss, $ms, $us, $ns].join(" ")

proc `$`*(detail: FileDetail): string =
  result = detail.path

proc toJson(invokation: InvocationInfo): JsonNode =
  result = newJObject()
  result["stdout"] = newJString invokation.stdout
  result["stderr"] = newJString invokation.stderr
  result["code"] = newJInt invokation.code

proc output*(golden: Golden; content: string; style: set[terminal.Style] = {}; fg: ForegroundColor = fgDefault; bg: BackgroundColor = bgDefault) =
  let
    flags = golden.options.flags
    fh = stdmsg()
  if NeverOutput in golden.options.flags:
    return
  if ColorConsole in flags or PipeOutput notin flags:
    fh.setStyle style
    fh.setForegroundColor fg
    fh.setBackgroundColor bg
  fh.writeLine content

proc output*(golden: Golden; content: JsonNode) =
  var ugly: string
  if NeverOutput in golden.options.flags:
    return
  ugly.toUgly(content)
  stdout.writeLine ugly

proc output*(golden: Golden; invocation: Gold; desc: string = "";
             arguments: seq[string] = @[]) =
  ## generally used to output a failed invocation
  let invokation = invocation.invokation
  if ColorConsole in golden.options.flags:
    if invokation.stdout.len > 0:
      golden.output invokation.stdout, fg = fgCyan
    if invokation.stderr.len > 0:
      golden.output invokation.stderr, fg = fgRed
    if invokation.code != 0:
      golden.output "exit code: " & $invokation.code
  if jsonOutput(golden):
    golden.output invokation.toJson
  if invokation.code != 0:
    new invokation.arguments
    for n in arguments:
      invokation.arguments[].add n
    golden.output "command-line:\n  " & invocation.commandLine
    invokation.arguments = nil

proc toWallDuration*(gold: Gold): Duration =
  case gold.kind:
  of anInvocation:
    result = gold.invokation.wall
  of aCompilation:
    result = gold.compilation.invocation.toWallDuration
  else:
    raise newException(Defect, "inconceivable!")

proc toStatValue*(gold: Gold): StatValue =
  case gold.kind:
  of anInvocation:
    result = gold.toWallDuration.toSeconds
  of aCompilation:
    result = gold.toWallDuration.toSeconds
  else:
    raise newException(Defect, "inconceivable!")

proc output*(golden: Golden; running: RunningResult; desc: string = "") =
  golden.output running.renderTable(desc)
