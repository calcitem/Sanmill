# Performance Critical Paths and Optimization Guide

## Overview

This document identifies performance-critical code paths in the Sanmill engine and provides optimization guidelines for AI agents and developers. Understanding these hotspots is essential to avoid performance regressions.

**Target Audience**: AI agents and developers working on performance-sensitive code

**Warning**: Changes to ultra-critical paths require careful benchmarking

## Performance Critical Paths

**Note**: CPU usage percentages and call frequencies are estimated values
based on typical search scenarios. Actual values may vary depending on
position complexity, search depth, and hardware. Use profiling tools to
measure actual performance in your specific use case.

### 🔥 Level 1: Ultra-Critical (>40% CPU time)

These functions consume the majority of CPU time during search. Any changes
require extensive benchmarking.

#### 1. Search::search()

**Location**: `src/search.cpp:140-393`  
**CPU Usage**: ~45% of total (estimated)  
**Call Frequency**: ~1M times per second (estimated)  
**Complexity**: O(b^d) where b=branching factor, d=depth

**Why Critical**:
- Core recursive search function
- Called for every node in game tree
- Small inefficiencies multiply exponentially

**Optimization Guidelines**:
- ✅ Minimize memory allocation
- ✅ Use inline functions for helpers
- ✅ Optimize move ordering
- ✅ Use transposition table effectively
- ❌ Avoid virtual function calls
- ❌ Avoid exception handling
- ❌ Avoid I/O operations

**Benchmark After Changes**:
```bash
./sanmill bench
# Compare nodes/second before and after
```

---

#### 2. Position::do_move()

**Location**: `src/position.cpp:815-853`  
**CPU Usage**: ~25% of total (estimated)  
**Call Frequency**: ~500K times per second (estimated)  
**Complexity**: O(1)

**Why Critical**:
- Called for every node in search tree
- Modifies board state (bitboards, hash keys)
- Must be extremely fast for good NPS (nodes per second)

**Current Optimizations**:
- Bitboard operations (fast bit manipulation)
- Incremental hash key updates
- Inline piece placement
- Minimal branching

**Optimization Guidelines**:
- ✅ Use bitwise operations instead of loops
- ✅ Update hash keys incrementally
- ✅ Keep function inline-able
- ❌ Avoid memory allocation
- ❌ Avoid function calls in hot loop
- ❌ Avoid conditional branches when possible

**Example Optimization**:
```cpp
// SLOW: Loop through squares
void update_hash() {
    key = 0;
    for (int sq = 0; sq < 24; sq++) {
        if (piece_on(sq) == W_PIECE) {
            key ^= zobrist[sq][WHITE];
        }
    }
}

// FAST: Incremental update
void update_hash_incrementally(Square from, Square to) {
    key ^= zobrist[from][sideToMove];  // Remove from 'from'
    key ^= zobrist[to][sideToMove];    // Add to 'to'
}
```

---

#### 3. Position::undo_move()

**Location**: `src/position.cpp:858-862`  
**CPU Usage**: ~15% of total (estimated)  
**Call Frequency**: ~500K times per second (estimated)  
**Complexity**: O(1)

**Why Critical**:
- Called after every do_move() in search
- Must restore complete position state
- Performance directly impacts search speed

**Optimization Guidelines**:
- ✅ Minimize data copying
- ✅ Use stack-based storage
- ✅ Inline state restoration
- ❌ Avoid memory allocation
- ❌ Avoid validation in release builds

---

### 🌡️ Level 2: Critical (10-40% CPU time)

#### 4. MoveGen::generate_legal_moves()

**Location**: `src/movegen.cpp` (implementation varies by move type)  
**CPU Usage**: ~12% of total (estimated)  
**Call Frequency**: ~100K times per second (estimated)  
**Complexity**: O(m) where m = legal moves

**Why Critical**:
- Called once per search node
- Generates all legal moves for position
- Move ordering affects search efficiency

**Optimization Guidelines**:
- ✅ Generate moves in priority order (captures first)
- ✅ Use bitboard operations for move generation
- ✅ Avoid generating illegal moves
- ❌ Avoid sorting (generate in order instead)
- ❌ Avoid dynamic memory allocation

---

#### 5. Position::is_all_in_mills()

**Location**: `src/position.cpp` (check current implementation)  
**CPU Usage**: ~8% of total (estimated)  
**Call Frequency**: ~50K times per second (estimated)  
**Complexity**: O(1)

**Why Critical**:
- Called during move generation (remove moves)
- Determines if can remove from mills
- Simple check but called very frequently

