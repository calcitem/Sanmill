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
ENGINE_THREADS="${ENGINE_THREADS:-${H2H_ENGINE_THREADS:-1}}"
MOVETIME="${MOVETIME:-0}"
# Sub-second per-move time in milliseconds (Sanmill-only, 0..=60000).
# Takes priority over MOVETIME when set.  Use for fast Sanmill-vs-Sanmill
# matches (e.g. eval-tuning verification).  Typical value: 200 (0.2 s).
MOVETIME_MS="${MOVETIME_MS:-}"
MAX_PLIES="${MAX_PLIES:-160}"
N_MOVE_RULE="${N_MOVE_RULE:-20}"
ENDGAME_N_MOVE_RULE="${ENDGAME_N_MOVE_RULE:-20}"
OPENING_PLIES="${OPENING_PLIES:-0}"
OPENING_SEED="${OPENING_SEED:-0x9E3779B97F4A7C15}"
OPENING_DB_PATH="${OPENING_DB_PATH:-$REPO_ROOT/src/ui/flutter_app/assets/databases}"
JOBS="${JOBS:-${H2H_JOBS:-1}}"
MASTER_ENGINE="${MASTER_ENGINE:-$(default_master_engine)}"
CURRENT_OVERRIDE="${CURRENT_ENGINE:-}"
CURRENT_ARGS="${CURRENT_ARGS:-uci}"
MASTER_ARGS="${MASTER_ARGS:-}"
CURRENT_ENV="${CURRENT_ENV:-${H2H_CURRENT_ENV:-}}"
MASTER_ENV="${MASTER_ENV:-${H2H_MASTER_ENV:-}}"
CURRENT_GO="${CURRENT_GO:-go depth 0}"
MASTER_GO="${MASTER_GO:-go}"
MINGW_BIN="${MINGW_BIN:-}"
SELF="${SELF:-}"
VS_PERFECT="${VS_PERFECT:-}"
PERFECT_DB_PATH="${PERFECT_DB_PATH:-${OPENING_DB_PATH:-$REPO_ROOT/src/ui/flutter_app/assets/databases}}"
PERFECT_DB_CACHE="${PERFECT_DB_CACHE:-32}"

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
      --time-ms MS     per-move time in milliseconds, 0..60000
                         (Sanmill-only; takes priority over --time)
  -p, --max-plies N    ply cap; reaching it scores a draw         [default: 160]
  -j, --jobs N         parallel worker count                       [default: 1]
      --n-move-rule N  no-capture draw threshold                  [default: 20]
      --endgame-n-move-rule N
                         endgame no-capture draw threshold        [default: 20]
      --opening-plies N
                         paired Perfect DB random opening plies    [default: 0]
      --opening-seed N  seed for paired Perfect DB random openings
      --opening-db PATH Perfect DB asset directory
      --self ENGINE     self-play ENGINE (current|master) instead of vs match
      --vs-perfect    make the opponent engine use the Perfect DB
      --perfect-db PATH
                     Perfect DB directory for --vs-perfect
  -m, --master PATH    path to master_engine
  -c, --current PATH   path to current engine (default: freshly built tgf)
      --current-args A extra args for current engine                  [default: uci]
      --master-args A  extra args for master/opponent engine          [default: empty]
      --current-env E  env assignments for current, KEY=VALUE...
      --master-env E   env assignments for master/opponent, KEY=VALUE...
      --current-go CMD go command for current engine             [default: go depth 0]
      --master-go CMD  go command for master/opponent engine     [default: go]
      --mingw-bin DIR   dir holding MinGW runtime DLLs to copy next to master
  -h, --help           show this help and exit

Each option also has an environment-variable form (command-line flags win):
  GAMES, SKILL, ENGINE_THREADS, MOVETIME (seconds), MOVETIME_MS (ms,
  priority), MAX_PLIES, JOBS, SELF, MASTER_ENGINE,
  CURRENT_ENGINE, CURRENT_ARGS, MASTER_ARGS, CURRENT_ENV, MASTER_ENV,
  H2H_CURRENT_ENV, H2H_MASTER_ENV, CURRENT_GO, MASTER_GO,
  N_MOVE_RULE, ENDGAME_N_MOVE_RULE, OPENING_PLIES, OPENING_SEED,
  OPENING_DB_PATH, MINGW_BIN.

