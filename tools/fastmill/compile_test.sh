#!/bin/bash

# Simple compilation test for individual files
# This helps identify specific compilation issues

echo "=== Fastmill Compilation Test ==="

# Test individual file compilation
echo "Testing main.cpp compilation..."
g++ -O3 -std=c++17 -Wall -Wextra -DNDEBUG -DMILL_GAME -march=native \
    -Isrc -I../../src -I../../include -c src/main.cpp -o test_main.o

if [ $? -eq 0 ]; then
    echo "✓ main.cpp compiled successfully"
    rm -f test_main.o
else
    echo "✗ main.cpp compilation failed"
    exit 1
fi

echo "Testing logger compilation..."
g++ -O3 -std=c++17 -Wall -Wextra -DNDEBUG -DMILL_GAME -march=native \
    -Isrc -I../../src -I../../include -c src/utils/logger.cpp -o test_logger.o

if [ $? -eq 0 ]; then
    echo "✓ logger.cpp compiled successfully"
    rm -f test_logger.o
else
    echo "✗ logger.cpp compilation failed"
    exit 1
fi

echo "Testing CLI parser compilation..."
g++ -O3 -std=c++17 -Wall -Wextra -DNDEBUG -DMILL_GAME -march=native \
    -Isrc -I../../src -I../../include -c src/cli/cli_parser.cpp -o test_cli.o

if [ $? -eq 0 ]; then
    echo "✓ cli_parser.cpp compiled successfully"
    rm -f test_cli.o
else
    echo "✗ cli_parser.cpp compilation failed"
    exit 1
fi

echo "Testing ELO calculator compilation..."
g++ -O3 -std=c++17 -Wall -Wextra -DNDEBUG -DMILL_GAME -march=native \
    -Isrc -I../../src -I../../include -c src/stats/elo_calculator.cpp -o test_elo.o

if [ $? -eq 0 ]; then
    echo "✓ elo_calculator.cpp compiled successfully"
    rm -f test_elo.o
else
    echo "✗ elo_calculator.cpp compilation failed"
    exit 1
fi

echo ""
echo "=== Basic compilation tests passed! ==="
echo "Now you can try: make"
