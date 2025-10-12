# Search Algorithms API Documentation

## Overview

The `Search` namespace contains implementations of various game tree search algorithms. These are the core algorithms that determine the engine's playing strength and style.

**Location**: `src/search.h`, `src/search.cpp`

**Pattern**: Namespace with function-based API

**Dependencies**: Position, SearchEngine, Evaluate, TranspositionTable

## Namespace Definition

```cpp
namespace Search {
    void init() noexcept;
    void clear();
    
    // Main search algorithms
    Value MTDF(SearchEngine &searchEngine, Position *pos,
               Sanmill::Stack<Position> &ss, Value firstguess, 
               Depth depth, Depth originDepth, Move &bestMove);
    
    Value pvs(SearchEngine &searchEngine, Position *pos,
              Sanmill::Stack<Position> &ss, Depth depth, Depth originDepth,
              Value alpha, Value beta, Move &bestMove, int i, 
              const Color before, const Color after);
    
    Value search(SearchEngine &searchEngine, Position *pos,
                 Sanmill::Stack<Position> &ss, Depth depth, Depth originDepth,
                 Value alpha, Value beta, Move &bestMove);
    
    Value random_search(Position *pos, Move &bestMove);
    
    // Quiescence search
    Value qsearch(SearchEngine &searchEngine, Position *pos,
                  Sanmill::Stack<Position> &ss, Depth depth, Depth originDepth,
                  Value alpha, Value beta, Move &bestMove);
}
```

## Key Concepts

### Search Tree

```
Root Position
  ├─ Move 1
  │   ├─ Opponent Response 1a
  │   └─ Opponent Response 1b
  ├─ Move 2
  │   ├─ Opponent Response 2a
  │   └─ Opponent Response 2b
  └─ Move 3
      └─ ...
```

**Terminology**:
- **Ply**: One move (half-move)
- **Depth**: Number of plies to search
- **Node**: A position in the tree
- **Leaf**: Terminal node (depth = 0 or game over)

---

### Alpha-Beta Pruning

**Core Idea**: Skip branches that cannot influence final result

```
Alpha (α): Best value for maximizing player (lower bound)
Beta (β):  Best value for minimizing player (upper bound)

If α >= β: Prune (beta cutoff)
```

**Benefits**:
- Reduces search tree from O(b^d) to O(b^(d/2)) with perfect ordering
- Same result as minimax but faster
- Move ordering crucial for efficiency

---

### Evaluation

**Score Representation**:
- Positive: Advantage for side to move
- Negative: Disadvantage
- Zero: Equal position
- ±VALUE_INFINITE: Forced win/loss

**Scale**:
```
+300 = ~3 pieces advantage
+100 = ~1 piece advantage
+50  = Significant positional advantage
+10  = Small advantage
0    = Equal
```

---

## Algorithm Functions

### Alpha-Beta Search

#### `search()`
```cpp
Value search(SearchEngine &searchEngine, Position *pos,
             Sanmill::Stack<Position> &ss, Depth depth, Depth originDepth,
             Value alpha, Value beta, Move &bestMove);
```

Standard Alpha-Beta pruning with null window enhancements.

**Parameters**:
- `searchEngine`: Engine instance (for options and state)
- `pos`: Current position pointer
- `ss`: Position stack for undo operations
- `depth`: Remaining search depth
- `originDepth`: Original search depth (for stats)
- `alpha`: Lower bound (best guaranteed value for maximizer)
- `beta`: Upper bound (best guaranteed value for minimizer)
- `bestMove`: Output parameter for best move found

**Returns**: Evaluation score from side-to-move perspective

**Algorithm**:
1. Check terminal conditions (depth=0, game over)
2. Probe transposition table
3. Generate legal moves
4. Order moves (hash move first, then others)
5. For each move:
   - Make move
   - Recursively search
   - Undo move
   - Update alpha/beta
   - Check for cutoff
6. Store in transposition table
7. Return best value

**Performance**: **ULTRA-CRITICAL** - Most CPU time spent here

**Example**:
```cpp
Position pos;
Sanmill::Stack<Position> history;
SearchEngine engine;
Move bestMove;

Value eval = Search::search(engine, &pos, history, 
                            8,      // depth
                            8,      // originDepth
                            -VALUE_INFINITE,  // alpha
                            VALUE_INFINITE,   // beta
                            bestMove);

std::cout << "Best move: " << UCI::move(bestMove) << "\n";
std::cout << "Evaluation: " << eval << "\n";
```

**Key Features**:
- Alpha-beta pruning for efficiency
- Transposition table integration
- Move ordering for better cutoffs
- Iterative deepening compatible

