# SearchEngine API Documentation

## Overview

`SearchEngine` is the coordinator class responsible for managing game tree search, selecting the best move using various algorithms, and integrating with perfect play databases and opening books.

**Location**: `src/search_engine.h`, `src/search_engine.cpp`

**Pattern**: Service object with mutable state

**Dependencies**: Position, Search namespace, TranspositionTable, OpeningBook, Perfect DB

## Class Definition

```cpp
class SearchEngine {
public:
    SearchEngine();
    ~SearchEngine();
    
    // Search management
    void setRootPosition(Position *p);
    uint64_t beginNewSearch(Position *p);
    void runSearch();
    int executeSearch();
    void abort();
    
    // Result access
    Move getBestMove() const;
    Value getBestValue() const;
    AiMoveType getAiMoveType() const;
    
    // Configuration
    Depth get_depth() const;
    void set_depth(Depth d);
    bool is_timeout(TimePoint startTime) const;
    
    // State queries
    bool isSearching() const;
    uint64_t getCurrentSearchId() const;
    
private:
    Position *rootPos;                       // Position to search from
    Move bestMove;                           // Best move found
    Value bestvalue;                         // Evaluation of best move
    Depth originDepth;                       // Search depth
    AiMoveType aiMoveType;                   // Move source (traditional/perfect/consensus)
    std::atomic<bool> searchAborted;         // Abort flag
    std::atomic<uint64_t> currentSearchId;   // Search ID for tracking
    uint64_t searchCounter;                  // Search counter
    TimePoint searchStartTime;               // Search start timestamp
    // ... more private members
};
```

## Key Responsibilities

1. **Search Coordination**: Manage iterative deepening and algorithm selection
2. **Root Position**: Maintain position to search from
3. **Algorithm Integration**: Coordinate Alpha-Beta, MTD(f), MCTS algorithms
4. **Time Management**: Handle search timeouts and interruption
5. **Database Integration**: Integrate opening book and perfect play database
6. **Result Management**: Store and provide best move and evaluation

## Constructor and Destructor

### `SearchEngine()`
```cpp
SearchEngine();
```

Create a new search engine instance.

**Postconditions**:
- Search state initialized
- No active search
- Default depth configured

**Example**:
```cpp
SearchEngine engine;
```

---

### `~SearchEngine()`
```cpp
~SearchEngine();
```

Destroy search engine and clean up resources.

**Side Effects**:
- Aborts any ongoing search
- Releases allocated resources

---

## Search Management

### `setRootPosition(pos)`
```cpp
void setRootPosition(Position *p);
```

Set the root position to search from.

**Parameters**:
- `p`: Pointer to position (must remain valid during search)

**Preconditions**:
- No search currently running
- Position pointer not null

**Side Effects**:
- Stores position pointer
- Does **not** copy position
- Does **not** start search

**Example**:
```cpp
Position pos;
pos.set("fen_string");

SearchEngine engine;
engine.setRootPosition(&pos);
// Position set, ready to search
```

**Important**: Position object must remain valid during entire search

---

### `beginNewSearch(pos)`
```cpp
uint64_t beginNewSearch(Position *p);
```

Initialize a new search session.

**Parameters**:
- `p`: Root position for search

**Returns**: Unique search ID

**Side Effects**:
- Increments search counter
- Resets abort flag
- Records search start time
- Sets root position

**Use Cases**:
- Start new search
- Track search progress
- Cancel specific search

**Example**:
```cpp
Position pos;
uint64_t searchId = engine.beginNewSearch(&pos);
// Search initialized but not started
```

---

### `runSearch()`
```cpp
void runSearch();
```

Execute the search and find best move.

**Preconditions**:
- Root position set via `setRootPosition()` or `beginNewSearch()`

**Side Effects**:
- Executes search algorithm
- Updates `bestMove` and `bestvalue`
- May take significant time
- Blocks until complete or aborted

**Search Process**:
1. Check opening book (if enabled)
2. Execute iterative deepening (if enabled)
3. Run main search algorithm
4. Query perfect database (if available)
5. Store best move and value

**Example**:
```cpp
engine.setRootPosition(&pos);
engine.runSearch();  // Blocks until search completes

Move best = engine.getBestMove();
Value eval = engine.getBestValue();
```

**Threading**: Blocking call - consider running in separate thread for responsive UI

---

### `executeSearch()`
```cpp
int executeSearch();
```

Low-level search execution (called by `runSearch()`).

**Returns**: Status code (implementation-defined)

**Side Effects**:
- Performs actual search
- Updates internal state

**Note**: Typically not called directly - use `runSearch()` instead

---

### `abort()`
```cpp
void abort();
```

