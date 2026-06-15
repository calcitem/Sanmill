# Building the Console UCI Engine (for head-to-head matches)

This guide explains how to build a minimal, GUI-free **UCI console engine**
from the master C++ sources. The resulting executable is used as the
*reference opponent* when measuring the playing strength of the Rust/TGF
engine on the Sanmill `next` branch.

It is written so that an AI Agent (or a human) can reproduce the build from a
clean checkout without prior context.

Supported build hosts: **Linux**, **macOS**, and **Windows (MinGW-w64)**.

---

## 1. What gets built

* A single console executable (default name `master_engine`, or
  `master_engine.exe` on MinGW) that speaks **standard UCI**: `uci`,
  `isready`, `setoption`, `position`, `go`, `bestmove`, `quit`.
* The **Perfect Database** tree is *not* compiled. The few entry-point
  symbols it would otherwise provide are satisfied by
  `tools/console_engine/perfect_stub.cpp`. These stubs are never executed because the engine keeps
  `UsePerfectDatabase` disabled.
* `benchmark.cpp` is excluded (it only references unused perfect-DB symbols).
* Link stubs live in `tools/console_engine/perfect_stub.cpp` (not under
  `src/`, so the Qt/Flutter CMake glob of `src/*.cpp` never picks them up).

The build is intentionally lean: one compiler invocation, ~20 seconds on a
typical desktop.

---

## 2. Prerequisites

* A C++17 compiler on `PATH`:
  * **Linux:** `g++` from `build-essential` (Debian/Ubuntu) or `gcc-c++`
    (Fedora/RHEL)
  * **macOS:** Apple `clang++` via Xcode Command Line Tools, or `g++` from
    Homebrew (`brew install gcc`)
  * **Windows:** MinGW-w64 `g++` (MSYS2, Git Bash + Strawberry Perl, etc.)
* A POSIX shell with Bash (Git Bash / MSYS2 on Windows).

Verify the toolchain:

```bash
g++ --version    # or: clang++ --version
```

If the compiler is not on `PATH`, set `CXX` explicitly (see below).

---

## 3. Build

From the repository root (`.../Sanmill-master/Sanmill`):

```bash
chmod +x scripts/build_console_engine.sh   # once, on Unix
scripts/build_console_engine.sh            # default output name
scripts/build_console_engine.sh my_engine  # custom output name
```

Environment overrides:

| Variable    | Default              | Meaning                                           |
|-------------|----------------------|---------------------------------------------------|
| `CXX`       | `g++`, else `clang++`| C++ compiler to use                               |
| `NO_STATIC` | `0`                  | set to `1` to link dynamically                    |

Platform-specific defaults:

| Host    | Default output        | Linking notes                                      |
|---------|-----------------------|----------------------------------------------------|
| MinGW   | `master_engine.exe`   | static by default (no MinGW runtime DLLs needed)   |
| Linux   | `master_engine`       | `-pthread`; static libgcc/libstdc++ when possible  |
| macOS   | `master_engine`       | `-pthread`; always dynamic (Apple toolchain)       |

Examples:

```bash
# Linux / macOS with clang++
CXX=clang++ scripts/build_console_engine.sh

# Windows (Strawberry Perl MinGW)
CXX="/c/Strawberry/c/bin/g++" scripts/build_console_engine.sh

# Force dynamic linking (MinGW/Linux)
NO_STATIC=1 scripts/build_console_engine.sh
```

### Dynamic linking on MinGW (optional)

When `NO_STATIC=1` on Windows, the `.exe` may need these DLLs next to it
(or on `PATH`):

* `libgcc_s_seh-1.dll`
* `libstdc++-6.dll`
* `libwinpthread-1.dll`

Prefer the default static MinGW build unless you have a specific reason not
to.

---

## 4. Smoke test

```bash
ENGINE=./master_engine
[[ -f ./master_engine.exe ]] && ENGINE=./master_engine.exe

printf 'uci\nsetoption name SkillLevel value 14\nsetoption name Shuffling value false\nposition startpos moves d6 f4 d2 b4 g4 d7 a4 d1\ngo\nquit\n' \
  | "${ENGINE}"
```

Expected: an `id name ...` line, `uciok`, and a final `bestmove <move>`.

On Linux you can confirm a MinGW static build has no stray runtime deps:

```bash
ldd master_engine.exe | grep -iE "libgcc|libstdc|winpthread" || echo "static OK"
```

---

## 5. Options relevant to fair matches

When comparing strength against the Rust engine, drive depth via
**SkillLevel**, not `go depth N` (this engine ignores `go depth`):

```
setoption name SkillLevel value <N>     # search depth
setoption name MoveTime value 0         # 0 = fixed depth, no time limit
setoption name Shuffling value false    # deterministic, or true for variety
```

Using `MoveTime > 0` biases the result toward whichever engine is faster, so
for an apples-to-apples depth comparison keep `MoveTime 0` and match the
SkillLevel on both sides.

---

## 6. Debug / parity commands (optional, off the hot path)

The console build also exposes a few **non-standard** verbs used only when
diagnosing search/eval divergences against the Rust engine. They never run
during a normal game and add no overhead to the standard path.

| Command                       | Purpose                                                        |
|-------------------------------|----------------------------------------------------------------|
| `valuevec [childDepth] [mv…]` | Value of each (optionally filtered) root move, White's POV     |
| `gomtdf [depth]`              | Explicit MTD(f) loop, logs each `(beta, g, bestmove)` iteration |
| `goab [depth]`                | Single plain alpha-beta search, full window, cleared TT        |
| `mobdiff`                     | Compare incremental vs recalculated mobility difference        |
| `evaldecomp`                  | Print individual evaluation terms for the current position     |

`valuevec` can additionally append NDJSON records to a log file for
move-for-move diffing. Configure via environment variables:

| Variable                   | Default   | Meaning                               |
|----------------------------|-----------|---------------------------------------|
| `SANMILL_DEBUG_LOG`        | *(unset)* | NDJSON output path; unset = stdout only |
| `SANMILL_DEBUG_SESSION`    | `debug`   | `sessionId` tag in the NDJSON         |
| `SANMILL_DEBUG_HYPOTHESIS` | `master`  | `hypothesisId` tag in the NDJSON      |

Example:

```bash
ENGINE=./master_engine
SANMILL_DEBUG_LOG="$PWD/parity.ndjson" \
  printf 'position startpos moves d6 f4 d2 b4 g4 d7 a4 d1\nvaluevec 7\nquit\n' \
  | "${ENGINE}"
```

---

## 7. Using it against the `next` branch

The Rust/TGF side lives in the main Sanmill repo. Point its head-to-head
harness at the freshly built executable, for example:

```bash
# in the main Sanmill repo (next branch)
H2H_MASTER="/path/to/Sanmill-master/Sanmill/master_engine" \
  scripts/run_head_to_head.sh -s 14 -g 100
```

On Windows, use the `.exe` path instead. See that repo's
`scripts/run_head_to_head.sh -h` for the full set of options.