---

### MTD(f) Search

#### `MTDF()`
```cpp
Value MTDF(SearchEngine &searchEngine, Position *pos,
           Sanmill::Stack<Position> &ss, Value firstguess,
           Depth depth, Depth originDepth, Move &bestMove);
```

Memory-enhanced Test Driver with node n and value f.

**Purpose**: Faster convergence than standard Alpha-Beta in some positions

**Parameters**:
- `firstguess`: Initial value estimate (from previous depth)
- Other parameters same as `search()`

**Returns**: Exact minimax value

**Algorithm**:
```cpp
function MTD(f, depth):
    g = f
    upperbound = +INF
    lowerbound = -INF
    
    while (lowerbound < upperbound):
        if g == lowerbound:
            beta = g + 1
        else:
            beta = g
        
        g = AlphaBetaWithMemory(pos, beta - 1, beta, depth)
        
        if g < beta:
            upperbound = g
        else:
            lowerbound = g
    
    return g
```

**Characteristics**:
- Uses zero-window searches (null window)
- Requires transposition table
- Converges with fewer nodes than Alpha-Beta sometimes
- Initial guess quality matters

**Example**:
```cpp
Value previousEval = 0;  // From previous iteration

Value eval = Search::MTDF(engine, &pos, history,
                          previousEval,  // firstguess
                          10,           // depth
                          10,           // originDepth
                          bestMove);
```

**When to Use**:
- Good transposition table hit rate
- Iterative deepening (provides initial guess)
- Positions with narrow evaluation window

**When Not to Use**:
- Poor TT hit rate
- First search of position
- Very tactical positions

---

### Principal Variation Search

#### `pvs()`
```cpp
Value pvs(SearchEngine &searchEngine, Position *pos,
          Sanmill::Stack<Position> &ss, Depth depth, Depth originDepth,
          Value alpha, Value beta, Move &bestMove, int i,
          const Color before, const Color after);
```

Enhanced Alpha-Beta with zero-window searches after first move.

**Purpose**: Faster search by assuming first move is best

**Parameters**:
- `i`: Move index (0 = PV move, >0 = other moves)
- `before`, `after`: Colors before/after move
- Other parameters same as `search()`

**Algorithm**:
```cpp
function PVS(pos, alpha, beta, depth):
    bestValue = -INF
    
    for each move in moves:
        if first move:
            value = -PVS(child, -beta, -alpha, depth-1)
        else:
            // Null window search
            value = -PVS(child, -alpha-1, -alpha, depth-1)
            
            if alpha < value < beta:
                // Re-search with full window
                value = -PVS(child, -beta, -alpha, depth-1)
        
        bestValue = max(bestValue, value)
        alpha = max(alpha, value)
        if alpha >= beta:
            break  // Beta cutoff
    
    return bestValue
```

**Benefits**:
- Faster than standard Alpha-Beta with good move ordering
- Null window searches are very fast
- Re-search penalty only when move ordering wrong

**Example**:
```cpp
// First move (PV)
Value pvValue = Search::pvs(engine, &pos, history, 8, 8,
                            -VALUE_INFINITE, VALUE_INFINITE,
                            bestMove, 0,  // i = 0 (PV move)
                            WHITE, BLACK);

// Other moves
Value otherValue = Search::pvs(engine, &pos, history, 8, 8,
                               -VALUE_INFINITE, VALUE_INFINITE,
                               bestMove, 1,  // i > 0
                               WHITE, BLACK);
```

---

### Quiescence Search

#### `qsearch()`
```cpp
Value qsearch(SearchEngine &searchEngine, Position *pos,
              Sanmill::Stack<Position> &ss, Depth depth, Depth originDepth,
              Value alpha, Value beta, Move &bestMove);
```

Search tactical moves beyond depth limit to avoid horizon effect.

**Purpose**: Resolve tactical sequences (captures, mill formations) to stable positions

**Algorithm**:
1. Evaluate current position (stand-pat score)
2. If stand-pat >= beta: Return stand-pat (beta cutoff)
3. Update alpha with stand-pat
4. Generate tactical moves only (captures, mill-forming moves)
5. For each tactical move:
   - Make move
   - Recursively qsearch
   - Undo move
   - Update alpha/beta

**Tactical Moves**:
- Mill-forming moves (may lead to captures)
- Piece removals
- Moves that create immediate tactical threats

**Depth Limit**: Typically 2-4 plies beyond main search