Interrupt ongoing search.

**Side Effects**:
- Sets abort flag (atomic)
- Search will terminate gracefully at next check
- Best move found so far will be returned

**Thread-Safe**: Yes - can be called from any thread

**Example**:
```cpp
// Thread 1: Start search
engine.runSearch();

// Thread 2: User clicks "stop"
engine.abort();

// Thread 1: Search stops, returns best move so far
Move best = engine.getBestMove();
```

**Timing**: Search checks abort flag every ~1000 nodes (fast response)

---

## Result Access

### `getBestMove()`
```cpp
Move getBestMove() const;
```

Get the best move found by search.

**Returns**: Best move, or `MOVE_NONE` if no move found

**Preconditions**:
- Search completed (or aborted)

**Example**:
```cpp
engine.runSearch();
Move best = engine.getBestMove();

if (best != MOVE_NONE) {
    pos.do_move(best);
}
```

**Thread-Safe**: Yes - after search completes

---

### `getBestValue()`
```cpp
Value getBestValue() const;
```

Get evaluation score of best move.

**Returns**: Evaluation in centipawns (100 = one piece advantage)

**Interpretation**:
- Positive: Advantage for side to move
- Negative: Disadvantage for side to move
- Zero: Equal position
- `VALUE_INFINITE`: Forced win
- `-VALUE_INFINITE`: Forced loss

**Example**:
```cpp
Value eval = engine.getBestValue();

if (eval > 100) {
    // Significant advantage (>1 piece)
} else if (eval == VALUE_INFINITE) {
    // Forced win
}
```

---

### `getAiMoveType()`
```cpp
AiMoveType getAiMoveType() const;
```

Get source of best move.

**Returns**:
- `AiMoveType::traditional`: From search algorithm
- `AiMoveType::perfect`: From perfect database
- `AiMoveType::consensus`: Search and database agree
- `AiMoveType::unknown`: Not determined

**Use Cases**:
- Display move source to user
- Statistics tracking
- Debug analysis

**Example**:
```cpp
AiMoveType type = engine.getAiMoveType();

switch (type) {
    case AiMoveType::perfect:
        std::cout << "Perfect database move\n";
        break;
    case AiMoveType::traditional:
        std::cout << "Search algorithm move\n";
        break;
    case AiMoveType::consensus:
        std::cout << "Verified by both\n";
        break;
}
```

---

## Configuration

### `get_depth()`
```cpp
Depth get_depth() const;
```

Get configured search depth.

**Returns**: Depth in plies (half-moves)

**Example**:
```cpp
Depth d = engine.get_depth();
// d == 8 (default)
```

---

### `set_depth(depth)`
```cpp
void set_depth(Depth d);
```

Set search depth.

**Parameters**:
- `d`: Depth in plies (1-16 typical)

**Preconditions**:
- `d > 0`

**Side Effects**:
- Updates internal depth parameter
- Affects next search

**Recommendations**:
- Depth 1-4: Very fast, weak
- Depth 6-8: Balanced (default)
- Depth 10-12: Strong, slower
- Depth 14+: Very strong, very slow

**Example**:
```cpp
engine.set_depth(10);  // Search 10 plies deep
engine.runSearch();
```

**Note**: Iterative deepening may reach target depth early if time limited

---

### `is_timeout(startTime)`
```cpp
bool is_timeout(TimePoint startTime) const;
```

Check if search time limit exceeded.

**Parameters**:
- `startTime`: Search start timestamp

**Returns**: true if time limit exceeded

**Use Cases**:
- Time management
- Search interruption

**Example**:
```cpp
TimePoint start = now();

// In search loop
if (engine.is_timeout(start)) {
    // Time exceeded, stop search
}
```

---

## State Queries

### `isSearching()`
```cpp
bool isSearching() const;
```

Check if search is currently running.

**Returns**: true if search active

**Example**:
```cpp
if (engine.isSearching()) {
    // Can't start new search
} else {
    engine.runSearch();
}
```

---

### `getCurrentSearchId()`
```cpp
uint64_t getCurrentSearchId() const;
```

Get ID of current search.

**Returns**: Search ID (unique per search)

**Use Cases**:
- Track multiple search sessions
- Cancel specific search

**Example**:
```cpp
uint64_t id = engine.getCurrentSearchId();
// Use id to identify this search
```

---

## Search Algorithms

SearchEngine supports multiple algorithms (selectable via options):

### Algorithm 1: Alpha-Beta Pruning

**Default**: Yes  
**Best For**: Tactical positions, general play  
**Performance**: Good with move ordering  

**Set via**:
```cpp
gameOptions.setAlgorithm(1);
```

---

### Algorithm 2: MTD(f)

