#!/usr/bin/env bash
#
# End-to-end Mill eval-weight tuning pipeline.
#
#   gen  -> label  -> fit  -> quantized weights artifact
#
# Usage:
#   bash scripts/tune_mill_eval.sh [OPTIONS]
#
# Required:
#   --db PATH     Perfect DB directory (e.g. D:/user/Documents/strong)
#
# Optional:
#   --positions N   Target quiet positions for gen (default: 50000)
#   --human-db PATH Use NMM_LLM human_db.sqlite as position source
#   --iters N       Texel fit iterations (default: 500)
#   --k SCALE       Initial sigmoid scaling K (default: 0.1)
#   --placing-weight W  Placing-phase sample weight (default: 0.2)
#   --seed HEX      RNG seed for gen (default: time-based)
#   --workdir PATH  Output directory (default: target/tune)
#   --resume        Resume from existing checkpoint / dataset
#   --no-gen        Skip gen stage (use existing positions file)
#   --no-label      Skip label stage (use existing labeled file)
#   --no-fit        Skip fit stage
#   --h2h           Run head-to-head match after fitting (optional, slow)
#   --jobs N        H2H parallel workers (default: 20)
#   --h2h-games N   H2H games per colour (default: 5000)
#
# Output (all under --workdir):
#   tune_positions.dat   - raw sampled positions
#   tune_labeled.dat     - positions with WDL labels
#   tune_fit.checkpoint  - fit optimizer state (supports --resume)
#   tune_weights.txt     - final TGF_EVAL_WEIGHTS artifact
#   tune_run.log         - full pipeline log
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Format integer seconds as "Xh Ym Zs" (or "Ym Zs" / "Zs" for short durations).
fmt_time() {
    local t=$1
    local h=$(( t / 3600 ))
    local m=$(( (t % 3600) / 60 ))
    local s=$(( t % 60 ))
    if   [ "$h" -gt 0 ]; then printf '%dh %02dm %02ds' "$h" "$m" "$s"
    elif [ "$m" -gt 0 ]; then printf '%dm %02ds' "$m" "$s"
    else printf '%ds' "$s"
    fi
}

PIPELINE_START=$SECONDS

# --------------------------------------------------------------------------
# Defaults
# --------------------------------------------------------------------------
DB_PATH=""
HUMAN_DB_PATH=""
POSITIONS="${POSITIONS:-50000}"
ITERS="${ITERS:-500}"
K_SCALE="${K_SCALE:-0.1}"
PLACING_WEIGHT="${PLACING_WEIGHT:-0.2}"
SEED="${SEED:-0}"
WORKDIR="${WORKDIR:-$REPO_ROOT/target/tune}"
RESUME=""
NO_GEN=""
NO_LABEL=""
NO_FIT=""
DO_H2H=""
H2H_JOBS="${H2H_JOBS:-20}"
H2H_GAMES="${H2H_GAMES:-5000}"

while [ $# -gt 0 ]; do
    case "$1" in
        --db)           DB_PATH="$2"; shift 2 ;;
        --db=*)         DB_PATH="${1#*=}"; shift ;;
        --positions)    POSITIONS="$2"; shift 2 ;;
        --positions=*)  POSITIONS="${1#*=}"; shift ;;
        --human-db)     HUMAN_DB_PATH="$2"; shift 2 ;;
        --human-db=*)   HUMAN_DB_PATH="${1#*=}"; shift ;;
        --iters)        ITERS="$2"; shift 2 ;;
        --iters=*)      ITERS="${1#*=}"; shift ;;
        --k)            K_SCALE="$2"; shift 2 ;;
        --k=*)          K_SCALE="${1#*=}"; shift ;;
        --placing-weight) PLACING_WEIGHT="$2"; shift 2 ;;
        --placing-weight=*) PLACING_WEIGHT="${1#*=}"; shift ;;
        --seed)         SEED="$2"; shift 2 ;;
        --seed=*)       SEED="${1#*=}"; shift ;;
        --workdir)      WORKDIR="$2"; shift 2 ;;
        --workdir=*)    WORKDIR="${1#*=}"; shift ;;
        --resume)       RESUME="--resume"; shift ;;
        --no-gen)       NO_GEN=1; shift ;;
        --no-label)     NO_LABEL=1; shift ;;
        --no-fit)       NO_FIT=1; shift ;;
        --h2h)          DO_H2H=1; shift ;;
        --jobs)         H2H_JOBS="$2"; shift 2 ;;
        --jobs=*)       H2H_JOBS="${1#*=}"; shift ;;
        --h2h-games)    H2H_GAMES="$2"; shift 2 ;;
        --h2h-games=*)  H2H_GAMES="${1#*=}"; shift ;;
        -h|--help) grep '^#' "$0" | sed 's/^# //; s/^#//' | head -40; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$DB_PATH" ] && [ -z "$NO_LABEL" ]; then
    echo "ERROR: --db PATH is required (or pass --no-label to skip labeling)" >&2
    exit 1
