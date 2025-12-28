#!/bin/bash

# AI Thinking Hang Test - First Move Only
# Tests only the first 2 moves (human move 1, AI move 2)
# This is the most common scenario where AI hangs occur

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get device from command line argument
DEVICE=${1:-linux}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}AI First Move Hang Detection Test${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Test Focus:${NC} AI's first response (move 2)"
echo -e "${YELLOW}Games:${NC} 500 iterations"
echo -e "${YELLOW}Moves per game:${NC} Only 2 moves"
echo -e "${YELLOW}Expected time:${NC} ~5-10 minutes"
echo -e "${YELLOW}Platform:${NC} $DEVICE"
echo ""
echo -e "${GREEN}Starting test...${NC}"
echo ""

# Run the test
flutter test integration_test/ai_thinking_hang_first_move_test.dart -d "$DEVICE"

EXIT_CODE=$?

echo ""
echo -e "${BLUE}========================================${NC}"
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ Test completed${NC}"
else
    echo -e "${RED}✗ Test failed with exit code $EXIT_CODE${NC}"
fi
echo -e "${BLUE}========================================${NC}"

exit $EXIT_CODE


