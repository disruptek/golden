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

when defined(useSHA):
  import std/sha1
else:
  import md5

import msgpack4nim

import running

export oids
export times

const
  ISO8601noTZ* = initTimeFormat "yyyy-MM-dd\'T\'HH:mm:ss\'.\'fff\'Z\'"
  billion* = 1_000_000_000

type
  BenchmarkusInterruptus* = IOError

  ModelVersion* = enum
    v0 = "(none)"
    v1 = "dragons; really alpha"

  ModelEvent* = enum
    Upgrade
    Downgrade

  # ordinal value is used as a magic number!
  GoldKind* = enum
    aFile = "📂"
    aRuntime = "⏱️"
    anOutput = "📢"
    aCompiler = "🧰"
    aCompilation = "🎯"
    anInvocation = "🎽"
    aBenchmark = "🏁"
    #aPackageOfCourse = "📦"
    #aTestHaHa = "🧪"
    #aRocketDuh = "🚀"
    #aLinkerGetIt = "🔗"

  Gold* = ref object
    oid*: Oid
    name*: string
    description*: string
    when defined(StoreEntry):
      entry*: DateTime
    dirty*: bool
    case kind*: GoldKind
    of aFile:
      file*: FileDetail
    of aRuntime:
      runtime*: RuntimeInfo
    of anOutput:
      output*: OutputInfo
    of aCompiler:
      compiler*: CompilerInfo
    of aCompilation:
      compilation*: CompilationInfo
    of anInvocation:
      invocation*: InvocationInfo
    of aBenchmark:
      benchmark*: BenchmarkResult

  FileSize* = BiggestInt
  FileDetail* = ref object
    digest*: string
    size*: FileSize
    path*: string
    mtime*: Time
    kind*: PathComponent

  WallDuration* = Duration
  CpuDuration* = float64
  MemorySize* = int

  RuntimeInfo* = ref object
    wall*: WallDuration
    cpu*: CpuDuration
    memory*: MemorySize

  OutputInfo* = ref object
    code*: int
    stdout*: string
    stderr*: string

  InvocationInfo* = ref object
    binary*: Gold
    arguments*: ref seq[string]
    runtime*: RuntimeInfo
    output*: OutputInfo

  CompilerInfo* = ref object
    binary*: Gold
    version*: string
    major*: int
    minor*: int
    patch*: int
    chash*: string

  CompilationInfo* = ref object
    compiler*: Gold
    invocation*: Gold
    source*: Gold
    binary*: Gold

  BenchmarkResult* = ref object
    binary*: Gold
    compilations*: RunningResult[Gold]
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

proc newGold*(kind: GoldKind): Gold =
  when defined(StoreEntry):
    result = Gold(kind: kind, oid: genOid(), entry: now(), dirty: true)
  else:
    result = Gold(kind: kind, oid: genOid(), dirty: true)

when defined(StoreEntry):
  proc newGold(kind: GoldKind; oid: Oid; entry: DateTime): Gold =
    ## prep a new Gold object for database paint
    result = Gold(kind: kind, oid: oid, entry: entry, dirty: false)
else:
  proc newGold(kind: GoldKind; oid: Oid): Gold =
    ## prep a new Gold object for database paint
    result = Gold(kind: kind, oid: oid, dirty: false)

proc digestOf*(content: string): string =
  when defined(useSHA):
    result = $secureHash(content)
  else:
    result = $toMD5(content)

proc digestOfFileContents(path: string): string =
  assert path.fileExists
  when defined(useSHA):
    result = $secureHashFile(path)
  else:
    result = digestOf(readFile(path))

proc commandLine*(invocation: InvocationInfo): string =
  ## compose the full commandLine for the given invocation
  result = invocation.binary.file.path
  if invocation.arguments != nil:
    if invocation.arguments[].len > 0:
      result &= " " & invocation.arguments[].join(" ")

proc okay*(gold: Gold): bool =
  case gold.kind:
  of aCompilation:
    result = gold.compilation.invocation.okay
  of anInvocation:
    result = gold.invocation.output.code == 0
  else:
    raise newException(Defect, "nonsensical")

proc newRuntimeInfo*(): RuntimeInfo =
  new result

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

proc newGolden*(): Golden =
  if stdmsg().isatty:
    result.options.flags.incl Interactive
    result.options.flags.incl ColorConsole
  else:
    result.options.flags.incl PipeOutput

proc newOutputInfo*(): OutputInfo =
  new result

proc `binary=`*(gold: var Gold; file: Gold) =
  assert file.kind == aFile
  gold.binary = file

proc `source=`*(gold: var Gold; file: Gold) =
  assert file.kind == aFile
  gold.source = file

proc init*(gold: var Gold; binary: Gold; args: ref seq[string]) =
  assert gold.kind == anInvocation
  assert binary.kind == aFile
  gold.invocation = InvocationInfo()
  gold.invocation.binary = binary
  gold.invocation.arguments = args
  gold.invocation.output = newOutputInfo()
  gold.invocation.runtime = newRuntimeInfo()

proc newInvocationInfo*(): Gold =
  result = newGold(anInvocation)
  result.invocation = InvocationInfo()

proc newInvocationInfo*(binary: Gold; args: ref seq[string]): Gold =
  result = newInvocationInfo()
  result.init(binary, args = args)