Fairness notes:
  * Depth is controlled by --skill: the master engine IGNORES UCI `go depth N`
    and always derives depth from Skill Level, so SKILL is the only correct way
    to set an equal depth.
  * --time 0 (fixed depth) is speed-independent and matches "Thinking Time 0".
    --time >0 favours the FASTER engine (master, C++); use only for a
    deliberately time-limited comparison.
  * --opening-plies N asks the Rust Perfect DB referee for a shared opening
    prefix per two-game colour pair.  Each pair keeps only strict DB-best
    moves, randomises among tied choices, then plays the same prefix once with
    current as White and once with current as Black.  The actual match search
    still uses MTD(f) with Perfect DB disabled for both engines.

Examples:
  run_head_to_head.sh                       # current vs master, skill 10, 10 games/colour
  run_head_to_head.sh -s 14 -g 50           # skill 14, 50 games/colour
  run_head_to_head.sh --engine-threads 4    # send UCI Threads=4 to engines
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
        --engine-threads) ENGINE_THREADS="$2"; shift 2 ;;
        --engine-threads=*) ENGINE_THREADS="${1#*=}"; shift ;;
        -t|--time)      MOVETIME="$2"; shift 2 ;;
        --time=*)       MOVETIME="${1#*=}"; shift ;;
        --time-ms)      MOVETIME_MS="$2"; shift 2 ;;
        --time-ms=*)    MOVETIME_MS="${1#*=}"; shift ;;
        -p|--max-plies) MAX_PLIES="$2"; shift 2 ;;
        --max-plies=*)  MAX_PLIES="${1#*=}"; shift ;;
        -j|--jobs)      JOBS="$2"; shift 2 ;;
        --jobs=*)       JOBS="${1#*=}"; shift ;;
        --n-move-rule)  N_MOVE_RULE="$2"; shift 2 ;;
        --n-move-rule=*) N_MOVE_RULE="${1#*=}"; shift ;;
        --endgame-n-move-rule) ENDGAME_N_MOVE_RULE="$2"; shift 2 ;;
        --endgame-n-move-rule=*) ENDGAME_N_MOVE_RULE="${1#*=}"; shift ;;
        --opening-plies) OPENING_PLIES="$2"; shift 2 ;;
        --opening-plies=*) OPENING_PLIES="${1#*=}"; shift ;;
        --opening-seed) OPENING_SEED="$2"; shift 2 ;;
        --opening-seed=*) OPENING_SEED="${1#*=}"; shift ;;
        --opening-db)   OPENING_DB_PATH="$2"; shift 2 ;;
        --opening-db=*) OPENING_DB_PATH="${1#*=}"; shift ;;
        --self)         SELF="$2"; shift 2 ;;
        --self=*)       SELF="${1#*=}"; shift ;;
        --vs-perfect)   VS_PERFECT=1; shift ;;
        --perfect-db)   PERFECT_DB_PATH="$2"; shift 2 ;;
        --perfect-db=*) PERFECT_DB_PATH="${1#*=}"; shift ;;
        -m|--master)    MASTER_ENGINE="$2"; shift 2 ;;
        --master=*)     MASTER_ENGINE="${1#*=}"; shift ;;
        -c|--current)   CURRENT_OVERRIDE="$2"; shift 2 ;;
        --current=*)    CURRENT_OVERRIDE="${1#*=}"; shift ;;
        --current-args) CURRENT_ARGS="$2"; shift 2 ;;
        --current-args=*) CURRENT_ARGS="${1#*=}"; shift ;;
        --master-args)  MASTER_ARGS="$2"; shift 2 ;;
        --master-args=*) MASTER_ARGS="${1#*=}"; shift ;;
        --current-env)  CURRENT_ENV="$2"; shift 2 ;;
        --current-env=*) CURRENT_ENV="${1#*=}"; shift ;;
        --master-env)   MASTER_ENV="$2"; shift 2 ;;
        --master-env=*) MASTER_ENV="${1#*=}"; shift ;;
        --current-go)   CURRENT_GO="$2"; shift 2 ;;
        --current-go=*) CURRENT_GO="${1#*=}"; shift ;;
        --master-go)    MASTER_GO="$2"; shift 2 ;;
        --master-go=*)  MASTER_GO="${1#*=}"; shift ;;
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