fi

mkdir -p "$WORKDIR"

POS_FILE="$WORKDIR/tune_positions.dat"
LABEL_FILE="$WORKDIR/tune_labeled.dat"
WEIGHTS_FILE="$WORKDIR/tune_weights.txt"
CHECKPOINT_FILE="$WORKDIR/tune_fit.checkpoint"
LOG_FILE="$WORKDIR/tune_run.log"

TGF="$REPO_ROOT/target/release/tgf"

# --------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------
echo ">> Building tgf release ..."
( cd "$REPO_ROOT" && cargo build --release -p tgf-cli )
echo ">> Built: $TGF"

# Helper: run a tgf subcommand and tee to log
run_tgf() {
    "$TGF" "$@" 2>&1 | tee -a "$LOG_FILE"
}

# --------------------------------------------------------------------------
# Banner
# --------------------------------------------------------------------------
{
    echo "========================================"
    echo "  Mill Eval Tuning Pipeline"
    echo "  $(date)"
    echo "  repo    = $REPO_ROOT"
    echo "  workdir = $WORKDIR"
    echo "  db      = ${DB_PATH:-<skipped>}"
    echo "  human_db= ${HUMAN_DB_PATH:-<none>}"
    echo "  positions=$POSITIONS  iters=$ITERS  k=$K_SCALE  placing_weight=$PLACING_WEIGHT  seed=$SEED"
    echo "========================================"
} | tee "$LOG_FILE"

# --------------------------------------------------------------------------
# Stage 1: gen
# --------------------------------------------------------------------------
if [ -z "$NO_GEN" ]; then
    echo "" | tee -a "$LOG_FILE"
    echo ">> [1/3] Generating positions ..." | tee -a "$LOG_FILE"
    _stage_t=$SECONDS
    if [ -n "$HUMAN_DB_PATH" ]; then
        run_tgf tune-gen-human \
            --db "$HUMAN_DB_PATH" \
            --positions "$POSITIONS" \
            --out "$POS_FILE"
    else
        run_tgf tune-gen \
            --positions "$POSITIONS" \
            --out "$POS_FILE" \
            --seed "$SEED" \
            ${RESUME:+--resume}
    fi
    echo ">> Stage 1 done in $(fmt_time $(( SECONDS - _stage_t ))): $POS_FILE" | tee -a "$LOG_FILE"
else
    echo ">> [1/3] Skipping gen (--no-gen)" | tee -a "$LOG_FILE"
    if [ ! -f "$POS_FILE" ]; then
        echo "ERROR: $POS_FILE does not exist; cannot skip gen" >&2; exit 1
    fi
fi

# --------------------------------------------------------------------------
# Stage 2: label
# --------------------------------------------------------------------------
if [ -z "$NO_LABEL" ]; then
    echo "" | tee -a "$LOG_FILE"
    echo ">> [2/3] Labeling with Perfect DB ..." | tee -a "$LOG_FILE"
    _stage_t=$SECONDS
    run_tgf tune-label \
        --db "$DB_PATH" \
        --in "$POS_FILE" \
        --out "$LABEL_FILE" \
        ${RESUME:+--resume}
    echo "" | tee -a "$LOG_FILE"
    echo ">> Label distribution by phase ..." | tee -a "$LOG_FILE"
    run_tgf tune-stats --in "$LABEL_FILE"
    echo ">> Stage 2 done in $(fmt_time $(( SECONDS - _stage_t ))): $LABEL_FILE" | tee -a "$LOG_FILE"