**Default**: No  
**Best For**: Positions with good TT hit rate  
**Performance**: Faster convergence in some cases  
**Requires**: Transposition table enabled  

**Set via**:
```cpp
gameOptions.setAlgorithm(2);
```

---

### Algorithm 3: MCTS

**Default**: No  
**Best For**: Complex positions, uncertain evaluations  
**Performance**: More simulations = better  
**Parameters**: Simulation count configurable  

**Set via**:
```cpp
gameOptions.setAlgorithm(3);
```

---

### Algorithm 4: Random

**Default**: No  
**Best For**: Testing, weak opponent  
**Performance**: Instant  

**Set via**:
```cpp
gameOptions.setAlgorithm(4);
```

---

## Iterative Deepening

### Overview

Iterative Deepening Search (IDS) searches progressively deeper until time/depth limit.

**Benefits**:
1. **Anytime Algorithm**: Can stop at any time with valid result
2. **Better Move Ordering**: Shallow search informs deeper search
3. **Time Management**: Easier to control time usage

**Process**:
```
Depth 1: Quick scan
Depth 2: Use depth 1 results for ordering
Depth 3: Use depth 2 results for ordering
...
Depth N: Target depth reached
```

**Enable/Disable**:
```cpp
gameOptions.setIDSEnabled(true);  // Enable IDS
gameOptions.setIDSEnabled(false); // Disable IDS (fixed depth)
```

**Info Output**:
```
info depth 1 score cp 0 nodes 24 time 1 pv a1b2
info depth 2 score cp 10 nodes 156 time 5 pv a1b2 c3d4
info depth 3 score cp 15 nodes 892 time 42 pv a1b2 c3d4 e5f6
...
```

---

## Database Integration

### Opening Book

**Purpose**: Fast, strong opening moves without search

**Usage**:
1. Check if position in book
2. If yes: Return book move instantly
3. If no: Proceed with search

**Enable**:
```cpp
gameOptions.setUseOpeningBook(true);
```

**Example Flow**:
```cpp
engine.runSearch();
// If in opening book: instant return
// Otherwise: full search
Move best = engine.getBestMove();
```

---

### Perfect Play Database

**Purpose**: Exact game-theoretic value for endgame positions

**Usage**:
1. After search completes
2. Query perfect database
3. If found: Use perfect move (overrides search)
4. If not found: Use search result

**Enable**:
```cpp
gameOptions.setUsePerfectDatabase(true);
```

**Move Type**:
- `AiMoveType::perfect`: Database move used
- `AiMoveType::consensus`: Database and search agree
- `AiMoveType::traditional`: Database not available, search used

**Example**:
```cpp
engine.runSearch();

if (engine.getAiMoveType() == AiMoveType::perfect) {
    // This is a perfect move (cannot be improved)
}
```

---

## Time Management

### Time Allocation

**Sources**:
1. `go movetime <ms>` command
2. `MoveTime` engine option
3. Time allocation formula (for timed games)

**Checking Timeout**:
```cpp
TimePoint start = now();

while (/* search loop */) {
    if (engine.is_timeout(start)) {
        break;  // Stop search
    }
    // Continue searching
}
```

---

### Soft vs Hard Limits

**Soft Limit**: Target time (can be exceeded slightly)  
**Hard Limit**: Maximum time (must not exceed)

**Implementation**: Search checks timeout every ~1000 nodes

---

## Performance Characteristics

### Time Complexity

**Per Search**:
- Alpha-Beta: O(b^d) where b=branching (~30), d=depth
- MTD(f): O(b^d) but fewer nodes than Alpha-Beta typically
- MCTS: O(n × d) where n=simulations, d=avg depth

**Typical Performance**:
- Depth 6: ~0.1-0.5 seconds
- Depth 8: ~1-5 seconds
- Depth 10: ~5-30 seconds
- Depth 12: ~30-300 seconds

---

### Space Complexity

**Per Search**: ~O(d) for search stack
- Depth 8: ~1.6 KB
- Depth 12: ~2.4 KB

**Shared State**:
- Transposition table: 16-256 MB (configurable)
- Opening book: 1-10 MB

---

## Usage Patterns

### Basic Search

```cpp
// Setup
Position pos;
pos.set("fen_string");

SearchEngine engine;
engine.setRootPosition(&pos);
engine.set_depth(8);

// Execute
engine.runSearch();

// Get result
Move best = engine.getBestMove();
Value eval = engine.getBestValue();

// Apply move
pos.do_move(best);
```

---

### Iterative Deepening with Timeout

