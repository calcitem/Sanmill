#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

# AI hang smoke test runner (native session path).

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DEVICE=${1:-linux}

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}AI Hang Smoke Test Runner${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e "${YELLOW}Device: $DEVICE${NC}"
echo ""

if ! command -v flutter &> /dev/null; then
    echo -e "${RED}Error: Flutter is not installed or not in PATH${NC}"
    exit 1
fi

cd "$(dirname "$0")"

TEST_FILE="integration_test/ai_hang_smoke_test.dart"
if [ ! -f "$TEST_FILE" ]; then
    echo -e "${RED}Error: $TEST_FILE not found${NC}"
    exit 1
fi

flutter pub get
flutter test "$TEST_FILE" -d "$DEVICE" --timeout 480s

exit $?
