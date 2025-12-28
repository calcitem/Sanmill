#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

# AI Thinking Hang Test Runner Script
# Runs the AI thinking hang detection test on specified platform

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}AI Thinking Hang Detection Test Runner${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

# Check if device parameter is provided
DEVICE=${1:-linux}

echo -e "${YELLOW}Device: $DEVICE${NC}"
echo ""

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}Error: Flutter is not installed or not in PATH${NC}"
    exit 1
fi

# Navigate to the flutter app directory
cd "$(dirname "$0")"

echo -e "${YELLOW}Running pub get...${NC}"
flutter pub get

echo ""
echo -e "${YELLOW}Starting AI hang detection test...${NC}"
echo -e "${YELLOW}This may take a while depending on the number of games configured.${NC}"
echo -e "${YELLOW}The test will stop immediately if a hang is detected.${NC}"
echo ""

# Run the test
flutter test integration_test/ai_thinking_hang_test.dart -d "$DEVICE"

TEST_RESULT=$?

echo ""
if [ $TEST_RESULT -eq 0 ]; then
    echo -e "${GREEN}✓ Test completed successfully - No hangs detected${NC}"
else
    echo -e "${RED}✗ Test failed - AI hang detected or test error occurred${NC}"
    echo -e "${YELLOW}Check the output above for detailed hang information${NC}"
fi

echo -e "${GREEN}==========================================${NC}"

exit $TEST_RESULT
