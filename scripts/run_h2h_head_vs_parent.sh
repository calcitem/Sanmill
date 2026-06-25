#!/usr/bin/env bash
#
# Strength match: working-tree HEAD engine vs parent commit (default HEAD^).
# Both engines are Sanmill binaries so MoveTimeMs (milliseconds) is used
# instead of the legacy seconds-only MoveTime.  Default: 200 ms / move.
#
# Override examples:
#   GAMES=100 scripts/run_h2h_head_vs_parent.sh
#   PARENT_REV=607907cb9 JOBS=12 scripts/run_h2h_head_vs_parent.sh
#   SKILL=30 MOVETIME_MS=500 PARENT_REV=HEAD^ GAMES=1000 JOBS=20 \
#     scripts/run_h2h_head_vs_parent.sh
#   H2H_CURRENT_ENV=TGF_ENABLE_TT_MOVE=0 \
#     SKILL=30 MOVETIME_MS=200 PARENT_REV=HEAD^ GAMES=1000 JOBS=20 \
#     scripts/run_h2h_head_vs_parent.sh  # disable HEAD TT move for A/B
#
# Legacy MOVETIME (whole seconds) is still accepted but MOVETIME_MS takes
# priority when set.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PARENT_REV="${PARENT_REV:-HEAD^}"
JOBS="${JOBS:-16}"
WORKTREE="${H2H_PARENT_WORKTREE:-$REPO_ROOT/target/h2h-parent-worktree}"

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

current_engine_path() {
    echo "$REPO_ROOT/target/release/tgf$(engine_suffix)"
}

parent_engine_path() {
    echo "$WORKTREE/target/release/tgf$(engine_suffix)"
}

ensure_parent_rev() {
    if ! git -C "$REPO_ROOT" rev-parse --verify "${PARENT_REV}^{commit}" >/dev/null 2>&1; then
        echo "ERROR: parent revision not found: $PARENT_REV" >&2
        exit 1
    fi
}

worktree_is_git_checkout() {
    git -C "$WORKTREE" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

sync_parent_worktree() {
    local parent_sha
    parent_sha="$(git -C "$REPO_ROOT" rev-parse "${PARENT_REV}^{commit}")"
    if worktree_is_git_checkout; then
        local checked_out
        checked_out="$(git -C "$WORKTREE" rev-parse HEAD)"
        if [ "$checked_out" != "$parent_sha" ]; then
            echo ">> Updating parent worktree to ${PARENT_REV} (${parent_sha:0:12}) ..."
            git -C "$WORKTREE" checkout --detach "$parent_sha" >/dev/null
        fi
    elif [ -e "$WORKTREE" ]; then
        echo "ERROR: $WORKTREE exists but is not a git worktree." >&2
        echo "       Remove the directory or run:" >&2
        echo "         git -C \"$REPO_ROOT\" worktree remove --force \"$WORKTREE\"" >&2
        exit 1
    else
        echo ">> Creating parent worktree at $WORKTREE (${parent_sha:0:12}) ..."
        mkdir -p "$(dirname "$WORKTREE")"
        git -C "$REPO_ROOT" worktree add --detach "$WORKTREE" "$parent_sha" >/dev/null
    fi
}

build_head_engine() {
    echo ">> Building HEAD engine (tgf, release) ..."
    ( cd "$REPO_ROOT" && cargo build --release -p tgf-cli )
}

build_parent_engine() {
    echo ">> Building parent engine (tgf, release) ..."
    ( cd "$WORKTREE" && cargo build --release -p tgf-cli )
}

ensure_parent_rev

HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
PARENT_SHA="$(git -C "$REPO_ROOT" rev-parse --short "${PARENT_REV}^{commit}")"
HEAD_SUBJECT="$(git -C "$REPO_ROOT" log -1 --format=%s HEAD)"
PARENT_SUBJECT="$(git -C "$REPO_ROOT" log -1 --format=%s "${PARENT_REV}^{commit}")"

sync_parent_worktree
build_head_engine
build_parent_engine

CURRENT_ENGINE="$(current_engine_path)"
PARENT_ENGINE="$(parent_engine_path)"

if [ ! -f "$CURRENT_ENGINE" ]; then
    echo "ERROR: HEAD engine not found: $CURRENT_ENGINE" >&2
    exit 1
fi
if [ ! -f "$PARENT_ENGINE" ]; then
    echo "ERROR: parent engine not found: $PARENT_ENGINE" >&2
    exit 1
fi

echo ">> PK: HEAD ${HEAD_SHA} (${HEAD_SUBJECT})"
echo ">>  vs parent ${PARENT_SHA} (${PARENT_SUBJECT})"
echo ">>  current = $CURRENT_ENGINE"
echo ">>  parent  = $PARENT_ENGINE"

export CURRENT_ENGINE
export MASTER_ENGINE="$PARENT_ENGINE"
export CURRENT_ARGS="${CURRENT_ARGS:-uci}"
export MASTER_ARGS="${MASTER_ARGS:-uci}"
export CURRENT_GO="${CURRENT_GO:-go depth 0}"
export MASTER_GO="${MASTER_GO:-go depth 0}"

# Resolve the effective per-move time. MOVETIME_MS (milliseconds) takes
# priority; fall back to legacy MOVETIME * 1000; default 200 ms.
if [ -n "${MOVETIME_MS:-}" ]; then
    _TIME_MS="$MOVETIME_MS"
elif [ -n "${MOVETIME:-}" ] && [ "${MOVETIME:-0}" -gt 0 ] 2>/dev/null; then
    _TIME_MS=$(( MOVETIME * 1000 ))
else
    _TIME_MS=200
fi

exec bash "$SCRIPT_DIR/run_head_to_head.sh" \
    --games "${GAMES:-5000}" \
    --skill "${SKILL:-30}" \
    --time-ms "$_TIME_MS" \
    --max-plies "${MAX_PLIES:-120}" \
    --n-move-rule "${N_MOVE_RULE:-20}" \
    --endgame-n-move-rule "${ENDGAME_N_MOVE_RULE:-20}" \
    --opening-plies "${OPENING_PLIES:-4}" \
    --jobs "$JOBS"