**Example**:
```cpp
// Called at end of main search
if (depth <= 0) {
    return Search::qsearch(engine, &pos, history,
                          4,  // qsearch depth
                          originDepth,
                          alpha, beta, bestMove);
}
```

**Benefits**:
- Prevents horizon effect (tactics just beyond search depth)
- More accurate evaluation
- Relatively fast (fewer moves considered)

**Limitations**:
- Only searches tactical moves
- Can miss positional threats
- Depth limit needed to prevent explosion

---

### Random Search

#### `random_search()`
```cpp
Value random_search(Position *pos, Move &bestMove);
```

Select random legal move (for testing or weak opponent).

**Purpose**:
- Testing move generation
- Weak opponent mode
- Baseline for benchmarking

**Algorithm**:
1. Generate all legal moves
2. Select random move
3. Return arbitrary evaluation

**Performance**: Instant (no search)

**Example**:
```cpp
Move move;
Value eval = Search::random_search(&pos, move);
// move is random legal move
```

---

## Supporting Functions

### `init()`
```cpp
void init() noexcept;
```

Initialize search module (called once at startup).

**Side Effects**:
- Initializes static data structures
- Prepares search tables

**Example**:
```cpp
int main() {
    Search::init();  // Initialize search module
    // ... rest of program
}
```

---

### `clear()`
```cpp
void clear();
```

Clear search state (called between games).

**Side Effects**:
- Clears transposition table (if desired)
- Resets search statistics

**Example**:
```cpp
// Between games
Search::clear();
```

---

## Search Enhancements

### Transposition Table

**Purpose**: Cache previously evaluated positions

**Usage in Search**:
```cpp
// Probe TT at start of search
TTEntry *tte = TT.probe(pos.key());
if (tte && tte->depth >= depth) {
    return tte->value;  // Use cached value
}

// Store result at end of search
TT.store(pos.key(), value, depth, bestMove);
```

**Benefits**:
- Avoid re-evaluating same position
- Can reduce search by 10x or more
- Essential for MTD(f)

---

### Move Ordering

**Purpose**: Search best moves first for better cutoffs

**Ordering Priority**:
1. **Hash move**: Best move from transposition table
2. **Mill-forming moves**: May lead to captures
3. **Captures**: Direct material gain
4. **History heuristic**: Moves that caused cutoffs before
5. **Other moves**: Remaining moves

**Implementation**:
```cpp
// In move loop
std::vector<Move> moves = generate_legal_moves(pos);

// Sort by score
sort(moves, [](Move a, Move b) {
    return score(a) > score(b);
});

// Search in order
for (Move m : moves) {
    // ...
}
```

**Impact**: Good ordering → 5-10x speedup

---

### Aspiration Windows

**Purpose**: Narrow search window for faster search

**Algorithm**:
```cpp
Value aspirationSearch(Position *pos, Value prevEval, Depth depth) {
    const int window = 50;  // Aspiration window size
    
    Value alpha = prevEval - window;
    Value beta = prevEval + window;
    
    Value value = search(pos, depth, alpha, beta);
    
    if (value <= alpha || value >= beta) {
        // Outside window, re-search with full window
        value = search(pos, depth, -VALUE_INFINITE, VALUE_INFINITE);
    }
    
    return value;
}
```

**Benefits**:
- Faster when estimate is accurate
- Minimal penalty when wrong

---

### Iterative Deepening

**Purpose**: Search progressively deeper, using previous results

**Algorithm**:
```cpp
Value iterativeDeepening(Position *pos, Depth maxDepth) {
    Value value = 0;
    Move bestMove;
    
    for (Depth d = 1; d <= maxDepth; d++) {
        value = Search::search(pos, d, -VALUE_INFINITE, VALUE_INFINITE, bestMove);
        
        if (timeout()) break;
        
        // Use result for next iteration
        TT.store(pos.key(), value, d, bestMove);
    }
    
    return value;
}
```

**Benefits**:
- Anytime algorithm (can stop at any time)
- Better move ordering for deeper searches
- Minimal overhead (~10-20% extra nodes)

---

## Performance Characteristics

### Time Complexity

**Alpha-Beta**:
- Best case: O(b^(d/2)) - perfect move ordering
- Average: O(b^(3d/4)) - realistic move ordering
- Worst case: O(b^d) - random move ordering

Where:
- b = branching factor (~30 for Mill)
- d = depth

**MTD(f)**:
- Similar to Alpha-Beta
- Fewer nodes with good TT hit rate
- More nodes with poor initial guess

**Quiescence**:
- O(t^q) where t = tactical branching (~5-10), q = qsearch depth

---

### Space Complexity