find_make() {
    for cmd in make mingw32-make gmake; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "$cmd"
            return 0
        fi
    done
    return 1
}

master_repo_root_for() {
    local engine="$1"
    local dir
    dir="$(cd "$(dirname "$engine")" 2>/dev/null && pwd || true)"
    if [ -n "$dir" ] && [ -d "$dir/src" ]; then
        echo "$dir"
        return 0
    fi
    if [ -n "$dir" ] && [ -d "$dir/../src" ]; then
        (cd "$dir/.." && pwd)
        return 0
    fi
    if [ -d "$REPO_ROOT/../Sanmill-master/src" ]; then
        (cd "$REPO_ROOT/../Sanmill-master" && pwd)
        return 0
    fi
    return 1
}

build_current_engine() {
    echo ">> Building current engine (tgf, release) ..."
    ( cd "$REPO_ROOT" && cargo build --release -p tgf-cli )
}

build_master_with_gxx() {
    local root="$1"
    local out="$2"
    local src="$root/src"
    local cxx="${CXX:-g++}"
    local pthread_flag="-pthread"
    local exe_dir
    exe_dir="$(dirname "$out")"
    mkdir -p "$exe_dir"
    echo ">> Building master engine with $cxx fallback ..."
    if is_windows_shell; then
        pthread_flag=""
    fi
    (
        cd "$src"
        "$cxx" -std=c++17 -O3 -DNDEBUG -DIS_64BIT \
            -Wall -Wextra -Wshadow -fno-exceptions \
            -I../include -Iperfect -I. \
            *.cpp perfect/*.cpp $pthread_flag -o "$out"
    )
}

build_master_engine() {
    local engine="$1"
    local root make_cmd comp arch built
    root="$(master_repo_root_for "$engine")" || {
        echo "ERROR: cannot locate Sanmill-master source tree for: $engine" >&2
        echo "       Expected a sibling directory with src/Makefile." >&2
        exit 1
    }
    arch="${MASTER_ARCH:-x86-64-modern}"
    if is_windows_shell; then
        comp="${MASTER_COMP:-mingw}"
    else
        comp="${MASTER_COMP:-gcc}"
    fi
    if make_cmd="$(find_make)"; then
        echo ">> Building master engine via $make_cmd (ARCH=$arch COMP=$comp) ..."
        ( cd "$root/src" && "$make_cmd" -j"$JOBS" build ARCH="$arch" COMP="$comp" )
        built="$root/src/sanmill$(engine_suffix)"
        if [ ! -f "$built" ] && [ -f "$root/src/sanmill" ]; then
            built="$root/src/sanmill"
        fi
        if [ ! -f "$built" ]; then
            echo "ERROR: master build finished but executable was not found under $root/src" >&2
            exit 1
        fi
        mkdir -p "$(dirname "$engine")"
        cp -f "$built" "$engine"
        chmod +x "$engine" 2>/dev/null || true
    elif command -v g++ >/dev/null 2>&1; then
        build_master_with_gxx "$root" "$engine"
    else
        echo "ERROR: cannot build master engine: neither make nor g++ is available" >&2
        exit 1
    fi
}

CURRENT_ENGINE="${CURRENT_OVERRIDE:-$(default_current_engine)}"
if [ "$NEED_CURRENT" -eq 1 ]; then
    if [ -z "$CURRENT_OVERRIDE" ] || [ ! -f "$CURRENT_ENGINE" ]; then
        build_current_engine
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
        build_master_engine "$MASTER_ENGINE"
    fi
    if [ ! -f "$MASTER_ENGINE" ]; then
        echo "ERROR: master engine not found after build: $MASTER_ENGINE" >&2
        exit 1
    fi
fi

if [ -n "$MOVETIME_MS" ] && [ "$MOVETIME_MS" -gt 0 ] 2>/dev/null; then
    echo ">> Config: mode=$MODE  skill=$SKILL  engine_threads=$ENGINE_THREADS  games/colour=$GAMES  jobs=$JOBS  thinking_time=${MOVETIME_MS}ms  ply_cap=$MAX_PLIES  n_move=$N_MOVE_RULE  endgame_n_move=$ENDGAME_N_MOVE_RULE  opening_plies=$OPENING_PLIES"
else
    echo ">> Config: mode=$MODE  skill=$SKILL  engine_threads=$ENGINE_THREADS  games/colour=$GAMES  jobs=$JOBS  thinking_time=${MOVETIME}s  ply_cap=$MAX_PLIES  n_move=$N_MOVE_RULE  endgame_n_move=$ENDGAME_N_MOVE_RULE  opening_plies=$OPENING_PLIES"
fi
[ "$NEED_CURRENT" -eq 1 ] && echo "     current = $CURRENT_ENGINE"
[ "$NEED_MASTER" -eq 1 ] && echo "     master  = $MASTER_ENGINE"
[ -n "$CURRENT_ENV" ] && echo "     current_env = $CURRENT_ENV"
[ -n "$MASTER_ENV" ] && echo "     master_env = $MASTER_ENV"
if [ -n "$VS_PERFECT" ]; then
    echo "     vs_perfect = on"
    echo "     perfect_db = $PERFECT_DB_PATH"
fi
if [ "$OPENING_PLIES" -gt 0 ] 2>/dev/null; then
    echo "     opening_db = $OPENING_DB_PATH"
    echo "     opening_seed = $OPENING_SEED"
fi
if [ -n "$MOVETIME_MS" ] && [ "$MOVETIME_MS" -gt 0 ] 2>/dev/null; then
    echo "     (thinking_time>0: time-limited; Sanmill MoveTimeMs=${MOVETIME_MS}ms)"
elif [ "$MOVETIME" -gt 0 ] 2>/dev/null; then
    echo "     (thinking_time>0: time-limited; favours the faster engine, master)"
fi

cd "$REPO_ROOT"
H2H_CURRENT="$(winpath "$CURRENT_ENGINE")" \
H2H_CURRENT_ARGS="$CURRENT_ARGS" \
H2H_CURRENT_ENV="$CURRENT_ENV" \
H2H_MASTER="$(winpath "$MASTER_ENGINE")" \
H2H_MASTER_ARGS="$MASTER_ARGS" \
H2H_MASTER_ENV="$MASTER_ENV" \
H2H_MODE="$MODE" \
H2H_SKILL="$SKILL" \
H2H_ENGINE_THREADS="$ENGINE_THREADS" \
H2H_GAMES="$GAMES" \
H2H_JOBS="$JOBS" \
H2H_MOVETIME="$MOVETIME" \
H2H_MOVETIME_MS="${MOVETIME_MS:-}" \
H2H_MAX_PLIES="$MAX_PLIES" \
H2H_N_MOVE_RULE="$N_MOVE_RULE" \
H2H_ENDGAME_N_MOVE_RULE="$ENDGAME_N_MOVE_RULE" \
H2H_OPENING_PLIES="$OPENING_PLIES" \
H2H_OPENING_SEED="$OPENING_SEED" \
H2H_OPENING_DB_PATH="$(winpath "$OPENING_DB_PATH")" \
H2H_GO_CURRENT="$CURRENT_GO" \
H2H_GO_MASTER="$MASTER_GO" \
H2H_MASTER_USE_PERFECT_DB="${VS_PERFECT:+true}" \
H2H_MASTER_PERFECT_DB_PATH="$(winpath "$PERFECT_DB_PATH")" \
H2H_MASTER_PERFECT_DB_CACHE="$PERFECT_DB_CACHE" \
    cargo test -p tgf-cli --release --test head_to_head \
        head_to_head_vs_master -- --ignored --nocapture
