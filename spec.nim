import os
import times
import md5
import oids
import strutils

type
  GoldObject* = ref object of RootObj
    oid*: Oid
    name*: string
    entry*: DateTime

  FileDetail* = ref object of GoldObject
    digest*: MD5Digest
    info*: FileInfo
    path*: string

  RuntimeInfo* = ref object of GoldObject
    wall*: float64
    cpu*: float64
    memory*: int

  OutputInfo* = ref object of GoldObject
    code*: int
    stdout*: FileDetail
    stderr*: FileDetail

  InvocationInfo* = ref object of GoldObject
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
    runtime*: RuntimeInfo
    source*: FileDetail

  BenchmarkResult* = ref object of GoldObject
    binary*: FileDetail
    compilations*: seq[CompilationInfo]
    invocations*: seq[InvocationInfo]

  Golden* = ref object of GoldObject
    compiler*: CompilerInfo

template initGold*(gold: typed; text: typed) =
  gold.oid = genOid()
  gold.name = `text`
  gold.entry = now()

method `$`*(gold: GoldObject): string {.base.} =
  result = gold.name & ":" & $gold.oid & " entry " & $gold.entry

proc digestOfFileContents(path: string): MD5Digest =
  let data = readFile(path)
  result = data.toMD5

proc newFileDetail*(path: string): FileDetail =
  new result
  result.initGold "file"
  result.path = path
  result.digest = digestOfFileContents(path)

proc newFileDetail*(path: string; info: FileInfo): FileDetail =
  result = newFileDetail(path)
  result.info = info

template newFileDetailWithInfo*(path: string): FileDetail =
  newFileDetail(path, getFileInfo(path))

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

proc `$`*(compiler: CompilerInfo): string =
  let digest = $compiler.binary.digest
  result = "Nim " & compiler.version
  if digest != "00000000000000000000000000000000":
    result &= " digest " & digest
  result &= " built " & $compiler.binary.info.lastWriteTime

proc newGolden*(): Golden =
  new result
  result.initGold "golden"
  result.compiler = newCompilerInfo()

proc newBenchmarkResult*(): BenchmarkResult =
  new result
  result.initGold "bench"

proc appearsBenchmarkable*(path: string): bool =
  ## true if the path looks like something we can bench
  var detail = newFileDetailWithInfo(path)
  if not path.endsWith(".nim"):
    return false
  if detail.info.kind notin {pcFile, pcLinkToFile}:
    return false
  result = true
