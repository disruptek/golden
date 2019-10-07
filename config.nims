# set the version of libgit2
switch("define", "git2SetVer:0.28.3")
#switch("define", "git2SetVer=0.28.3")

#hint[Processing]=off
switch("define", "threadsafe")
switch("threads", "on")
switch("opt", "speed")

# use a better poller against process termination
switch("define", "useProcessSignal")

# you can leave this enabled
switch("define", "git2DL")

# bad idea
#define:git2Static

#switch("define", "plotGraphs")
