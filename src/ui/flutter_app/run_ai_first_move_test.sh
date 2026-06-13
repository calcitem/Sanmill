#!/bin/bash

# AI hang smoke test (alias for the first-move hang scenario on native path).

set -e

DEVICE=${1:-linux}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

exec "$SCRIPT_DIR/run_ai_hang_test.sh" "$DEVICE"