proc fibonacci*(x: int): int =
  result = if x <= 2: 1
  else: fibonacci(x - 1) + fibonacci(x - 2)

proc pack_type*[ByteStream](s: ByteStream; x: GoldKind) =
  let v = cast[char](ord(x))
  s.pack(v)

proc unpack_type*[ByteStream](s: ByteStream; x: var GoldKind) =
  var v: char
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
    raise newException(Defect, "unsupported")

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
    raise newException(Defect, "unsupported")

#[
proc pack_type*[ByteStream](s: ByteStream; x: CompilationInfo) =
  s.pack(x.oid)
  s.pack(x.entry)
  s.pack(x.source)
  s.pack(x.compiler)
  s.pack(x.binary)
  s.pack(x.invocation)
  when declared(x.runtime):
    s.pack(x.runtime)
  else:
    s.pack(x.invocation.runtime)

proc unpack_type*[ByteStream](s: ByteStream; x: var CompilationInfo) =
  s.unpack_type(x.oid)
  s.unpack_type(x.entry)
  s.unpack_type(x.source)
  s.unpack_type(x.compiler)
  s.unpack_type(x.binary)
  s.unpack_type(x.invocation)
  when declared(x.runtime):
    s.unpack_type(x.runtime)
  else:
    s.unpack_type(x.invocation.runtime)

proc pack_type*[ByteStream](s: ByteStream; x: InvocationInfo) =
  s.pack(x.oid)
  s.pack(x.entry)
  s.pack(x.arguments)
  s.pack(x.binary)
  s.pack(x.invocation)
  when declared(x.runtime):
    s.pack(x.runtime)
  else:
    s.pack(x.invocation.runtime)

proc unpack_type*[ByteStream](s: ByteStream; x: var InvocationInfo) =
  s.unpack_type(x.oid)
  s.unpack_type(x.entry)
  s.unpack_type(x.compiler)
  s.unpack_type(x.binary)
  s.unpack_type(x.invocation)
  when declared(x.runtime):
    s.unpack_type(x.runtime)
  else:
    s.unpack_type(x.invocation.runtime)
]#

proc toJson*(entry: DateTime): JsonNode =
  result = newJString entry.format(ISO8601noTZ)

proc toJson*(gold: Gold): JsonNode =
  result = %* {
    "oid": newJString $gold.oid,
    "name": newJString gold.name,
    "description": newJString gold.description,
  }
  when defined(StoreEntry):
    result["entry"] = gold.entry.toJson

proc jsonOutput*(golden: Golden): bool =
  let flags = golden.options.flags
  result = PipeOutput in flags or Interactive notin flags

proc add*[T: InvocationInfo](running: RunningResult[T]; value: T) =
  ## for stats, pull out the invocation duration from invocation info
  let seconds = value.runtime.wall.toSeconds
  running.list.append value
  running.stat.push seconds

proc add*[T: Gold](running: RunningResult[T]; value: T) =
  ## for stats, pull out the invocation duration from invocation info
  var v: StatValue
  case value.kind:
  of aCompilation:
    v = value.compilation.invocation.invocation.runtime.wall.toSeconds
  of anInvocation:
    v = value.invocation.runtime.wall.toSeconds
  else:
    raise newException(Defect, "nonsense")
  running.list.append value
  running.stat.push v

proc reset*[T: InvocationInfo](running: RunningResult[T]) =
  running.stat.clear
  var stat: seq[StatValue]
  for invocation in running.list.items:
    stat.add invocation.runtime.stat.toSeconds
  running.stat.push stat

proc add*[T: CompilationInfo](running: RunningResult[T]; value: T) =
  ## for stats, pull out the invocation duration from compilation info
  running.list.append value
  running.stat.push value.invocation.runtime.wall.toSeconds

proc pack_type*[ByteStream](s: ByteStream; x: RunningResult[CompilationInfo]) =
  s.pack_type(x.oid)
  s.pack_type(x.entry)
  s.pack_type(x.list)
  s.pack_type(x.wall)

proc unpack_type*[ByteStream](s: ByteStream; x: var RunningResult[CompilationInfo]) =
  s.unpack_type(x.oid)
  s.unpack_type(x.entry)
  s.unpack_type(x.list)
  s.unpack_type(x.wall)

template goldenDebug*() =
  when defined(debug):
    when defined(nimTypeNames):
      dumpNumberOfInstances()
    stdmsg().writeLine "total: " & $getTotalMem()
    stdmsg().writeLine " free: " & $getFreeMem()
    stdmsg().writeLine "owned: " & $getOccupiedMem()
    stdmsg().writeLine "  max: " & $getMaxMem()

include output

proc toWallDuration*(gold: Gold): Duration =
  case gold.kind:
  of anInvocation:
    result = gold.invocation.runtime.wall
  of aCompilation:
    result = gold.compilation.invocation.invocation.runtime.wall
  else:
    raise newException(Defect, "nonsense")

proc toStatValue*(gold: Gold): StatValue =
  case gold.kind:
  of anInvocation:
    result = gold.toWallDuration.toSeconds
  of aCompilation:
    result = gold.toWallDuration.toSeconds
  else:
    raise newException(Defect, "nonsense")

proc output*(golden: Golden; running: RunningResult; desc: string = "") =
  golden.output running.renderTable(desc)
