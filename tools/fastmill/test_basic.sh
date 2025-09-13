#!/bin/bash

# Basic test script for Fastmill
# This script tests basic functionality with mock engines

echo "=== Fastmill Basic Test ==="

# Check if fastmill executable exists
if [ ! -f "./fastmill" ]; then
    echo "Error: fastmill executable not found. Please compile first with 'make'."
    exit 1
fi

echo "Testing fastmill help..."
./fastmill -help

echo ""
echo "Testing fastmill version..."
./fastmill -version

echo ""
echo "=== Test completed ==="
echo "To run a full tournament test, you need Mill engines that support UCI protocol."
echo ""
echo "Example usage:"
echo "./fastmill -engine cmd=sanmill name=Engine1 \\"
echo "           -engine cmd=sanmill name=Engine2 \\"
echo "           -each tc=10+0.1 \\"
echo "           -rounds 1 \\"
echo "           -concurrency 1"
