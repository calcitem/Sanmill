#!/usr/bin/env bash
#
# Fixed-depth strength match: HEAD engine vs parent (default HEAD^).
#
# Uses Skill 10 and MoveTime 0 (pure depth-limited search, no per-move clock).
# This isolates chess strength from the "faster engine searches deeper in 1s"
# effect that time-limited matches introduce.  Skill 10 keeps each move tractable
# when Thinking Time is unlimited.
#
# Delegates engine builds and the parent worktree to run_h2h_head_vs_parent.sh.
# Override any value through the matching environment variable, for example:
#   GAMES=200 JOBS=8 scripts/run_h2h_head_vs_parent_skill10_depth0.sh
#   PARENT_REV=607907cb9 GAMES=500 scripts/run_h2h_head_vs_parent_skill10_depth0.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export SKILL="${SKILL:-10}"
export MOVETIME="${MOVETIME:-0}"
export GAMES="${GAMES:-10000}"
export JOBS="${JOBS:-16}"
export MAX_PLIES="${MAX_PLIES:-160}"
export N_MOVE_RULE="${N_MOVE_RULE:-20}"
export ENDGAME_N_MOVE_RULE="${ENDGAME_N_MOVE_RULE:-20}"
export OPENING_PLIES="${OPENING_PLIES:-4}"

exec bash "$SCRIPT_DIR/run_h2h_head_vs_parent.sh"