```cpp
// Setup
engine.setRootPosition(&pos);
gameOptions.setIDSEnabled(true);
gameOptions.setMoveTime(5000);  // 5 seconds

// Execute
engine.runSearch();  // Will stop after ~5 seconds

// Get result (best move found within time)
Move best = engine.getBestMove();
```

---

### Abortable Search (Separate Thread)

```cpp
// Thread 1: Search
std::thread searchThread([&]() {
    engine.runSearch();
});

// Thread 2: UI event
void onStopButton() {
    engine.abort();  // Safe to call from any thread
}

// Wait for search
searchThread.join();

// Get result
Move best = engine.getBestMove();
```

---

### Multiple Algorithms Comparison

```cpp
Position pos;
pos.set("fen_string");

// Algorithm 1: Alpha-Beta
gameOptions.setAlgorithm(1);
engine.setRootPosition(&pos);
engine.runSearch();
Move ab_move = engine.getBestMove();
Value ab_eval = engine.getBestValue();

// Algorithm 2: MTD(f)
gameOptions.setAlgorithm(2);
engine.setRootPosition(&pos);
engine.runSearch();
Move mtdf_move = engine.getBestMove();
Value mtdf_eval = engine.getBestValue();

// Compare results
if (ab_move == mtdf_move) {
    std::cout << "Algorithms agree\n";
}
```

---

## Thread Safety

### Thread-Safe Operations

- `abort()`: Can be called from any thread
- Read operations after search completes

### Not Thread-Safe

- `setRootPosition()` during search
- `runSearch()` from multiple threads on same engine
- Modifying options during search

### Recommendations

- Use separate `SearchEngine` instance per thread
- Or: Synchronize access with mutexes
- Or: Use thread-local storage

---

## Error Handling

### No Legal Moves

```cpp
engine.runSearch();
Move best = engine.getBestMove();

if (best == MOVE_NONE) {
    // No legal moves (game over)
    assert(pos.get_phase() == Phase::gameOver);
}
```

---

### Search Timeout

```cpp
gameOptions.setMoveTime(1000);  // 1 second
engine.runSearch();

// Search may have been cut off
// Best move so far is still available
Move best = engine.getBestMove();
```

---

### Invalid Position

```cpp
Position pos;
// Don't set position!

engine.setRootPosition(&pos);
engine.runSearch();  // Undefined behavior!

// CORRECT:
pos.set("valid_fen");
engine.setRootPosition(&pos);
engine.runSearch();  // OK
```

---

## Debugging

### Search Info

Enable developer mode for verbose output:

```cpp
gameOptions.setDeveloperMode(true);
engine.runSearch();

// Output:
// debug: Search starting depth 8
// debug: Nodes: 1234, Time: 100ms
// debug: Best move: a1b2, Value: +50
```

---

### Assertions

Debug builds include assertions:

```cpp
assert(rootPos != nullptr);           // Position set
assert(bestMove != MOVE_NONE);        // Valid move found
assert(depth > 0 && depth <= 20);     // Reasonable depth
```

---

## Common Pitfalls

### 1. Not Setting Root Position

```cpp
// BAD: No position set
SearchEngine engine;
engine.runSearch();  // Crash or undefined behavior!

// GOOD: Set position first
engine.setRootPosition(&pos);
engine.runSearch();
```

---

### 2. Position Goes Out of Scope

```cpp
// BAD: Position destroyed while engine holds pointer
void badFunction() {
    Position pos;
    engine.setRootPosition(&pos);
}  // pos destroyed!
engine.runSearch();  // Dangling pointer!

// GOOD: Position outlives engine usage
Position pos;
engine.setRootPosition(&pos);
engine.runSearch();  // OK - pos still valid
```

---

### 3. Concurrent Searches on Same Engine

```cpp
// BAD: Multiple threads, one engine
std::thread t1([&]() { engine.runSearch(); });
std::thread t2([&]() { engine.runSearch(); });  // Race condition!

// GOOD: Separate engines
SearchEngine engine1, engine2;
std::thread t1([&]() { engine1.runSearch(); });
std::thread t2([&]() { engine2.runSearch(); });
```

---

### 4. Reading Results During Search

```cpp
// BAD: Read while searching
std::thread([&]() { engine.runSearch(); }).detach();
Move m = engine.getBestMove();  // Race condition!

// GOOD: Wait for completion
std::thread t([&]() { engine.runSearch(); });
t.join();  // Wait
Move m = engine.getBestMove();  // Safe
```

---

## See Also

- [Search Algorithms](Search.md) - Detailed algorithm documentation
- [Position API](Position.md) - Position management
- [C++ Architecture](../CPP_ARCHITECTURE.md) - System architecture
- [UCI Protocol](../UCI_PROTOCOL.md) - Communication protocol

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3