**Current Implementation**: Bitboard-based (fast)

**Optimization**: Already optimized, avoid adding complexity

---

### ❄️ Level 3: Warm (1-10% CPU time)

#### 6. Evaluate::evaluate()

**Location**: `src/evaluate.cpp` (main evaluation function)  
**CPU Usage**: ~5% of total (estimated)  
**Call Frequency**: ~100K times per second (estimated)  
**Complexity**: O(1)

**Why Matters**:
- Called at leaf nodes of search
- Determines position quality
- More accurate → better play, but slower

**Optimization Guidelines**:
- ✅ Keep evaluation simple and fast
- ✅ Use precomputed tables
- ✅ Avoid expensive calculations
- ⚠️ Balance accuracy vs speed

---

#### 7. TranspositionTable::probe()

**Location**: `src/tt.cpp` (static member function)  
**CPU Usage**: ~4% of total (estimated)  
**Call Frequency**: ~1M times per second (estimated)  
**Complexity**: O(1)

**Why Matters**:
- Provides cache hits (huge speedup)
- Called at start of every search node
- Cache locality important

**Optimization Guidelines**:
- ✅ Maximize cache hit rate
- ✅ Keep entries compact
- ✅ Use prefetching if available
- ❌ Avoid cache thrashing

---

#### 8. MovePick / Move Ordering

**Location**: `src/movepick.cpp` (MovePicker class)  
**CPU Usage**: ~3% of total (estimated)  
**Call Frequency**: ~100K times per second (estimated)  
**Complexity**: O(m log m) if sorting

**Why Matters**:
- Better move ordering → more cutoffs → faster search
- Can reduce search tree by 5-10x
- Tradeoff: ordering time vs search savings

**Optimization**: Generate moves in priority order instead of sorting

---

## Performance Budgets

### Per-Function Time Budgets

| Function | Budget (μs) | Why |
|----------|-------------|-----|
| `do_move()` | < 0.002 | Called millions of times |
| `undo_move()` | < 0.002 | Called millions of times |
| `search()` (per call) | < 0.01 | Recursive, many calls |
| `evaluate()` | < 0.005 | Leaf node evaluation |
| `generate_moves()` | < 0.05 | Once per node |
| `probe_tt()` | < 0.001 | Must be extremely fast |

### Total Search Performance

**Target**: 100K-500K nodes/second

**Breakdown**:
```
Position operations: ~40% (do_move, undo_move)
Search logic: ~45% (search, pvs, MTDF)
Move generation: ~10% (generate, ordering)
Evaluation: ~5% (evaluate at leaves)
```

---

## Optimization Techniques

### 1. Bitboard Operations

**Why**: Operate on all 24 squares simultaneously

**Example**:
```cpp
// SLOW: Loop through squares
int count_white_pieces() {
    int count = 0;
    for (Square sq = SQ_A1; sq < SQ_NB; sq++) {
        if (piece_on(sq) == W_PIECE) {
            count++;
        }
    }
    return count;
}

// FAST: Bitboard popcount
int count_white_pieces() {
    return popcount(byColorBB[WHITE]);
}
```

**Performance**: 10-100x faster

---

### 2. Incremental Updates

**Why**: Update only what changed, not entire state

**Example**:
```cpp
// SLOW: Recalculate entire hash
Key calculate_key() {
    Key k = 0;
    for (Square sq = SQ_A1; sq < SQ_NB; sq++) {
        k ^= zobrist[sq][piece_on(sq)];
    }
    return k;
}

// FAST: Incremental update
void do_move(Move m) {
    key ^= zobrist[from_sq(m)][moved_piece];  // XOR out old
    key ^= zobrist[to_sq(m)][moved_piece];    // XOR in new
}
```

**Performance**: O(n) → O(1), ~50x faster

---

### 3. Move Ordering

**Why**: Search best moves first for more cutoffs

**Ordering Priority**:
```cpp
1. Hash move (from TT)           // 10000 points
2. Mill-forming moves            // 5000 points
3. Captures                      // 2000 points
4. History heuristic moves       // 0-1000 points
5. Other moves                   // 0 points
```

**Impact**: Can reduce nodes by 5-10x

---

### 4. Transposition Table

**Why**: Avoid re-evaluating same position

**Hit Rate Impact**:
```
TT Hit Rate | Search Speedup
------------|---------------
0%          | 1x (baseline)
30%         | 1.5x
50%         | 2.5x
70%         | 5x
90%         | 10x
```

**Optimization**:
- Use large TT (128-256 MB)
- Prefer depth replacement
- Age old entries

---

### 5. Inline Functions

