#!/usr/bin/env bash
#
# run_head_to_head.sh - current-branch engine vs master C++ engine match,
# or self-play of either engine.
#
# Runs the `head_to_head` integration test (tgf-mill referee + engines as UCI
# subprocesses) under MinGW / Cygwin / Git-Bash on Windows.  Colours alternate
# every game and an aligned standings table is printed after each game.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

is_windows_shell() {
    case "$(uname -s 2>/dev/null || echo unknown)" in
        MINGW*|MSYS*|CYGWIN*) return 0 ;;
        *) return 1 ;;
    esac
}

engine_suffix() {
    if is_windows_shell; then
        echo ".exe"
    fi
}

default_current_engine() {
    echo "$REPO_ROOT/target/release/tgf$(engine_suffix)"
}

default_master_engine() {
    if is_windows_shell; then
        echo "D:/Repo/Sanmill-master/Sanmill/master_engine.exe"
    else
        echo "$(cd "$REPO_ROOT/.." && pwd)/Sanmill-master/master_engine"
    fi
}

# Defaults (overridable by environment, then by command-line flags).
GAMES="${GAMES:-10}"
SKILL="${SKILL:-10}"
MOVETIME="${MOVETIME:-0}"
MAX_PLIES="${MAX_PLIES:-160}"
MASTER_ENGINE="${MASTER_ENGINE:-$(default_master_engine)}"
CURRENT_OVERRIDE="${CURRENT_ENGINE:-}"
MINGW_BIN="${MINGW_BIN:-}"
SELF="${SELF:-}"

usage() {
    cat <<'EOF'
Usage: run_head_to_head.sh [OPTIONS]

Strength match between the current-branch engine and the master C++ engine,
OR a self-play test of either engine.  Colours ALTERNATE every game and an
aligned table prints Win/Draw/Loss counts and Win%/Draw%/Loss%/Score% for
White, Black and total after each game.  tgf-mill is the authoritative referee.

Modes:
  (default)            current vs master; table rows = current's colour.
  --self current       current plays ITSELF; rows = White/Black side.
  --self master        master  plays ITSELF; rows = White/Black side.
  Self-play uses two independent instances of one engine, so the White vs
  Black Score% gap reveals the game's first/second-player bias (useful to tell
  a colour bug apart from Mill's natural second-player edge).

Options:
  -g, --games N        games per colour (total played = 2*N)      [default: 10]
  -s, --skill N        Skill Level for the engine(s), 0..30       [default: 10]
  -t, --time SECONDS   per-move Thinking Time, 0..60, 0=unlimited [default: 0]
  -p, --max-plies N    ply cap; reaching it scores a draw         [default: 160]
      --self ENGINE     self-play ENGINE (current|master) instead of vs match
  -m, --master PATH    path to master_engine
  -c, --current PATH   path to current engine (default: freshly built tgf)
      --mingw-bin DIR   dir holding MinGW runtime DLLs to copy next to master
  -h, --help           show this help and exit

Each option also has an environment-variable form (command-line flags win):
  GAMES, SKILL, MOVETIME (seconds), MAX_PLIES, SELF, MASTER_ENGINE,
  CURRENT_ENGINE, MINGW_BIN.

Fairness notes:
  * Depth is controlled by --skill: the master engine IGNORES UCI `go depth N`
    and always derives depth from Skill Level, so SKILL is the only correct way
    to set an equal depth.
  * --time 0 (fixed depth) is speed-independent and matches "Thinking Time 0".
    --time >0 favours the FASTER engine (master, C++); use only for a
    deliberately time-limited comparison.

Examples:
  run_head_to_head.sh                       # current vs master, skill 10, 10 games/colour
  run_head_to_head.sh -s 14 -g 50           # skill 14, 50 games/colour
  run_head_to_head.sh --self master -g 50    # master self-play (colour bias)
  run_head_to_head.sh --self current -g 50   # current self-play (colour bias)
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)      usage; exit 0 ;;
        -g|--games)     GAMES="$2"; shift 2 ;;
        --games=*)      GAMES="${1#*=}"; shift ;;
        -s|--skill)     SKILL="$2"; shift 2 ;;
        --skill=*)      SKILL="${1#*=}"; shift ;;
        -t|--time)      MOVETIME="$2"; shift 2 ;;
        --time=*)       MOVETIME="${1#*=}"; shift ;;
        -p|--max-plies) MAX_PLIES="$2"; shift 2 ;;
        --max-plies=*)  MAX_PLIES="${1#*=}"; shift ;;
        --self)         SELF="$2"; shift 2 ;;
        --self=*)       SELF="${1#*=}"; shift ;;
        -m|--master)    MASTER_ENGINE="$2"; shift 2 ;;
        --master=*)     MASTER_ENGINE="${1#*=}"; shift ;;
        -c|--current)   CURRENT_OVERRIDE="$2"; shift 2 ;;
        --current=*)    CURRENT_OVERRIDE="${1#*=}"; shift ;;
        --mingw-bin)    MINGW_BIN="$2"; shift 2 ;;
        --mingw-bin=*)  MINGW_BIN="${1#*=}"; shift ;;
        *) echo "Unknown option: $1" >&2; echo "Try '$0 -h' for help." >&2; exit 2 ;;
    esac