else
    echo ">> [2/3] Skipping label (--no-label)" | tee -a "$LOG_FILE"
    if [ ! -f "$LABEL_FILE" ]; then
        echo "ERROR: $LABEL_FILE does not exist; cannot skip label" >&2; exit 1
    fi
fi

# --------------------------------------------------------------------------
# Stage 3: fit
# --------------------------------------------------------------------------
if [ -z "$NO_FIT" ]; then
    echo "" | tee -a "$LOG_FILE"
    echo ">> [3/3] Fitting weights (Texel logistic regression) ..." | tee -a "$LOG_FILE"
    _stage_t=$SECONDS
    run_tgf tune-fit \
        --in "$LABEL_FILE" \
        --out "$WEIGHTS_FILE" \
        --iters "$ITERS" \
        --k "$K_SCALE" \
        --placing-weight "$PLACING_WEIGHT" \
        --checkpoint "$CHECKPOINT_FILE" \
        ${RESUME:+--resume}
    echo ">> Stage 3 done in $(fmt_time $(( SECONDS - _stage_t ))): $WEIGHTS_FILE" | tee -a "$LOG_FILE"
else
    echo ">> [3/3] Skipping fit (--no-fit)" | tee -a "$LOG_FILE"
fi

# --------------------------------------------------------------------------
# Print weights artifact
# --------------------------------------------------------------------------
echo "" | tee -a "$LOG_FILE"
echo "========================================"  | tee -a "$LOG_FILE"
echo "  RESULTS"  | tee -a "$LOG_FILE"
echo "========================================"  | tee -a "$LOG_FILE"
if [ -f "$WEIGHTS_FILE" ]; then
    cat "$WEIGHTS_FILE" | tee -a "$LOG_FILE"
    WEIGHTS_LINE="$(grep '^TGF_EVAL_WEIGHTS=' "$WEIGHTS_FILE" | head -1)"
    echo "" | tee -a "$LOG_FILE"
    echo "  Inject:  $WEIGHTS_LINE" | tee -a "$LOG_FILE"
    echo "  H2H verify:" | tee -a "$LOG_FILE"
    echo "    $WEIGHTS_LINE SKILL=30 MOVETIME_MS=200 \\" | tee -a "$LOG_FILE"
    echo "    GAMES=$H2H_GAMES JOBS=$H2H_JOBS bash scripts/run_h2h_head_vs_parent.sh" | tee -a "$LOG_FILE"
fi

# --------------------------------------------------------------------------
# Optional H2H
# --------------------------------------------------------------------------
if [ -n "$DO_H2H" ] && [ -f "$WEIGHTS_FILE" ]; then
    WEIGHTS_LINE="$(grep '^TGF_EVAL_WEIGHTS=' "$WEIGHTS_FILE" | head -1)"
    if [ -n "$WEIGHTS_LINE" ]; then
        echo "" | tee -a "$LOG_FILE"
        echo ">> Running H2H match (tuned vs HEAD^) ..." | tee -a "$LOG_FILE"
        H2H_CURRENT_ENV="$WEIGHTS_LINE" \
        SKILL=30 MOVETIME_MS=200 \
        PARENT_REV=HEAD GAMES="$H2H_GAMES" JOBS="$H2H_JOBS" \
        bash "$SCRIPT_DIR/run_h2h_head_vs_parent.sh" 2>&1 | tee -a "$LOG_FILE"
    fi
fi

echo "" | tee -a "$LOG_FILE"
echo ">> All done in $(fmt_time $(( SECONDS - PIPELINE_START ))).  Full log: $LOG_FILE" | tee -a "$LOG_FILE"
