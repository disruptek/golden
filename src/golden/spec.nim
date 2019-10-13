#[

basic types and operations likely shared by all modules

]#
import os
import times
import oids
import strutils
import terminal

when defined(useSHA):
  import std/sha1
else:
  import md5

import msgpack4nim

export oids
export times

const
  ISO8601noTZ* = initTimeFormat "yyyy-MM-dd\'T\'HH:mm:ss\'.\'fff\'Z\'"
  billion* = 1_000_000_000

type
  BenchmarkusInterruptus* = IOError

  Sync* {.deprecated,pure.} = enum
    Okay
    Read
    Write
    Error

  ModelVersion* = enum
    v0 = "(none)"
    v1 = "dragons; really alpha"

  ModelEvent* = enum
    Upgrade
    Downgrade

  GoldObject* = ref object of RootObj
    oid*: Oid
    name*: string
    description*: string
    entry*: DateTime
    dirty*: bool

  FileSize* = BiggestInt
  FileDetail* = ref object of GoldObject
    digest*: string
    size*: FileSize
    path*: string
    mtime*: Time
    kind*: PathComponent

  WallDuration* = Duration
  CpuDuration* = float64
  MemorySize* = int

  RuntimeInfo* = ref object of GoldObject
    wall*: WallDuration
    cpu*: CpuDuration
    memory*: MemorySize

  OutputInfo* = ref object of GoldObject
    code*: int
    stdout*: string
    stderr*: string

  InvocationInfo* = ref object of GoldObject
    binary*: FileDetail
    arguments*: ref seq[string]
    runtime*: RuntimeInfo
    output*: OutputInfo

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

  Golden* = ref object of GoldObject
    options*: GoldenOptions

method init*(gold: GoldObject; text: string) {.base.} =
  gold.oid = genOid()
  gold.name = text
  gold.entry = now()
  assert text.len <= 16
  gold.dirty = true

proc digestOfFileContents(path: string): string =
  assert path.fileExists
  when defined(useSHA):
    result = $secureHashFile(path)
  else:
    let data = readFile(path)
    result = $toMD5(data)

proc digestOf*(content: string): string =
  when defined(useSHA):
    result = $secureHash(content)
  else:
    result = $toMD5(content)

proc commandLine*(invocation: InvocationInfo): string =
  ## compose the full commandLine for the given invocation
  result = invocation.binary.path
  if invocation.arguments != nil:
    if invocation.arguments[].len > 0:
      result &= " " & invocation.arguments[].join(" ")

template okay*(invocation: InvocationInfo): bool =
  ## was the invocation successful?
  invocation.output.code == 0

proc newRuntimeInfo*(): RuntimeInfo =
  new result
  result.init "runtime"

proc newFileDetail*(path: string): FileDetail =
  new result
  result.init "file"
  result.path = path

proc newFileDetail*(path: string; size: FileSize; digest: string): FileDetail =
  result = newFileDetail(path)
  result.size = size
  result.digest = digest

proc newFileDetail*(path: string; info: FileInfo): FileDetail =
  let normal = path.absolutePath.normalizedPath
  result = newFileDetail(normal, info.size, digestOfFileContents(normal))
  result.mtime = info.lastWriteTime
  result.kind = info.kind

proc newFileDetailWithInfo*(path: string): FileDetail =
  assert path.fileExists, "path `" & path & "` does not exist"
  result = newFileDetail(path, getFileInfo(path))

proc newGolden*(): Golden =
  new result
  result.init "golden"
  if stdmsg().isatty:
    result.options.flags.incl Interactive
    result.options.flags.incl ColorConsole
  else:
    result.options.flags.incl PipeOutput

proc newOutputInfo*(): OutputInfo =
  new result
  result.init "output"

proc init*(invocation: var InvocationInfo; binary: FileDetail; args: ref seq[string]) =
  invocation.binary = binary
  invocation.arguments = args
  invocation.output = newOutputInfo()
  invocation.runtime = newRuntimeInfo()

proc newInvocationInfo*(): InvocationInfo =
  new result
  procCall result.GoldObject.init "invoked"

proc newInvocationInfo*(binary: FileDetail; args: ref seq[string]): InvocationInfo =
  result = newInvocationInfo()
  result.init(binary, args = args)

proc fibonacci*(x: int): int =
  result = if x <= 2: 1
  else: fibonacci(x - 1) + fibonacci(x - 2)

proc pack_type*[ByteStream](s: ByteStream; x: DateTime) =
  s.pack(x.inZone(local()).format(ISO8601noTZ))

proc unpack_type*[ByteStream](s: ByteStream; x: var DateTime) =
  var datetime: string
  s.unpack_type(datetime)
  x = datetime.parse(ISO8601noTZ).inZone(local())

proc pack_type*[ByteStream](s: ByteStream; x: Timezone) =
  s.pack(x.name)

proc unpack_type*[ByteStream](s: ByteStream; x: var Timezone) =
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

proc pack_type*[ByteStream](s: ByteStream; x: Oid) =
  s.pack($x)

proc unpack_type*[ByteStream](s: ByteStream; x: var Oid) =
  var oid: string
  s.unpack_type(oid)
  x = parseOid(oid)

proc pack_type*[ByteStream](s: ByteStream; x: GoldObject) =
  s.pack($x)

proc unpack_type*[ByteStream](s: ByteStream; x: var GoldObject) =
  var oid: string
  s.unpack_type(oid)
  x = parseOid(oid)

proc pack_type*[ByteStream](s: ByteStream; x: FileDetail) =
  s.pack(x.oid)
  s.pack(x.entry)
  s.pack(x.digest)
  s.pack(x.size)
  s.pack(x.path)
  s.pack(x.kind)
  s.pack(x.mtime)

proc unpack_type*[ByteStream](s: ByteStream; x: var FileDetail) =
  s.unpack_type(x.oid)
  s.unpack_type(x.entry)
  s.unpack_type(x.digest)
  s.unpack_type(x.size)
  s.unpack_type(x.path)
  s.unpack_type(x.kind)
  s.unpack_type(x.mtime)

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

template goldenDebug*() =
  when defined(debug):
    when defined(nimTypeNames):
      dumpNumberOfInstances()
    stdmsg().writeLine "total: " & $getTotalMem()
    stdmsg().writeLine " free: " & $getFreeMem()
    stdmsg().writeLine "owned: " & $getOccupiedMem()
    stdmsg().writeLine "  max: " & $getMaxMem()
