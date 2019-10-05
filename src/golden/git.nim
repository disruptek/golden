import nimgit2

proc init*() =
  let lg = git_libgit2_init()
  if lg != 0:
    echo "unable to initialize libgit2; error code " & $lg
    when declared(git_error_last):
      let err = git_error_last()
      echo "message: " & err.message
    else:
      {.warning: "git_error_last() not found".}