**Search Stack**: O(d)
- Per-ply: ~200 bytes
- Depth 8: ~1.6 KB
- Depth 12: ~2.4 KB

**Transposition Table**: O(1) for probes (hash lookup)

---

### Nodes Per Second

**Typical Performance** (varies by position):
- Placing phase: 100K-500K nodes/sec
- Moving phase: 50K-200K nodes/sec
- Endgame: 200K-1M nodes/sec

**Factors**:
- Position complexity
- Move ordering quality
- TT hit rate
- Evaluation complexity

---

## Usage Patterns

### Basic Search

```cpp
Position pos;
pos.set("fen_string");
Sanmill::Stack<Position> history;
SearchEngine engine;
Move bestMove;

Value eval = Search::search(engine, &pos, history,
                            8,  // depth
                            8,  // originDepth
                            -VALUE_INFINITE,
                            VALUE_INFINITE,
                            bestMove);

pos.do_move(bestMove);
```

---

### Iterative Deepening

```cpp
Value prevEval = 0;
Move bestMove;

for (Depth d = 1; d <= 10; d++) {
    Value eval = Search::search(engine, &pos, history,
                                d, d,
                                -VALUE_INFINITE, VALUE_INFINITE,
                                bestMove);
    
    if (engine.isAborted()) break;
    
    prevEval = eval;
    std::cout << "Depth " << d << ": " << eval << "\n";
}
```

---

### MTD(f) with Aspiration

```cpp
Value guess = 0;  // Initial guess

for (Depth d = 1; d <= maxDepth; d++) {
    Value eval = Search::MTDF(engine, &pos, history,
                              guess,  // Use previous result
                              d, d, bestMove);
    
    guess = eval;  // Update guess for next iteration
}
```

---

### Algorithm Comparison

```cpp
// Test different algorithms on same position
Move ab_move, mtdf_move, mcts_move;

// Alpha-Beta
gameOptions.setAlgorithm(1);
Value ab_eval = Search::search(..., ab_move);

// MTD(f)
gameOptions.setAlgorithm(2);
Value mtdf_eval = Search::MTDF(..., mtdf_move);

// Compare
if (ab_move == mtdf_move) {
    std::cout << "Algorithms agree\n";
}
```

---

## Thread Safety

**Not Thread-Safe**: Search functions modify Position and use SearchEngine state

**Recommendations**:
- Each thread should have own Position copy
- Each thread should have own SearchEngine instance
- Or: Use mutex to synchronize access

---

## Debugging

### Debug Output

```cpp
#ifdef DEBUG_MODE
debugPrintf("Search depth %d, alpha=%d, beta=%d\n", depth, alpha, beta);
debugPrintf("Generated %d moves\n", moves.size());
debugPrintf("Best move: %s, value: %d\n", UCI::move(bestMove).c_str(), value);
#endif
```

---

### Performance Profiling

```cpp
#ifdef TIME_STAT
auto start = std::chrono::steady_clock::now();
Value result = Search::search(...);
auto end = std::chrono::steady_clock::now();
auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);
std::cout << "Search time: " << duration.count() << "ms\n";
#endif
```

---

## Common Pitfalls

### 1. Not Checking Abort Flag

```cpp
// BAD: Long search without checking
for (Move m : moves) {
    value = -search(pos, depth-1, -beta, -alpha, move);
    // Never checks if aborted!
}

// GOOD: Check periodically
for (Move m : moves) {
    if (searchEngine.isAborted()) break;
    value = -search(pos, depth-1, -beta, -alpha, move);
}
```

---

### 2. Forgetting to Undo Moves

```cpp
// BAD: Leak positions
for (Move m : moves) {
    pos->do_move(m);
    value = -search(pos, depth-1, -beta, -alpha, move);
    // Forgot to undo!
}

// GOOD: Always undo
for (Move m : moves) {
    history.push(*pos);
    pos->do_move(m);
    value = -search(pos, depth-1, -beta, -alpha, move);
    pos->undo_move(history);
}
```

---

### 3. Incorrect Alpha-Beta Update

```cpp
// BAD: Wrong update order
value = -search(...);
if (value >= beta) return beta;  // Cutoff
if (value > alpha) alpha = value;  // Too late!

// GOOD: Correct order
value = -search(...);
if (value > alpha) alpha = value;  // Update first
if (alpha >= beta) return beta;     // Then check cutoff
```

---

## See Also

- [SearchEngine API](SearchEngine.md) - Search coordinator
- [Position API](Position.md) - Position management
- [C++ Architecture](../CPP_ARCHITECTURE.md) - System overview

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3