done

case "$SELF" in
    "")      MODE="vs";           NEED_CURRENT=1; NEED_MASTER=1 ;;
    current) MODE="self-current"; NEED_CURRENT=1; NEED_MASTER=0 ;;
    master)  MODE="self-master";  NEED_CURRENT=0; NEED_MASTER=1 ;;
    *) echo "ERROR: --self must be 'current' or 'master' (got '$SELF')" >&2; exit 2 ;;
esac

# Convert a path to a Windows form the native engine binaries accept.
winpath() { cygpath -m "$1" 2>/dev/null || echo "$1"; }

CURRENT_ENGINE="${CURRENT_OVERRIDE:-$(default_current_engine)}"
if [ "$NEED_CURRENT" -eq 1 ]; then
    if [ -z "$CURRENT_OVERRIDE" ]; then
        echo ">> Building current engine (tgf, release) ..."
        ( cd "$REPO_ROOT" && cargo build --release -p tgf-cli )
    fi
    if [ ! -f "$CURRENT_ENGINE" ]; then
        echo "ERROR: current engine not found: $CURRENT_ENGINE" >&2
        exit 1
    fi
fi

if [ "$NEED_MASTER" -eq 1 ]; then
    # Best-effort: make sure a MinGW-built master engine can find its DLLs.
    master_dir="$(dirname "$MASTER_ENGINE")"
    if is_windows_shell && [ -f "$MASTER_ENGINE" ] && [ ! -f "$master_dir/libstdc++-6.dll" ]; then
        cand="$MINGW_BIN"
        if [ -z "$cand" ] && command -v g++ >/dev/null 2>&1; then
            cand="$(dirname "$(command -v g++)")"
        fi
        if [ -n "$cand" ]; then
            echo ">> Copying MinGW runtime DLLs from $cand ..."
            for d in libstdc++-6.dll libgcc_s_seh-1.dll libwinpthread-1.dll; do
                [ -f "$cand/$d" ] && cp -n "$cand/$d" "$master_dir/" 2>/dev/null && echo "   copied $d" || true
            done
        else
            echo ">> NOTE: if the master engine fails to start, copy its MinGW"
            echo "         runtime DLLs next to it, or pass --mingw-bin <dir>."
        fi
    fi
    if [ ! -f "$MASTER_ENGINE" ]; then
        echo "ERROR: master engine not found: $MASTER_ENGINE" >&2
        echo "       Pass --master /path/to/master_engine" >&2
        exit 1
    fi
fi

echo ">> Config: mode=$MODE  skill=$SKILL  games/colour=$GAMES  thinking_time=${MOVETIME}s  ply_cap=$MAX_PLIES"
[ "$NEED_CURRENT" -eq 1 ] && echo "     current = $CURRENT_ENGINE"
[ "$NEED_MASTER" -eq 1 ] && echo "     master  = $MASTER_ENGINE"
if [ "$MOVETIME" -gt 0 ] 2>/dev/null; then
    echo "     (thinking_time>0: time-limited; favours the faster engine, master)"
fi

cd "$REPO_ROOT"
H2H_CURRENT="$(winpath "$CURRENT_ENGINE")" \
H2H_MASTER="$(winpath "$MASTER_ENGINE")" \
H2H_MODE="$MODE" \
H2H_SKILL="$SKILL" \
H2H_GAMES="$GAMES" \
H2H_MOVETIME="$MOVETIME" \
H2H_MAX_PLIES="$MAX_PLIES" \
H2H_GO_CURRENT="go depth 0" \
H2H_GO_MASTER="go" \
    cargo test -p tgf-mill --release --test head_to_head \
        head_to_head_vs_master -- --ignored --nocapture
