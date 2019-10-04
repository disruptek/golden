import os
import times
import lists
import md5
import oids
import stats
import strutils
import strformat
import terminal

type
  GoldObject* = ref object of RootObj
    oid*: Oid
    name*: string
    entry*: DateTime

  FileDetail* = ref object of GoldObject
    digest*: MD5Digest
    info*: FileInfo
    path*: string

  WallDuration = Duration
  CpuDuration = float64
  MemorySize = int

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
    arguments*: seq[string]
    runtime*: RuntimeInfo
    output*: OutputInfo

  CompilerInfo* = ref object of GoldObject
    binary*: FileDetail
    version*: string
    major*: int
    minor*: int
    patch*: int
    commit*: string

  CompilationInfo* = ref object of GoldObject
    compiler*: CompilerInfo
    invocation*: InvocationInfo
    source*: FileDetail
    binary*: FileDetail

  RunningResult*[T] = ref object of GoldObject
    list: SinglyLinkedList[T]
    wall: RunningStat
    cpu: RunningStat
    memory: RunningStat

  BenchmarkResult* = ref object of GoldObject
    binary*: FileDetail
    compilations*: RunningResult[CompilationInfo]
    invocations*: RunningResult[InvocationInfo]

  Golden* = ref object of GoldObject
    compiler*: CompilerInfo
    interactive*: bool

template initGold*(gold: typed; text: typed) =
  gold.oid = genOid()
  gold.name = `text`
  gold.entry = now()

method `$`*(gold: GoldObject): string {.base.} =
  result = gold.name & ":" & $gold.oid & " entry " & $gold.entry

proc `$`*(detail: FileDetail): string =
  result = detail.path

proc `$`*(compiler: CompilerInfo): string =
  let digest = $compiler.binary.digest
  result = "Nim " & compiler.version
  if digest != "00000000000000000000000000000000":
    result &= " digest " & digest
  result &= " built " & $compiler.binary.info.lastWriteTime

proc digestOfFileContents(path: string): MD5Digest =
  assert path.fileExists
  let data = readFile(path)
  result = data.toMD5

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

proc `$`*(runtime: RuntimeInfo): string =
  result = runtime.wall.render

proc len*[T](list: SinglyLinkedList[T]): int =
  var head = list.head
  while head != nil:
    result.inc
    head = head.next

proc len*(running: RunningResult): int =
  result = running.wall.n

proc `$`*(invocation: InvocationInfo): string =
  result = $invocation.binary
  result &= invocation.arguments.join(" ")

proc `$`*(bench: BenchmarkResult): string =
  result = $bench.GoldObject
  if bench.invocations.len > 0:
    let invocation = bench.invocations.list.head.value
    result &= "\n" & $invocation
  result &= "\ncompilation(s) -- " & $bench.compilations.wall
  result &= "\n invocation(s) -- " & $bench.invocations.wall

template okay*(invocation: InvocationInfo): bool =
  ## was the invocation successful?
  invocation.output.code == 0

proc add*[T: InvocationInfo](running: RunningResult[T]; value: T) =
  ## for stats, pull out the invocation duration from invocation info
  running.list.append value
  running.wall.push value.runtime.wall.inNanoseconds.float64 / 1_000_000_000

proc add*[T: CompilationInfo](running: RunningResult[T]; value: T) =
  ## for stats, pull out the invocation duration from compilation info
  running.list.append value
  running.wall.push value.invocation.runtime.wall.inNanoseconds.float64 / 1_000_000_000

proc newRuntimeInfo*(): RuntimeInfo =
  new result
  result.initGold "runtime"

proc newFileDetail*(path: string): FileDetail =
  new result
  result.initGold "file"
  result.path = path.absolutePath.normalizedPath
  result.digest = digestOfFileContents(path)

proc newFileDetail*(path: string; info: FileInfo): FileDetail =
  result = newFileDetail(path)
  result.info = info

proc newFileDetailWithInfo*(path: string): FileDetail =
  assert path.fileExists
  result = newFileDetail(path, getFileInfo(path))

proc newCompilerInfo*(hint: string = ""): CompilerInfo =
  var path: string
  new result
  result.initGold "compiler"
  result.version = NimVersion
  result.major = NimMajor
  result.minor = NimMinor
  result.patch = NimPatch
  if hint == "":
    path = getCurrentCompilerExe()
  else:
    path = hint
  result.binary = newFileDetailWithInfo(path)

proc newGolden*(): Golden =
  new result
  result.initGold "golden"
  result.compiler = newCompilerInfo()
  result.interactive = stdmsg().isatty

proc newRunningResult*[T](): RunningResult[T] =
  new result
  result.initGold "running"
  result.list = initSinglyLinkedList[T]()

proc newBenchmarkResult*(): BenchmarkResult =
  new result
  result.initGold "bench"
  result.compilations = newRunningResult[CompilationInfo]()
  result.invocations = newRunningResult[InvocationInfo]()

proc newOutputInfo*(): OutputInfo =
  new result
  result.initGold "output"

proc newInvocationInfo*(binary: FileDetail; args: seq[string] = @[]): InvocationInfo =
  new result
  result.initGold "invoked"
  result.binary = binary
  result.arguments = args
  result.output = newOutputInfo()
  result.runtime = newRuntimeInfo()

proc newCompilationInfo*(compiler: CompilerInfo = nil): CompilationInfo =
  new result
  result.initGold "compile"
  result.compiler = compiler
  if result.compiler == nil:
    result.compiler = newCompilerInfo()

proc appearsBenchmarkable*(path: string): bool =
  ## true if the path looks like something we can bench
  var detail = newFileDetailWithInfo(path)
  if not path.endsWith(".nim"):
    return false
  if detail.info.kind notin {pcFile, pcLinkToFile}:
    return false
  result = true

proc fibonacci*(x: int): int =
  result = if x <= 2: 1
  else: fibonacci(x - 1) + fibonacci(x - 2)
