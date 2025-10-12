# C++ Engine Development Workflows

## Overview

This document provides step-by-step workflows for common C++ engine development tasks. Each workflow includes prerequisite knowledge, detailed steps, validation methods, and common pitfalls.

**Target Audience**: AI agents and developers working on the C++ engine

## Table of Contents

- [Workflow 1: Add New Search Algorithm](#workflow-1-add-new-search-algorithm)
- [Workflow 2: Modify Evaluation Function](#workflow-2-modify-evaluation-function)
- [Workflow 3: Add UCI Command](#workflow-3-add-uci-command)
- [Workflow 4: Optimize Performance Bottleneck](#workflow-4-optimize-performance-bottleneck)
- [Workflow 5: Add Engine Option](#workflow-5-add-engine-option)
- [Workflow 6: Fix Search Bug](#workflow-6-fix-search-bug)
- [Workflow 7: Add Opening Book Moves](#workflow-7-add-opening-book-moves)
- [Workflow 8: Implement New Rule Variant](#workflow-8-implement-new-rule-variant)

---

## Workflow 1: Add New Search Algorithm

### Objective
Implement a new game tree search algorithm and integrate it with the engine.

### Prerequisites
- Understanding of minimax search
- Familiarity with Position and SearchEngine APIs
- Knowledge of Alpha-Beta pruning basics

### Steps

#### 1. Define Algorithm Interface

**File**: `src/search.h`

Add function declaration to Search namespace:

```cpp
namespace Search {
    // Existing algorithms...
    
    /// Your New Algorithm
    ///
    /// Brief description of what this algorithm does.
    ///
    /// @param searchEngine  Search engine instance
    /// @param pos           Current position
    /// @param ss            Position stack for undo
    /// @param depth         Search depth in plies
    /// @param originDepth   Original requested depth
    /// @param alpha         Lower bound
    /// @param beta          Upper bound
    /// @param bestMove      Output: best move found
    /// @return              Evaluation score
    Value your_new_algorithm(SearchEngine &searchEngine, Position *pos,
                             Sanmill::Stack<Position> &ss,
                             Depth depth, Depth originDepth,
                             Value alpha, Value beta, Move &bestMove);
}
```

#### 2. Implement Algorithm

**File**: `src/search.cpp`

```cpp
Value Search::your_new_algorithm(SearchEngine &searchEngine, Position *pos,
                                  Sanmill::Stack<Position> &ss,
                                  Depth depth, Depth originDepth,
                                  Value alpha, Value beta, Move &bestMove) {
    // Check terminal conditions
    if (depth <= 0 || pos->get_phase() == Phase::gameOver) {
        return Evaluate::evaluate(pos);
    }
    
    // Check timeout
    if (searchEngine.is_timeout(searchEngine.getSearchStartTime())) {
        return VALUE_ZERO;
    }
    
    // Generate moves
    std::vector<Move> moves = /* generate legal moves */;
    if (moves.empty()) {
        return Evaluate::evaluate(pos);
    }
    
    Value bestValue = -VALUE_INFINITE;
    
    // Search moves
    for (Move move : moves) {
        // Save position
        ss.push(*pos);
        
        // Make move
        pos->do_move(move);
        
        // Recursive search (your algorithm logic here)
        Value value = -your_new_algorithm(searchEngine, pos, ss,
                                          depth - 1, originDepth,
                                          -beta, -alpha, bestMove);
        
        // Undo move
        pos->undo_move(ss);
        
        // Update best
        if (value > bestValue) {
            bestValue = value;
            if (depth == originDepth) {
                bestMove = move;
            }
        }
        
        // Alpha-beta update (if applicable)
        if (value > alpha) {
            alpha = value;
        }
        if (alpha >= beta) {
            break;  // Beta cutoff
        }
    }
    
    return bestValue;
}
```

#### 3. Integrate with SearchEngine

**File**: `src/search_engine.cpp`

Modify `executeSearch()` to call your algorithm:

```cpp
int SearchEngine::executeSearch() {
    // ... existing code ...
    
    if (gameOptions.getAlgorithm() == 2 /* MTD(f) */) {
        value = Search::MTDF(*this, rootPos, ss, value, i, i, bestMove);
    } else if (gameOptions.getAlgorithm() == 3 /* MCTS */) {
        value = monte_carlo_tree_search(rootPos, bestMove);
    } else if (gameOptions.getAlgorithm() == 5 /* YOUR ALGORITHM */) {
        value = Search::your_new_algorithm(*this, rootPos, ss,
                                           i, i, alpha, beta, bestMove);
    } else {
        value = Search::search(*this, rootPos, ss, i, i, alpha, beta, bestMove);
    }
    
    // ... existing code ...
}
```

#### 4. Add Engine Option

**File**: `src/option.cpp`

```cpp
void Options::init() {
    // ... existing options ...
    
    // Add your algorithm to the Algorithm option range
    // Update max value from 4 to 5
}
```

#### 5. Add Unit Tests

**File**: `tests/test_search.cpp`

```cpp
#include "gtest/gtest.h"
#include "search.h"
#include "position.h"

TEST(SearchTest, YourNewAlgorithm) {
    Position pos;
    pos.set("********/********/********_w_0_0");
    pos.start();
    
    SearchEngine engine;
    Sanmill::Stack<Position> history;
    Move bestMove;
    
    Value value = Search::your_new_algorithm(engine, &pos, history,
                                              6, 6,
                                              -VALUE_INFINITE, VALUE_INFINITE,
                                              bestMove);
    
    EXPECT_NE(bestMove, MOVE_NONE);
    EXPECT_GE(value, -VALUE_INFINITE);
    EXPECT_LE(value, VALUE_INFINITE);
}

TEST(SearchTest, YourNewAlgorithmVsAlphaBeta) {
    Position pos;
    pos.set("complex_position_fen");
    
    // Your algorithm
    Move yourMove;
    Value yourValue = Search::your_new_algorithm(/*...*/, yourMove);
    
    // Alpha-Beta
    Move abMove;
    Value abValue = Search::search(/*...*/, abMove);
    
    // Results should be similar (not necessarily identical)
    EXPECT_NEAR(yourValue, abValue, 50);  // Within 0.5 pieces
}
```

#### 6. Build and Test

```bash
cd src
make clean
make all
./sanmill

# Test manually
position startpos
setoption name Algorithm value 5
go depth 6
# Verify bestmove output
```

#### 7. Benchmark Performance

```bash
make bench
# Compare performance with other algorithms
```

### Validation Checklist

- [ ] Algorithm compiles without errors
- [ ] Unit tests pass
- [ ] Returns valid move
- [ ] Handles timeout correctly
- [ ] Performance acceptable (within 2x of Alpha-Beta)
- [ ] Results reasonable (not significantly worse evaluation)

### Common Pitfalls

1. **Forgetting to save/restore position**: Always use Stack<Position>
2. **Infinite recursion**: Check depth and terminal conditions
3. **Not checking timeout**: Add timeout checks every ~1000 nodes
4. **Memory leaks**: Ensure all pushed positions are popped
5. **Wrong sign**: Remember to negate value in recursive calls

---

## Workflow 2: Modify Evaluation Function

### Objective
Improve position evaluation by adding or modifying evaluation terms.

### Prerequisites
- Understanding of Mill game strategy
- Knowledge of Position API
- Familiarity with evaluation concepts

### Steps

#### 1. Identify Evaluation Feature

Decide what to evaluate:
- Material (piece count)
- Mobility (legal moves count)
- Mill potential
- Piece placement quality
- Control of key squares

#### 2. Locate Evaluation Code

**File**: `src/evaluate.cpp`

```cpp
Value Evaluate::evaluate(const Position *pos) {
    Value value = VALUE_ZERO;
    
    // Material evaluation
    value += materialEvaluation(pos);
    
    // Mobility evaluation
    if (gameOptions.getConsiderMobility()) {
        value += mobilityEvaluation(pos);
    }
    
    // ADD YOUR FEATURE HERE
    value += yourNewFeature(pos);
    
    return pos->side_to_move() == WHITE ? value : -value;
}
```

#### 3. Implement Feature Function

```cpp
/// Evaluate your new feature
///
/// @param pos  Position to evaluate
/// @return     Evaluation contribution (positive = good for white)
static Value yourNewFeature(const Position *pos) {
    Value score = 0;
    
    // Example: Evaluate piece placement
    for (Square sq = SQ_A1; sq < SQ_NB; ++sq) {
        Piece piece = pos->piece_on(sq);
        
        if (piece == W_PIECE) {
            score += squareValue[sq];  // Add square value table
        } else if (piece == B_PIECE) {
            score -= squareValue[sq];
        }
    }
    
    return score;
}
```

#### 4. Add Configuration Option (Optional)

If feature should be configurable:

```cpp
// In option.h
bool getConsiderYourFeature() const { return considerYourFeature; }

// In evaluate.cpp
if (gameOptions.getConsiderYourFeature()) {
    value += yourNewFeature(pos);
}
```

#### 5. Test Evaluation

**File**: `tests/test_evaluate.cpp`

```cpp
TEST(EvaluateTest, YourNewFeature) {
    Position pos;
    
    // Test position where feature should be positive
    pos.set("position_with_good_feature");
    Value good = Evaluate::evaluate(&pos);
    
    // Test position where feature should be negative
    pos.set("position_with_bad_feature");
    Value bad = Evaluate::evaluate(&pos);
    
    EXPECT_GT(good, bad);
}
```

#### 6. Benchmark Impact

```bash
# Before changes
make bench
# Record results

# After changes
make bench
# Compare: should maintain or improve playing strength
```

### Validation Checklist

- [ ] Evaluation is symmetric (white/black)
- [ ] Doesn't slow down search significantly (<10% slowdown)
- [ ] Improves playing strength (test games)
- [ ] Handles edge cases (empty squares, game over)

### Common Pitfalls

1. **Asymmetric evaluation**: Must flip sign for black
2. **Performance**: Keep evaluation fast (called millions of times)
3. **Overfitting**: Test on diverse positions
4. **Integer overflow**: Be careful with large values

---

## Workflow 3: Add UCI Command

### Objective
Add a new UCI command for extended functionality.

### Prerequisites
- Understanding of UCI protocol
- Knowledge of command parsing
- Familiarity with EngineController

### Steps

#### 1. Define Command Syntax

Document in `src/docs/UCI_PROTOCOL.md`:

```markdown
### yournewcommand

**Purpose**: Brief description

**Syntax**:
```
yournewcommand [param1] [param2]
```

**Example**:
```
yournewcommand value1 value2
```
```

#### 2. Add Command Parser

**File**: `src/engine_commands.cpp`

```cpp
void handle_your_command(Position *pos, std::istringstream &is) {
    std::string param1, param2;
    
    // Parse parameters
    is >> param1 >> param2;
    
    // Validate parameters
    if (param1.empty()) {
        sync_cout << "error: missing parameter" << sync_endl;
        return;
    }
    
    // Execute command logic
    // ... your implementation ...
    
    // Send response (if needed)
    sync_cout << "response_data" << sync_endl;
}
```

#### 3. Integrate with Command Dispatcher

**File**: `src/engine_controller.cpp`

```cpp
void EngineController::handleCommand(const std::string &cmd, Position *pos) {
    std::istringstream is(cmd);
    std::string token;
    
    is >> std::skipws >> token;
    
    if (token == "uci") {
        // ... existing ...
    } else if (token == "yournewcommand") {
        handle_your_command(pos, is);
    }
    // ... other commands ...
}
```

#### 4. Add Tests

**File**: `tests/test_uci.cpp`

```cpp
TEST(UCITest, YourNewCommand) {
    Position pos;
    EngineController controller;
    
    // Test valid command
    controller.handleCommand("yournewcommand param1 param2", &pos);
    // Verify expected behavior
    
    // Test invalid command
    controller.handleCommand("yournewcommand", &pos);
    // Should handle gracefully
}
```

#### 5. Test Manually

```bash
./sanmill
yournewcommand param1 param2
# Verify output
quit
```

### Validation Checklist

- [ ] Command syntax documented
- [ ] Parser handles all parameter combinations
- [ ] Error handling for invalid input
- [ ] Doesn't block engine operation
- [ ] Thread-safe (if applicable)

---

## Workflow 4: Optimize Performance Bottleneck

### Objective
Identify and optimize a performance bottleneck in the engine.

### Prerequisites
- Profiling tools (gprof, perf, Valgrind)
- Understanding of hot paths
- Knowledge of optimization techniques

### Steps

#### 1. Profile Current Performance

```bash
# Linux
cd src
make profile
./sanmill < benchmark.txt
gprof sanmill gmon.out > profile.txt

# Windows
# Use Visual Studio Profiler
```

#### 2. Identify Bottleneck

Look for functions consuming most CPU time:

```
%   cumulative   self              self     total
time   seconds   seconds    calls  ms/call  ms/call  name
40.23     0.521     0.521  1234567    0.000    0.001  Position::do_move()
15.67     0.724     0.203   876543    0.000    0.002  MoveGen::generate()
10.23     0.856     0.132  2345678    0.000    0.000  Evaluate::evaluate()
```

#### 3. Analyze Hotspot

**Questions**:
- Why is this function called so often?
- Can calls be reduced?
- Can function be optimized?
- Can result be cached?

#### 4. Apply Optimization

**Example**: Optimize `do_move()` with inline bitboard operations

**Before**:
```cpp
void Position::do_move(Move m) {
    Square from = from_sq(m);
    Square to = to_sq(m);
    
    Piece piece = piece_on(from);
    remove_piece(from);
    put_piece(to, piece);
    
    update_key();
}
```

**After**:
```cpp
inline void Position::do_move(Move m) {
    Square from = from_sq(m);
    Square to = to_sq(m);
    
    // Inline bitboard operations
    Bitboard from_bb = sq_bb(from);
    Bitboard to_bb = sq_bb(to);
    
    byColorBB[sideToMove] ^= (from_bb | to_bb);
    
    // Incremental key update (faster)
    st->key ^= zobrist[from][sideToMove];
    st->key ^= zobrist[to][sideToMove];
}
```

#### 5. Measure Impact

```bash
make bench
# Compare before/after:
# - Nodes per second
# - Total time
# - Search depth achieved
```

#### 6. Verify Correctness

```bash
make test
# Ensure all tests still pass

# Run perft test
position startpos
perft 6
# Verify node count matches known value
```

### Validation Checklist

- [ ] Performance improved (>5% speedup)
- [ ] All tests pass
- [ ] No correctness regressions
- [ ] No new memory leaks (Valgrind)

### Common Pitfalls

1. **Premature optimization**: Profile first!
2. **Breaking correctness**: Always test after optimization
3. **Compiler already did it**: Check assembly output
4. **Cache effects**: Benchmark with realistic data

---

## Workflow 5: Add Engine Option

### Objective
Add a new configurable option for engine behavior.

### Prerequisites
- Understanding of option system
- Knowledge of UCI protocol
- Familiarity with GameOptions class

### Steps

#### 1. Add Option Field

**File**: `src/option.h`

```cpp
class GameOptions {
private:
    // ... existing fields ...
    bool yourNewOption;
    
public:
    // Getter
    bool getYourNewOption() const { return yourNewOption; }
    
    // Setter
    void setYourNewOption(bool value) { yourNewOption = value; }
};
```

#### 2. Initialize Default Value

**File**: `src/option.cpp`

```cpp
GameOptions::GameOptions() {
    // ... existing initialization ...
    yourNewOption = true;  // Default value
}
```

#### 3. Register UCI Option

**File**: `src/uci.cpp`

```cpp
void UCI::init_options() {
    Options["YourNewOption"] << 
        Option(true,  // default
               on_your_option);  // callback
}

// Callback function
void on_your_option(const Option &o) {
    gameOptions.setYourNewOption(o);
}
```

#### 4. Use Option in Code

**File**: Various files

```cpp
if (gameOptions.getYourNewOption()) {
    // Feature enabled
} else {
    // Feature disabled
}
```

#### 5. Document Option

**File**: `src/docs/UCI_PROTOCOL.md`

```markdown
### YourNewOption

**Type**: Check (boolean)
**Default**: true
**Description**: Brief description of what this option does

**Example**:
```
setoption name YourNewOption value false
```
```

#### 6. Test

```bash
./sanmill
setoption name YourNewOption value false
isready
readyok
```

### Validation Checklist

- [ ] Option appears in UCI output
- [ ] Default value correct
- [ ] Setter/getter work
- [ ] Option documented
- [ ] Tested with both values

---

## Workflow 6: Fix Search Bug

### Objective
Debug and fix a bug in search algorithm.

### Prerequisites
- Debugging skills
- Understanding of search algorithms
- Knowledge of Position and SearchEngine APIs

### Steps

#### 1. Reproduce Bug

Create minimal test case:

```cpp
TEST(SearchBugTest, ReproduceBug) {
    Position pos;
    pos.set("fen_that_causes_bug");
    
    SearchEngine engine;
    engine.setRootPosition(&pos);
    engine.runSearch();
    
    Move best = engine.getBestMove();
    // Bug manifests here
}
```

#### 2. Add Debug Output

```cpp
Value Search::search(...) {
    #ifdef DEBUG_MODE
    debugPrintf("Search depth=%d, alpha=%d, beta=%d\n", depth, alpha, beta);
    debugPrintf("Position: %s\n", pos->fen().c_str());
    #endif
    
    // ... rest of function ...
}
```

#### 3. Trace Execution

```bash
make debug
gdb ./sanmill
(gdb) break Search::search
(gdb) run
(gdb) next
(gdb) print depth
(gdb) print alpha
(gdb) print beta
```

#### 4. Identify Root Cause

Common bug categories:
- Off-by-one errors
- Sign errors (alpha/beta)
- Forgetting to undo moves
- Race conditions
- Integer overflow

#### 5. Implement Fix

```cpp
// BEFORE (buggy)
if (value > alpha) alpha = value;
if (value >= beta) return beta;  // Wrong order!

// AFTER (fixed)
if (value > alpha) alpha = value;
if (alpha >= beta) return beta;  // Correct order
```

#### 6. Add Regression Test

```cpp
TEST(SearchBugTest, FixedBug_Issue123) {
    // This test would have failed before fix
    Position pos;
    pos.set("bug_triggering_fen");
    
    SearchEngine engine;
    engine.setRootPosition(&pos);
    engine.runSearch();
    
    Move best = engine.getBestMove();
    Value eval = engine.getBestValue();
    
    // Verify correct behavior
    EXPECT_NE(best, MOVE_NONE);
    EXPECT_GT(eval, -VALUE_INFINITE);
}
```

### Validation Checklist

- [ ] Bug reproducible with test case
- [ ] Root cause identified
- [ ] Fix implements correctly
- [ ] Regression test added
- [ ] All other tests still pass

---

## Workflow 7: Add Opening Book Moves

### Objective
Extend opening book with new opening lines.

### Prerequisites
- Understanding of opening theory
- Knowledge of FEN format
- Familiarity with opening book structure

### Steps

#### 1. Collect Opening Moves

Research good opening moves for Mill:
- Standard openings
- Tactical variations
- Regional variants

#### 2. Add to Opening Book

**File**: `src/opening_book.cpp`

```cpp
void OpeningBook::init() {
    // Existing openings...
    
    // Add new opening
    book["********/********/********_w_0_0"] = {"a1", "d2", "g1"};  // Multiple options
    
    // After first move
    book["********/********/********_b_0_1"] = {"d2", "a1"};
    
    // ... more positions ...
}
```

#### 3. Test Book Moves

```bash
./sanmill
position startpos
go depth 1
# Should return book move instantly
```

#### 4. Validate Opening Quality

Play test games with new openings:

```bash
# Self-play with opening book
./sanmill
setoption name UseOpeningBook value true
# Play multiple games, record outcomes
```

### Validation Checklist

- [ ] Book moves are legal
- [ ] Moves lead to reasonable positions
- [ ] No obvious blunders
- [ ] Improves opening play

---

## Workflow 8: Implement New Rule Variant

### Objective
Add support for a new Mill game variant.

**See**: Comprehensive guide in `src/docs/RULE_SYSTEM_GUIDE.md`

### Quick Steps

1. Add Rule to `RULES[]` array in `src/rule.cpp`
2. Update `N_RULES` in `src/rule.h`
3. Add Flutter RuleSet enum value
4. Create Flutter RuleSettings class
5. Map to C++ index
6. Add localization
7. Test

**Full Details**: See [Rule System Guide](RULE_SYSTEM_GUIDE.md) and
[Adding New Game Rules](../../docs/guides/ADDING_NEW_GAME_RULES.md)

---

## General Best Practices

### Before Making Changes

1. **Read Documentation**: Understand relevant APIs
2. **Study Existing Code**: Look at similar implementations
3. **Plan Changes**: Think through approach
4. **Create Branch**: Use git for version control

### During Development

1. **Write Tests First**: TDD approach
2. **Compile Frequently**: Catch errors early
3. **Use Assertions**: Validate assumptions
4. **Add Comments**: Explain non-obvious code

### After Changes

1. **Run All Tests**: Ensure no regressions
2. **Benchmark**: Check performance impact
3. **Format Code**: Run `./format.sh s`
4. **Update Docs**: Keep documentation in sync
5. **Commit**: Use descriptive commit messages

---

## Debugging Techniques

### Print Debugging

```cpp
#include "misc.h"

debugPrintf("Value: %d\n", value);
sync_cout << "Move: " << UCI::move(m) << sync_endl;
```

### GDB Debugging

```bash
make debug
gdb ./sanmill
(gdb) break search.cpp:123
(gdb) run
(gdb) print pos->fen()
(gdb) bt  # backtrace
```

### Valgrind (Memory Debugging)

```bash
valgrind --leak-check=full ./sanmill
```

### Performance Profiling

```bash
# Linux
perf record ./sanmill < benchmark.txt
perf report

# View hotspots
perf top
```

---

## Common Issues and Solutions

### Issue: Compilation Errors

**Solution**:
1. Check include paths
2. Verify all dependencies
3. Clean and rebuild: `make clean && make all`

### Issue: Tests Failing

**Solution**:
1. Run specific test: `./test_program --gtest_filter=TestName`
2. Add debug output
3. Use debugger to step through

### Issue: Performance Regression

**Solution**:
1. Profile to find bottleneck
2. Compare with previous version
3. Check if optimization flags enabled

### Issue: UCI Communication Problems

**Solution**:
1. Check command syntax
2. Verify response format
3. Test with UCI protocol tester

---

## Resources

### Internal Documentation

- [C++ Architecture](CPP_ARCHITECTURE.md)
- [Component Catalog](CPP_COMPONENTS.md)
- [API Documentation](api/)
- [UCI Protocol](UCI_PROTOCOL.md)
- [Rule System](RULE_SYSTEM_GUIDE.md)

### External References

- UCI Protocol: http://wbec-ridderkerk.nl/html/UCIProtocol.html
- Alpha-Beta Pruning: https://en.wikipedia.org/wiki/Alpha-beta_pruning
- Minimax Algorithm: https://en.wikipedia.org/wiki/Minimax

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3

