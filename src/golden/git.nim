#[

this is a long rabbithole, so focus a bit on the target.

we want to be able to add metadata
  - for a file
    - about all we can determine is that it's versioned
      and it's modified or not; changes to the repo/env
      invalidate all other assumptions
  - for a repo
    - so we can reproduce builds or confirm binary identity

we want to to use that metadata to make decisions and take action
  - roll the compiler
  - roll the target

]#

import nimgit2

{.hint: "libgit2 version " & git2SetVer.}

proc dumpError() =
  let err = git_error_last()
  if err == nil:
    return
  stdmsg().writeLine "\"" & $err.message & "\""
  quit(err.klass)

proc init*() =
  let count = git_libgit2_init()
  if count > 0:
    return
  assert count != 0, "unable to initialize libgit2; no error code!"
  dumpError()

proc shutdown*() =
  let count = git_libgit2_shutdown()
  if count == 0:
    return
  assert count > 0, $count & " too many git inits"
  dumpError()