**Why**: Avoid function call overhead

**Example**:
```cpp
// In header (position.h)
inline bool empty(Square s) const {
    return piece_on(s) == NO_PIECE;
}

inline Piece piece_on(Square s) const {
    return board[s];
}
```

**When to Inline**:
- ✅ Small functions (<10 lines)
- ✅ Called frequently
- ✅ Simple logic
- ❌ Recursive functions
- ❌ Large functions

---

## Profiling

### Linux/macOS (gprof)

```bash
# Compile with profiling
cd src
make clean
make CXXFLAGS="-O3 -pg" LDFLAGS="-pg" all

# Run benchmark
./sanmill bench

# Analyze profile
gprof ./sanmill gmon.out > profile.txt
less profile.txt
```

### perf (Linux)

```bash
# Record performance data
perf record ./sanmill bench

# Report results
perf report

# Top functions (live monitoring)
perf top
```

### Valgrind (Cache profiling)

```bash
# Cache analysis
valgrind --tool=cachegrind ./sanmill bench

# View results
cg_annotate cachegrind.out.<pid>
```

---

## Benchmarking

### Standard Benchmark

```bash
cd src
./sanmill bench
```

**Output** (sample):
```
Benchmark: 12 positions
Total time: 5.234 seconds
Nodes searched: 2,456,789
NPS: 469,234 nodes/second
```

**Note**: The actual benchmark command is `./sanmill bench`, which runs
built-in benchmark positions.

### Custom Benchmark

```cpp
// In benchmark.cpp
void custom_benchmark() {
    Position pos;
    pos.set("your_test_position");
    
    auto start = now();
    
    SearchEngine engine;
    engine.setRootPosition(&pos);
    engine.runSearch();
    
    auto elapsed = now() - start;
    
    std::cout << "Time: " << elapsed << "ms" << std::endl;
    std::cout << "Nodes: " << engine.getNodesSearched() << std::endl;
    std::cout << "NPS: " << (engine.getNodesSearched() * 1000 / elapsed) << std::endl;
}
```

---

## Optimization Checklist

### Before Optimizing

- [ ] Profile to identify actual bottleneck
- [ ] Understand current implementation
- [ ] Establish baseline performance
- [ ] Create reproducible benchmark

### During Optimization

- [ ] Make one change at a time
- [ ] Benchmark after each change
- [ ] Keep code readable
- [ ] Add comments explaining optimizations

### After Optimization

- [ ] Run all tests (verify correctness)
- [ ] Benchmark improvement (>5% to be worthwhile)
- [ ] Check for regressions in other areas
- [ ] Document optimization rationale

---

## Performance Anti-Patterns

### 1. Memory Allocation in Hot Paths

```cpp
// BAD: Allocates every call
Value search(Position *pos, int depth) {
    std::vector<Move> moves;  // Heap allocation!
    generate_moves(pos, moves);
    // ...
}

// GOOD: Stack allocation
Value search(Position *pos, int depth) {
    Move moves[MAX_MOVES];
    int count = generate_moves(pos, moves);
    // ...
}
```

---

### 2. Unnecessary Copies

```cpp
// BAD: Copies entire position
void analyze(Position pos) {  // Copy!
    // ...
}

// GOOD: Use const reference
void analyze(const Position &pos) {  // No copy
    // ...
}
```

---

### 3. Virtual Function Calls in Loops

```cpp
// BAD: Virtual call overhead
for (int i = 0; i < 1000000; i++) {
    value += obj->virtual_function();  // Slow
}

// GOOD: Direct call or inline
for (int i = 0; i < 1000000; i++) {
    value += direct_function();  // Fast
}
```

---

### 4. Branch Misprediction

```cpp
// BAD: Unpredictable branches
if (rare_condition) {  // Mispredicted often
    // ...
}

// GOOD: Predict likely path
if (__builtin_expect(rare_condition, 0)) {  // Hint to compiler
    // ...
}
```

---

### 5. Cache Misses

```cpp
// BAD: Poor cache locality
struct Node {
    Position pos;       // 200 bytes
    char metadata[800]; // Large, rarely used
    Value value;        // 4 bytes
};

// GOOD: Hot data together
struct Node {
    Value value;        // Hot data first
    Move bestMove;
    Depth depth;
    Position pos;       // Then larger data
    char metadata[800]; // Cold data last
};
```

---

## Compiler Optimizations

### Optimization Flags

```bash
# Release build (fast)
make CXXFLAGS="-O3 -DNDEBUG -march=native" all

# Debug build (debuggable)
make CXXFLAGS="-O0 -g -DDEBUG" all
```

