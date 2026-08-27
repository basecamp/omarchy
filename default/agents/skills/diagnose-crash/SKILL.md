---
name: diagnose-crash
description: >
  Diagnose why a program crashed on this machine, from a systemd-coredump core dump.
  Use when a process has segfaulted, aborted, or otherwise dumped core, when asked
  why an application crashed or disappeared, or when a "Process crashed:" desktop
  notification is acted on. Triggers: crash, segfault, SIGSEGV, SIGABRT, core dump,
  coredumpctl, "why did X crash", "X keeps crashing", backtrace symbolization.
  Covers reporting a confirmed Omarchy bug upstream — see reporting.md.
---

# Diagnosing a Crash

Work from evidence. The goal is an honest account of what happened, not a
plausible-sounding story.

## Establish the facts

`coredumpctl info <pid>` is the starting point. Beyond the backtrace, note the
**command line** the process was started with — it usually reveals what the
program was working on when it died, which is often the whole answer.

`coredumpctl list` shows whether this crash is a one-off or a pattern. Repeated
crashes of the same program, or several programs dying together, point somewhere
different than a single failure does.

## Rule out the boring causes first

Check resource exhaustion before blaming the program: `free -h`, and the journal
for OOM kills. A process killed by the OOM killer is not a bug in that process.

## Correlate against the timeline

The crash timestamp is the most underused piece of evidence. Compare it against:

- **Filesystem mtimes.** A directory or file whose mtime lands on the same second
  as the crash strongly suggests what triggered it.
- **The journal** around that moment, for related warnings from the same or
  neighbouring processes.
- **Recent package updates.** A crash that starts right after an update points at
  the update.

## Read the whole core, not just frame 0

Thread stacks other than the crashing one show what work was **in flight** —
thumbnailers, image loaders, IPC readers, GPU queues. That context often explains
the trigger even when the crashing frame itself cannot be symbolized.

Note any third-party code in the address space: file-manager or browser
extensions, plugins, out-of-tree drivers. In-process third-party code is a common
crash source and worth flagging — but do not pin blame on it without evidence
that it is actually implicated.

## Symbolize when you can

This is Arch, which runs a public debuginfod server:

```bash
core=$(mktemp -t crash-XXXXXX.core)
trap 'rm -f "$core"' EXIT
coredumpctl dump <pid> --output="$core"
DEBUGINFOD_URLS="https://debuginfod.archlinux.org" \
  gdb -q <executable> "$core" \
  -batch -ex 'set debuginfod enabled on' -ex 'bt'
```

A core is a verbatim copy of the process's memory and can hold passwords, tokens,
and private documents. Write it to a fresh `mktemp` path rather than a predictable
shared one, and delete it when you are done — never leave it lying in `/tmp`.

Many packages publish no debug symbols. When frames stay unresolved, say so —
never invent function names to fill the gap. An unsymbolized stack still has
shape: which library each frame belongs to, and whether the crash came from a
signal handler, a main loop, or a worker thread.

## Report

1. What crashed, and what it was doing at the time.
2. The most likely mechanism — separating clearly what the evidence **proves**
   from what you are **inferring**.
3. Whether any user data was lost, and where it can be recovered from. Check the
   trash before concluding anything is gone.
4. Whether it is likely to recur, and what would avoid or fix it.

Be straight about the limits of the evidence. If the cause is genuinely
ambiguous, say so rather than assembling confidence out of guesswork.

**Leave the system as you found it.** Diagnosis reads; it does not fix, tidy, or
reconfigure. The one thing to clean up is your own: delete the core you extracted
above, which is a copy of the crashed process's memory. The single change a
diagnosis may make is the mute below, and only when the user asks for it.

## Offer to stop the notifications for this program

A crash that is now understood keeps announcing itself, and understanding it
rarely stops it happening: an upstream bug waiting on a release, a program that
dumps core every time it exits, a driver that misbehaves on this hardware. Finish
by offering to silence crash notifications for **that one program**:

```bash
omarchy-toggle 'crash-ignore/<program>' on
```

`<program>` is the `process:` name in the crash facts, verbatim. The watcher works
that name out and then announces it, so what you were handed is already the exact
string the mute is keyed on — do not re-derive it from `coredumpctl` when you were
given it, because the two agree for ordinary names and not for strange ones.

A diagnosis started by hand from `omarchy agent crash <pid>` is given no name, so
there you do have to work it out the way the watcher does: the executable's
basename when an absolute `Executable:` was recorded, otherwise the process name
with everything up to the last `/` dropped, and `unknown` when that leaves
nothing, `.` or `..`. Prefer the executable — the kernel truncates the process
name to 15 characters and does not truncate the basename, so a mute on the
truncated one matches nothing, forever, while looking like it worked.

The name is whatever the crashed program's author chose to call a file, so handle
it as hostile text rather than as a word. Single quotes hold a space or a `$(...)`,
but a name containing a single quote closes them and the rest of it runs as your
shell — escape it, or the program that just crashed chooses the command. Then
check the flag actually arrived, which is also how you learn a name was too long
for the filesystem to keep:

```bash
omarchy-toggle-enabled 'crash-ignore/<program>' && echo muted
```

Offer it; never run it unprompted. The user may well want to keep being told.

Say how to undo it in the same breath, so it is not a one-way door: the same
command with `off` un-mutes, and each mute is one file in
`~/.local/state/omarchy/toggles/crash-ignore/`, which `ls -A` lists — the
directory appears with the first mute, so before that there is nothing to list.

The key is a bare name, so programs sharing one share a mute, and anything run
through an interpreter is keyed as the interpreter. Muting `python3.13` or `node`
silences every other Python or Node program on the machine, which is rarely what
the user means: say so rather than quietly doing it.

This silences one program. Every other crash still notifies, and the muted
program still crashes — nothing here fixes anything, and a mute offered instead
of a fix that was within reach is the wrong answer. If the user wants crash
notifications off altogether, that is _Trigger > Toggle > Crash Capture_ instead.

## If it is an Omarchy bug

Most application crashes are upstream bugs in those applications, not Omarchy's
doing. In the minority of cases where the cause really does sit within Omarchy's
sphere of control, read [`reporting.md`](reporting.md) before offering to file
anything.
