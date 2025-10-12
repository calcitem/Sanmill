# Troubleshooting Guide

## Overview

This guide helps diagnose and fix common issues in the Sanmill C++ engine development. Issues are organized by category with symptoms, causes, and solutions.

## Table of Contents

- [Compilation Issues](#compilation-issues)
- [Runtime Errors](#runtime-errors)
- [Search Problems](#search-problems)
- [UCI Communication Issues](#uci-communication-issues)
- [Performance Issues](#performance-issues)
- [Testing Issues](#testing-issues)
- [Build System Issues](#build-system-issues)

---

## Compilation Issues

### Issue: "undefined reference to Position::do_move"

**Symptoms**:
```
/tmp/ccXXXXXX.o: In function `main':
main.cpp:(.text+0x123): undefined reference to `Position::do_move(int)'
collect2: error: ld returned 1 exit status
```

**Cause**: Object file not linked or not compiled

**Solution**:
```bash
# Rebuild position.o
cd src
make position.o

# Or rebuild everything
make clean
make all
```

---

### Issue: "Position.h: No such file or directory"

**Symptoms**:
```
fatal error: position.h: No such file or directory
 #include "position.h"
          ^
```

**Cause**: Wrong include path or working directory

**Solution**:
```bash
# Check current directory
pwd  # Should be in src/ or project root

# Fix include path
g++ -I/path/to/src ...

# Or in code
#include "../src/position.h"  // Adjust path as needed
```

---

### Issue: "conflicting declaration of 'Value'"

**Symptoms**:
```
error: conflicting declaration 'typedef int Value'
 typedef int Value;
             ^
```

**Cause**: Multiple definitions of same type

**Solution**:
1. Check for duplicate includes
2. Use include guards properly
3. Check for conflicting type definitions

```cpp
// In types.h
#ifndef TYPES_H_INCLUDED
#define TYPES_H_INCLUDED

using Value = int;  // Use 'using' instead of typedef

#endif
```

---

### Issue: "cannot convert Move to int"

**Symptoms**:
```
error: cannot convert 'Move' {aka 'enum Move'} to 'int' in assignment
```

**Cause**: Enum class used incorrectly

**Solution**:
```cpp
// BAD
int m = MOVE_NONE;

// GOOD
Move m = MOVE_NONE;

// If conversion needed
int m_int = static_cast<int>(move);
```

---

## Runtime Errors

### Issue: Segmentation Fault on do_move()

**Symptoms**:
```
Segmentation fault (core dumped)
```

**Cause**: Null pointer or out-of-bounds access

**Solution**:
```cpp
// Check position pointer
assert(pos != nullptr);

// Check square bounds
assert(sq >= SQ_A1 && sq < SQ_NB);

// Check move validity
if (pos->legal(move)) {
    pos->do_move(move);
} else {
    // Handle illegal move
}
```

**Debug**:
```bash
# Run with debugger
gdb ./sanmill
(gdb) run
# When it crashes:
(gdb) bt  # backtrace
(gdb) print pos
(gdb) print move
```

---

### Issue: Assertion Failed: "is_ok()"

**Symptoms**:
```
sanmill: position.cpp:123: void Position::do_move(Move): Assertion `is_ok()' failed.
Aborted (core dumped)
```

**Cause**: Position internal state corrupted

**Solution**:
1. Check recent move operations
2. Ensure all do_move() have matching undo_move()
3. Verify position initialization

```cpp
// Always pair do_move with undo_move
history.push(*pos);
pos->do_move(move);
// ... use position ...
pos->undo_move(history);  // DON'T FORGET THIS
```

---

### Issue: Infinite Loop in Search

**Symptoms**:
- Engine hangs
- 100% CPU usage
- Never returns bestmove

**Cause**: Missing terminal condition or timeout check

**Solution**:
```cpp
Value search(Position *pos, Depth depth, ...) {
    // Add terminal conditions
    if (depth <= 0) {
        return qsearch(pos, ...);  // Or evaluate
    }
    
    if (pos->get_phase() == Phase::gameOver) {
        return Evaluate::evaluate(pos);
    }
    
    // Add timeout check
    if (searchEngine.is_timeout(startTime)) {
        return VALUE_ZERO;  // or current best
    }
    
    // ... rest of search ...
}
```

---

### Issue: Search Returns MOVE_NONE

**Symptoms**:
- `getBestMove()` returns `MOVE_NONE`
- No error message

**Causes & Solutions**:

**1. No legal moves** (Game over):
```cpp
if (engine.getBestMove() == MOVE_NONE) {
    // Check if game over
    if (pos.get_phase() == Phase::gameOver) {
        // Game ended, no move to make
    }
}
```

**2. Search aborted early**:
```cpp
// Check if aborted
if (searchEngine.isAborted()) {
    // Search was interrupted
    // May not have found valid move yet
}
```

**3. Search depth too low**:
```cpp
// Increase depth
engine.set_depth(6);  // Try higher depth
```

---

## Search Problems

### Issue: Search Too Slow

**Symptoms**:
- Takes too long to return move
- Lower depth than expected

**Diagnostic**:
```cpp
// Add timing
auto start = now();
engine.runSearch();
auto elapsed = now() - start;
std::cout << "Search took: " << elapsed << "ms" << std::endl;
```

**Common Causes & Solutions**:

**1. Transposition table disabled**:
```cpp
// Enable TT
#define TRANSPOSITION_TABLE_ENABLE
```

**2. Poor move ordering**:
```cpp
// Check move ordering implementation
// Hash move should be searched first
```

**3. Deep search depth**:
```cpp
// Reduce depth temporarily
gameOptions.setDepth(6);  // Instead of 10+
```

**4. No iterative deepening**:
```cpp
// Enable IDS
gameOptions.setIDSEnabled(true);
```

---

### Issue: Evaluation Seems Wrong

**Symptoms**:
- Engine plays obviously bad moves
- Evaluation scores don't match position quality

**Diagnostic**:
```cpp
// Print evaluation details
std::cout << "Material: " << materialScore(pos) << std::endl;
std::cout << "Mobility: " << mobilityScore(pos) << std::endl;
std::cout << "Total: " << Evaluate::evaluate(pos) << std::endl;
```

**Common Causes**:

**1. Sign error**:
```cpp
// BAD: Forgot to flip for side to move
Value evaluate(Position *pos) {
    Value score = materialScore(pos) + mobilityScore(pos);
    return score;  // WRONG!
}

// GOOD
Value evaluate(Position *pos) {
    Value score = materialScore(pos) + mobilityScore(pos);
    return pos->side_to_move() == WHITE ? score : -score;
}
```

**2. Symmetric evaluation bug**:
```cpp
// Must be symmetric
Value score_white = evaluate_for_white(pos);
Value score_black = evaluate_for_black(pos);
assert(score_white == -score_black);  // Should hold
```

---

### Issue: Search Finds Illegal Move

**Symptoms**:
- `getBestMove()` returns move that fails `legal()` check
- Move cannot be applied to position

**Causes & Solutions**:

**1. Position changed between search and retrieval**:
```cpp
// BAD
engine.setRootPosition(&pos);
engine.runSearch();
pos.do_move(someMove);  // Position changed!
Move best = engine.getBestMove();  // May be illegal now

// GOOD
engine.setRootPosition(&pos);
engine.runSearch();
Move best = engine.getBestMove();  // Get move first
if (pos.legal(best)) {
    pos.do_move(best);  // Then modify position
}
```

**2. Bug in move generation**:
```cpp
// Verify move generation
std::vector<Move> moves = generate_legal_moves(pos);
for (Move m : moves) {
    assert(pos.legal(m));  // All generated moves should be legal
}
```

---

## UCI Communication Issues

### Issue: GUI Doesn't Recognize Engine

**Symptoms**:
- GUI shows "Engine not responding"
- No communication

**Solution**:
```bash
# Test engine manually
./sanmill
uci
# Should output:
# id name Sanmill
# id author ...
# uciok
```

**If no output**:
1. Check stdout not buffered
2. Verify UCI::loop() is called
3. Check for crashes during init

---

### Issue: "bestmove" Not Sent

**Symptoms**:
- Engine searches but never sends `bestmove`
- GUI waits forever

**Causes & Solutions**:

**1. Forgot to send bestmove**:
```cpp
// In search completion
sync_cout << "bestmove " << UCI::move(bestMove) << sync_endl;
```

**2. Search aborted without output**:
```cpp
// Always send bestmove, even if aborted
if (searchAborted) {
    sync_cout << "bestmove " << UCI::move(bestMoveSoFar) << sync_endl;
}
```

---

### Issue: Invalid FEN Accepted

**Symptoms**:
- Engine doesn't reject invalid FEN
- Position becomes corrupted

**Solution**:
```cpp
bool Position::set(const std::string &fen) {
    // Validate FEN format
    if (!validateFEN(fen)) {
        return false;  // Reject invalid FEN
    }
    
    // Parse and set position
    // ...
    
    // Verify resulting position is valid
    assert(is_ok());
    return true;
}
```

---

## Performance Issues

### Issue: Nodes Per Second Too Low

**Expected**: 50K-500K nodes/sec  
**Actual**: <10K nodes/sec

**Diagnostic**:
```cpp
// Add node counter
uint64_t nodes = 0;

Value search(...) {
    nodes++;
    // ... search code ...
}

// After search
std::cout << "Nodes searched: " << nodes << std::endl;
std::cout << "Time: " << time_ms << "ms" << std::endl;
std::cout << "NPS: " << (nodes * 1000 / time_ms) << std::endl;
```

**Common Causes**:

**1. Debug build**:
```bash
# Use release build
make clean
make CXXFLAGS="-O3 -DNDEBUG" all
```

**2. Expensive evaluation**:
```cpp
// Profile evaluation
#ifdef TIME_STAT
auto start = now();
Value eval = Evaluate::evaluate(pos);
auto elapsed = now() - start;
if (elapsed > 1) {  // More than 1ms is too slow
    debugPrintf("Slow evaluation: %dms\n", elapsed);
}
#endif
```

**3. Memory allocation in hot path**:
```cpp
// BAD: Allocates every call
Value search(...) {
    std::vector<Move> moves;  // Dynamic allocation!
    // ...
}

// GOOD: Stack allocation
Value search(...) {
    Move moves[MAX_MOVES];
    int count = generate_moves(pos, moves);
    // ...
}
```

---

### Issue: Memory Leak

**Symptoms**:
- Memory usage grows over time
- Eventual crash (out of memory)

**Detection**:
```bash
# Run with Valgrind
valgrind --leak-check=full ./sanmill

# Look for:
# "definitely lost: X bytes in Y blocks"
```

**Common Causes**:

**1. Forgetting to pop from stack**:
```cpp
// BAD
for (Move m : moves) {
    history.push(*pos);
    pos->do_move(m);
    search(pos, ...);
    // Forgot to pop!
}

// GOOD
for (Move m : moves) {
    history.push(*pos);
    pos->do_move(m);
    search(pos, ...);
    pos->undo_move(history);  // Pop here
}
```

**2. New without delete**:
```cpp
// BAD
Position *pos = new Position();
// ... use pos ...
// Never deleted!

// GOOD: Use stack allocation
Position pos;
// Automatically destroyed

// Or use smart pointers
std::unique_ptr<Position> pos = std::make_unique<Position>();
```

---

## Testing Issues

### Issue: Test Fails with "Assertion Failed"

**Symptoms**:
```
test_position.cpp:45: Failure
Expected: (move), actual: MOVE_NONE
```

**Solution**:
```cpp
// Add more diagnostic output
TEST(PositionTest, MoveGeneration) {
    Position pos;
    pos.set("test_fen");
    
    Move move = generate_move(pos);
    
    if (move == MOVE_NONE) {
        // Print diagnostic info
        std::cout << "Position: " << pos.fen() << std::endl;
        std::cout << "Phase: " << (int)pos.get_phase() << std::endl;
        std::cout << "Legal moves: " << count_legal_moves(pos) << std::endl;
    }
    
    EXPECT_NE(move, MOVE_NONE);
}
```

---

### Issue: Tests Pass Individually But Fail Together

**Symptoms**:
- Running single test: PASS
- Running all tests: FAIL

**Cause**: Tests have dependencies or shared state

**Solution**:
```cpp
// Ensure tests are independent
TEST(SearchTest, Test1) {
    // Reset global state
    Search::clear();
    TranspositionTable::clear();
    
    // ... test code ...
}

TEST(SearchTest, Test2) {
    // Reset global state again
    Search::clear();
    TranspositionTable::clear();
    
    // ... test code ...
}
```

---

## Build System Issues

### Issue: "make: *** No rule to make target"

**Symptoms**:
```
make: *** No rule to make target `new_file.o', needed by `sanmill'.  Stop.
```

**Solution**:
```bash
# Update Makefile to include new file
# In Makefile, add to OBJS:
OBJS = position.o search.o ... new_file.o

# Or regenerate dependencies
make depend
```

---

### Issue: Changes Not Reflected After Rebuild

**Symptoms**:
- Modified code
- Ran `make`
- No change in behavior

**Cause**: Object files not rebuilt

**Solution**:
```bash
# Force rebuild
make clean
make all

# Or touch source file
touch src/position.cpp
make
```

---

### Issue: Link Error with Undefined Symbol

**Symptoms**:
```
undefined reference to `vtable for Position'
```

**Cause**: Virtual function declared but not defined

**Solution**:
```cpp
// If you have virtual functions, define them
class Position {
    virtual Value evaluate();  // Declaration
};

// Must provide definition
Value Position::evaluate() {
    // Implementation
}
```

---

## Getting Help

### Information to Provide

When reporting issues, include:

1. **Version**: `git rev-parse HEAD`
2. **Platform**: OS, compiler version
3. **Build flags**: Output of `make -n`
4. **Full error**: Complete error message
5. **Minimal reproduction**: Smallest code that shows issue
6. **Steps taken**: What you've tried

### Debugging Checklist

Before asking for help:

- [ ] Read relevant documentation
- [ ] Check this troubleshooting guide
- [ ] Search existing issues on GitHub
- [ ] Try with debug build
- [ ] Run under debugger
- [ ] Create minimal test case
- [ ] Check git history for related changes

### Useful Commands

```bash
# Check build environment
gcc --version
g++ --version
make --version

# Clean build
make clean && make all

# Verbose build
make VERBOSE=1

# Debug build
make debug

# Run tests
make test

# Memory check
valgrind --leak-check=full ./sanmill

# Performance profile
perf record ./sanmill
perf report
```

---

## Quick Fixes

### Reset Everything

```bash
cd src
make clean
rm -f *.o sanmill
make all
./sanmill
```

### Verify Installation

```bash
# Check files exist
ls -la src/*.cpp src/*.h

# Check build system
cd src
make clean
make all
./sanmill
uci
quit
```

### Test UCI Communication

```bash
echo "uci" | ./sanmill
echo "isready" | ./sanmill
echo -e "uci\nisready\nposition startpos\ngo depth 3\nquit" | ./sanmill
```

---

## See Also

- [C++ Architecture](CPP_ARCHITECTURE.md) - System overview
- [API Documentation](api/) - Detailed API reference
- [Workflows](CPP_WORKFLOWS.md) - Development workflows
- [UCI Protocol](UCI_PROTOCOL.md) - Communication protocol

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3

