#!/bin/bash

# smart-monkey.sh
#
# Run the smart monkey integration test suite for the Sanmill Flutter app.
#
# Unlike the traditional adb monkey test (monkey.sh) which generates
# completely random touch events, this script runs a Flutter integration
# test that understands the game's state machine. It exercises all game
# phases including:
#
#   - Placing phase: pieces are placed on empty board positions
#   - Moving phase: pieces are selected and moved to adjacent squares
#     (the key scenario that random monkey testing cannot reach)
#   - Removing phase: opponent pieces are removed after forming mills
#   - Game over: result dialogs are dismissed and new games are started
#
# Usage:
#   ./tests/monkey/smart-monkey.sh              # Run on default (Linux)
#   ./tests/monkey/smart-monkey.sh android      # Run on Android device
#   ./tests/monkey/smart-monkey.sh linux         # Run on Linux desktop
#
# Prerequisites:
#   - Flutter SDK installed and in PATH
#   - For Android: a connected device or running emulator
#   - Run ./flutter-init.sh first if dependencies are not installed

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FLUTTER_APP_DIR="$REPO_ROOT/src/ui/flutter_app"

# Default device is Linux desktop.
DEVICE="${1:-linux}"

echo "============================================="
echo "  Sanmill Smart Monkey Test"
echo "============================================="
echo "Device: $DEVICE"
echo "App dir: $FLUTTER_APP_DIR"
echo ""

cd "$FLUTTER_APP_DIR"

echo "Running smart monkey integration test..."
echo ""

flutter test \
    integration_test/monkey/smart_monkey_test.dart \
    -d "$DEVICE" \
    --timeout 600

echo ""
echo "============================================="
echo "  Smart Monkey Test Complete"
echo "============================================="
