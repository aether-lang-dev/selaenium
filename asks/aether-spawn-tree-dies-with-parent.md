# Ask (aether std.os): a spawned process tree that ends with its parent

**Status:** OPEN. Filed from selaenium 2026-11-20; not yet filed upstream in
`~/scm/aether/asks/` (this agent was told not to touch the aether checkout).
Worked around in selaenium by `selenium_core/drivermgr/proctree/` (C, about 300
lines), which can be deleted once std.os has what is asked for here.

## Motivation

selaenium launches a WebDriver driver (chromedriver, geckodriver, appium) with
`os.spawn_proc_to`, and the driver launches a browser. Since 0.923 that child
leads a process group (a Job Object on Windows) and `os.kill(token, sig)`
signals the group, so a clean stop reaches the browser. Two things are still
missing, and both left real browsers running on a lab host:

1. **Nothing ends the tree when the parent dies.** A test killed by a timeout,
   a crash, a program that exits without calling stop: the driver and browser
   keep running with ppid 1. A library loaded into the BEAM, the JVM or Julia
   cannot rely on its own signal handlers or atexit to clean up, because the
   host owns those (and the BEAM ignores SIGCHLD, Julia blocks SIGTERM).
   Windows: the job has no `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` (see the
   comment on `winproc_remove`), so the same is true there.
2. **A group kill misses a descendant that left the group.** Anything that
   calls `setsid()` or `setpgid()` (Chromium's crash handler does on some
   builds, as do daemonising helpers) survives `os.kill(token, ...)`.

## Minimal repro (Aether 0.931.0, Linux x86_64, cachyos)

`tree_outlives_parent.ae`:

```aether
import std.os
import std.list
import std.string

extern exit(code: int)

main() {
    if os.args_count() >= 2 && string.equals(os.args_get(1), "--parent") == 1 {
        argv = list.new()
        list.add(argv, "-c")
        list.add(argv, "echo $$ > ${os.args_get(2)}.child; exec sleep 300")
        _t, _e = os.spawn_proc_to("/bin/sh", argv, null, "/dev/null")
        sleep(500)
        exit(0)   // the parent ends without killing or waiting for the child
    }
    // Case 1: parent exits, child survives.
    pf = "${os.temp_dir()}/tree_outlives_parent"
    argv = list.new()
    list.add(argv, "--parent")
    list.add(argv, pf)
    tok, _e = os.spawn_proc(os.argv0(), argv, null)
    _w, _we = os.wait(tok)
    sleep(300)
    out, _s, _x = os.run_capture("/bin/sh", list_of2("-c", "p=$(cat ${pf}.child); kill -0 $p 2>/dev/null && echo SURVIVED $p && kill $p || echo gone"), null)
    println("case 1 (parent exited): ${string.trim(out)}")
    // Case 2: os.kill on the token misses a setsid'd grandchild.
    a2 = list.new()
    list.add(a2, "-c")
    list.add(a2, "setsid sh -c 'echo $$ > ${pf}.esc; exec sleep 300' & exec sleep 300")
    t2, _e2 = os.spawn_proc_to("/bin/sh", a2, null, "/dev/null")
    sleep(500)
    _k = os.kill(t2, 15)
    _w2, _we2 = os.wait(t2)
    sleep(300)
    out2, _s2, _x2 = os.run_capture("/bin/sh", list_of2("-c", "p=$(cat ${pf}.esc); kill -0 $p 2>/dev/null && echo SURVIVED $p && kill $p || echo gone"), null)
    println("case 2 (setsid descendant after os.kill): ${string.trim(out2)}")
}

list_of2(a: string, b: string) -> ptr {
    l = list.new()
    list.add(l, a)
    list.add(l, b)
    return l
}
```

Output on 0.931.0:

```
case 1 (parent exited): SURVIVED 164420
case 2 (setsid descendant after os.kill): SURVIVED 164441
```

Wanted: `gone` for both, with an opt-in flag on the spawn.

## Suggested shape

An option on `spawn_proc_to` (or a sibling, `spawn_tree`) meaning "this child's
whole tree ends when I end or when I kill it":

- **Linux**: a forked supervisor (no exec needed) that is
  `PR_SET_CHILD_SUBREAPER`, watches the parent with a `pidfd`, and on parent
  death or kill does SIGTERM to the group, a grace period, SIGKILL to the group,
  then SIGKILL to every remaining child listed in `/proc/self/task/<tid>/children`
  until it has none. `PR_SET_PDEATHSIG` is NOT enough on its own: it fires when
  the parent THREAD exits, and a managed runtime spawns from short-lived or
  pooled threads.
- **FreeBSD**: the same with `procctl(PROC_REAP_ACQUIRE)` and
  `PROC_REAP_KILL`, and kqueue `EVFILT_PROC`/`NOTE_EXIT` on the parent.
- **macOS**: kqueue `NOTE_EXIT` on the parent plus the group kill. There is no
  subreaper, so a descendant that leaves the group is not covered.
- **Windows**: `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` on the job, with the parent
  holding the only handle.

selaenium's implementation of exactly this is
`selenium_core/drivermgr/proctree/proctree.c`; its test is
`selenium_core/tests/driver_lifetime_live.ae` (6 cases, 4 of them fail on the
plain `os.spawn_proc_to` path).
