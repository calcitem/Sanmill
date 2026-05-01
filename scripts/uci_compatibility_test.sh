#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
#
# uci_compatibility_test.sh
#
# Smoke-test the tgf-cli UCI interface against a reference command sequence.
#
# Usage:
#   ./scripts/uci_compatibility_test.sh [path/to/tgf-binary]
#
# Defaults to cargo run -p tgf-cli in release mode when no binary is given.
# All assertions are made against tgf-cli; comparison against the legacy
# sanmill binary is optional (pass it as $2 if available).

set -euo pipefail

TGF="${1:-}"
LEGACY="${2:-}"

# Build tgf-cli in release mode if no binary was provided.
if [[ -z "$TGF" ]]; then
  echo "Building tgf-cli (release)..."
  cargo build --release -p tgf-cli --quiet
  TGF="./target/release/tgf"
fi

run_uci() {
  local binary="$1"
  local input="$2"
  # Feed input to the binary and capture output (5-second timeout).
  echo -e "$input" | timeout 5 "$binary" uci 2>/dev/null || true
}

PASS=0
FAIL=0

check() {
  local desc="$1"
  local output="$2"
  local pattern="$3"
  if echo "$output" | grep -qE "$pattern"; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc (pattern: $pattern)"
    echo "        output: $(echo "$output" | head -5)"
    ((FAIL++))
  fi
}

echo ""
echo "=== tgf-cli UCI smoke tests ==="

# ---- Test 1: uci response ----
OUT=$(run_uci "$TGF" "uci\nquit")
check "uci → id name"    "$OUT" "^id name "
check "uci → id author"  "$OUT" "^id author "
check "uci → uciok"      "$OUT" "^uciok$"

# ---- Test 2: isready ----
OUT=$(run_uci "$TGF" "uci\nisready\nquit")
check "isready → readyok" "$OUT" "^readyok$"

# ---- Test 3: option declarations ----
OUT=$(run_uci "$TGF" "uci\nquit")
check "option Threads"       "$OUT" "option name Threads"
check "option Hash"          "$OUT" "option name Hash"
check "option MaxQuiescence" "$OUT" "option name MaxQuiescenceDepth"
check "option PieceCount"    "$OUT" "option name PieceCount"
check "option MayFly"        "$OUT" "option name MayFly"

# ---- Test 4: position start + go depth 1 → bestmove ----
OUT=$(run_uci "$TGF" "uci\nisready\nposition startpos\ngo depth 1\nstop\nquit")
check "go depth 1 → bestmove" "$OUT" "^bestmove [a-z][0-9]"

# ---- Test 5: setoption PieceCount ----
OUT=$(run_uci "$TGF" "uci\nsetoption name PieceCount value 12\nisready\nquit")
check "setoption PieceCount → readyok" "$OUT" "^readyok$"

# ---- Test 6: ucinewgame ----
OUT=$(run_uci "$TGF" "uci\nucinewgame\nisready\nquit")
check "ucinewgame → readyok" "$OUT" "^readyok$"

# ---- Test 7: position with moves ----
OUT=$(run_uci "$TGF" "uci\nisready\nposition startpos moves d7\ngo depth 1\nstop\nquit")
check "position moves → bestmove" "$OUT" "^bestmove "

# ---- Test 8: infinite + stop ----
OUT=$(run_uci "$TGF" "uci\nisready\nposition startpos\ngo infinite\nstop\nquit")
check "go infinite + stop → bestmove" "$OUT" "^bestmove "

# ---- Test 9: d (debug print) ----
OUT=$(run_uci "$TGF" "uci\nisready\nposition startpos\nd\nquit")
check "d command → board output" "$OUT" "side: white"

# ---- Optional legacy comparison ----
if [[ -n "$LEGACY" && -x "$LEGACY" ]]; then
  echo ""
  echo "=== Legacy sanmill comparison ==="
  LEG_OUT=$(run_uci "$LEGACY" "uci\nisready\nposition startpos\ngo depth 1\nstop\nquit")
  TGF_MOVE=$(echo "$OUT" | grep "^bestmove" | head -1 | awk '{print $2}')
  LEG_MOVE=$(echo "$LEG_OUT" | grep "^bestmove" | head -1 | awk '{print $2}')
  if [[ "$TGF_MOVE" == "$LEG_MOVE" ]]; then
    echo "  PASS: depth-1 bestmove agrees ($TGF_MOVE)"
    ((PASS++))
  else
    echo "  NOTE: depth-1 bestmove differs (tgf=$TGF_MOVE legacy=$LEG_MOVE) — expected in practice"
    # Not a failure: search ordering and TT differ.
  fi
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
