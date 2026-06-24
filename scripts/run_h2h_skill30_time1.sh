#!/usr/bin/env bash
#
# Shortcut for a long current-vs-master strength match at high skill.
# Override any value through the matching environment variable, for example:
#   JOBS=8 GAMES=1000 scripts/run_h2h_skill30_time1.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

default_jobs() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    elif command -v getconf >/dev/null 2>&1; then
        getconf _NPROCESSORS_ONLN
    else
        echo 1
    fi
}

JOBS="${JOBS:-$(default_jobs)}"

exec bash "$SCRIPT_DIR/run_head_to_head.sh" \
    --games "${GAMES:-5000}" \
    --skill "${SKILL:-30}" \
    --time "${MOVETIME:-1}" \
    --max-plies "${MAX_PLIES:-120}" \
    --n-move-rule "${N_MOVE_RULE:-20}" \
    --endgame-n-move-rule "${ENDGAME_N_MOVE_RULE:-20}" \
    --opening-plies "${OPENING_PLIES:-4}" \
    --jobs "$JOBS"