### Flag Explanations:

- `-O3`: Aggressive optimization
- `-DNDEBUG`: Disable assertions (release only!)
- `-march=native`: Use CPU-specific instructions
- `-O0`: No optimization (debug)
- `-g`: Debug symbols

### Link-Time Optimization

```bash
# Enable LTO (link-time optimization)
make CXXFLAGS="-O3 -flto" LDFLAGS="-flto" all
```

**Benefit**: 5-15% performance improvement

---

## Performance Measurement

### Timing Code Sections

```cpp
#include "misc.h"

TimePoint start = now();

// Code to measure
search(pos, depth, alpha, beta, bestMove);

TimePoint elapsed = now() - start;
std::cout << "Elapsed: " << elapsed << "ms" << std::endl;
```

### Node Counting

```cpp
// Global counter
uint64_t nodes_searched = 0;

Value search(...) {
    nodes_searched++;
    // ... rest of search ...
}

// After search
std::cout << "Nodes: " << nodes_searched << std::endl;
std::cout << "NPS: " << (nodes_searched * 1000 / time_ms) << std::endl;
```

### Cache Statistics

```cpp
#ifdef TRANSPOSITION_TABLE_STATS
uint64_t tt_hits = 0;
uint64_t tt_probes = 0;

TTEntry *probe(Key key) {
    tt_probes++;
    TTEntry *entry = lookup(key);
    if (entry && entry->key == key) {
        tt_hits++;
        return entry;
    }
    return nullptr;
}

// Report hit rate
double hit_rate = (double)tt_hits / tt_probes;
std::cout << "TT Hit Rate: " << (hit_rate * 100) << "%" << std::endl;
```

---

## Performance Targets

### Search Performance

| Metric | Target | Excellent |
|--------|--------|-----------|
| Nodes/second | 100K | 500K |
| Depth (1 sec) | 6-8 | 10+ |
| TT hit rate | 50% | 70% |
| Beta cutoffs | 70% | 85% |

### Memory Usage

| Component | Typical | Maximum |
|-----------|---------|---------|
| Position | 200 bytes | - |
| Search stack | 2 KB | 5 KB |
| TT | 64 MB | 256 MB |
| Opening book | 5 MB | 20 MB |
| **Total** | ~70 MB | ~280 MB |

---

## Common Performance Issues

### Issue: Low NPS (< 50K nodes/sec)

**Diagnostic**:
```bash
# Profile to find bottleneck
perf record ./sanmill bench
perf report
```

**Common Causes**:
1. Debug build (use release: `-O3 -DNDEBUG`)
2. TT disabled (enable: `#define TRANSPOSITION_TABLE_ENABLE`)
3. Memory allocation in hot path
4. Poor move ordering

---

### Issue: Deep Searches Too Slow

**Diagnostic**:
- Depth 8: Should take ~1-5 seconds
- Depth 10: Should take ~5-30 seconds
- Depth 12: Should take ~30-300 seconds

**If slower**:
1. Check TT enabled and properly sized
2. Verify move ordering working
3. Check for performance regressions
4. Profile to find new bottleneck

---

### Issue: High Memory Usage

**Diagnostic**:
```bash
# Monitor memory
valgrind --tool=massif ./sanmill
ms_print massif.out.<pid>
```

**Common Causes**:
1. TT too large (reduce size)
2. Memory leak (fix leak)
3. Opening book too large
4. Search stack too deep

---

## Optimization Workflow

### Step 1: Profile

```bash
perf record ./sanmill bench
perf report --stdio > profile.txt
```

Identify function consuming most time.

### Step 2: Analyze

- Why is it slow?
- Can it be called less?
- Can it be faster?
- Is it already optimized?

### Step 3: Optimize

Apply appropriate technique:
- Algorithmic improvement
- Bitboard operations
- Incremental updates
- Caching
- Inlining

### Step 4: Benchmark

```bash
# Before
./sanmill bench > before.txt

# Apply change

# After
./sanmill bench > after.txt

# Compare
diff before.txt after.txt
```

### Step 5: Validate

```bash
# Correctness (run unit tests)
cd src
make test

# No regression (run benchmark)
./sanmill bench

# Memory
valgrind --leak-check=full ./sanmill bench
```

---

## See Also

- [C++ Architecture](CPP_ARCHITECTURE.md) - System overview
- [Components](CPP_COMPONENTS.md) - Component details
- [API Documentation](api/) - API reference
- [Workflows](CPP_WORKFLOWS.md#workflow-4) - Optimization workflow

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3

