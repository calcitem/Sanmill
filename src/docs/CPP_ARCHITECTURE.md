# Sanmill C++ Engine Architecture

## Overview

The Sanmill C++ engine is a high-performance Mill (Nine Men's Morris) game engine implementing multiple search algorithms, perfect play databases, and UCI-like protocol for GUI integration. This document describes the architectural design, core components, and data flow of the engine.

## Design Philosophy

### Core Principles

1. **Performance First**: Engine designed for competitive play with focus on search speed
2. **Algorithm Flexibility**: Support for multiple search algorithms (Alpha-Beta, MTD(f), MCTS, Random)
3. **Memory Efficiency**: Bitboard representation for fast board operations
4. **Cross-Platform**: POSIX and Windows support with minimal platform-specific code
5. **Perfect Play Integration**: Endgame tablebases for perfect play in solved positions

### Architecture Style

The engine follows a **modular architecture** with **clear separation of concerns**:

```
┌─────────────────────────────────────────────────────────┐
│                    UCI Interface Layer                   │
│              (uci.cpp, engine_commands.cpp)             │
└─────────────────────────────────────────────────────────┘
                          ↓↑
┌─────────────────────────────────────────────────────────┐
│                  Controller Layer                        │
│            (engine_controller.cpp)                       │
└─────────────────────────────────────────────────────────┘
                          ↓↑
┌─────────────────────────────────────────────────────────┐
│                  Search Layer                            │
│  (search_engine.cpp, search.cpp, mcts.cpp)              │
└─────────────────────────────────────────────────────────┘
                          ↓↑
┌─────────────────────────────────────────────────────────┐
│                  Game Logic Layer                        │
│  (position.cpp, movegen.cpp, rule.cpp)                  │
└─────────────────────────────────────────────────────────┘
                          ↓↑
┌─────────────────────────────────────────────────────────┐
│                  Data Layer                              │
│  (bitboard.cpp, tt.cpp, opening_book.cpp)               │
└─────────────────────────────────────────────────────────┘
                          ↓↑
┌─────────────────────────────────────────────────────────┐
│                External Services                         │
│  (Perfect DB, Evaluation, Utilities)                     │
└─────────────────────────────────────────────────────────┘
```

## Core Components

### 1. UCI Interface Layer

**Purpose**: Communication bridge between GUI and engine

**Key Files**:
- `uci.h` / `uci.cpp` - UCI protocol implementation
- `engine_commands.h` / `engine_commands.cpp` - Command parsing and execution

**Responsibilities**:
- Parse UCI commands from GUI
- Send responses to GUI
- Manage engine options
- Handle initialization and shutdown

**Communication Pattern**: Line-based text protocol
- Input: Commands from GUI (e.g., `position`, `go`, `setoption`)
- Output: Responses to GUI (e.g., `bestmove`, `info`, `option`)

### 2. Controller Layer

**Purpose**: Coordinate engine operations and maintain engine state

**Key Files**:
- `engine_controller.h` / `engine_controller.cpp` - Engine controller

**Responsibilities**:
- Handle command dispatch
- Maintain engine state (ready, searching, etc.)
- Coordinate position setup and search execution

**Pattern**: Command pattern with controller as mediator

### 3. Search Layer

**Purpose**: Implement game tree search algorithms to find best moves

**Key Files**:
- `search_engine.h` / `search_engine.cpp` - Search coordination
- `search.h` / `search.cpp` - Alpha-Beta and PVS algorithms
- `mcts.h` / `mcts.cpp` - Monte Carlo Tree Search
- `movepick.h` / `movepick.cpp` - Move ordering

**Responsibilities**:
- Execute search algorithms
- Manage search depth and time limits
- Handle search interruption and timeout
- Coordinate with transposition table
- Integrate perfect play database

**Algorithms Supported**:
1. **Alpha-Beta Pruning** (default)
   - Classic minimax with alpha-beta cutoffs
   - Best for tactical positions
   
2. **Principal Variation Search (PVS)**
   - Enhanced alpha-beta with zero-window searches
   - Better performance with good move ordering
   
3. **MTD(f)** (Memory-enhanced Test Driver)
   - Iterative deepening with zero-window searches
   - Requires transposition table
   - Faster convergence in some positions
   
4. **Monte Carlo Tree Search (MCTS)**
   - Simulation-based evaluation
   - Good for complex positions
   - Configurable simulation count
   
5. **Random Search**
   - For testing and weak opponent modes

### 4. Game Logic Layer

**Purpose**: Core game rules, move generation, and position management

**Key Files**:
- `position.h` / `position.cpp` - Board state representation
- `movegen.h` / `movegen.cpp` - Legal move generation
- `rule.h` / `rule.cpp` - Rule variants configuration
- `mills.h` / `mills.cpp` - Mill detection logic

**Responsibilities**:
- Represent board state (bitboards)
- Generate legal moves for each game phase
- Execute and undo moves
- Detect mills and game endings
- Manage game phases (placing, moving, flying)

**Game Phases**:
```
Ready → Placing → Moving → Game Over
                    ↓
                 Flying (when pieces ≤ threshold)
```

### 5. Data Layer

**Purpose**: Fast data structures and persistent data

**Key Files**:
- `bitboard.h` / `bitboard.cpp` - Bitboard operations
- `tt.h` / `tt.cpp` - Transposition table
- `opening_book.h` / `opening_book.cpp` - Opening database
- `hashmap.h` - Hash table implementation

**Responsibilities**:
- Bitboard manipulation (AND, OR, XOR, count bits)
- Transposition table probe/store
- Opening book lookups
- Position hashing

**Data Structures**:
- **Bitboard**: 32-bit representation of 24-square board
- **Transposition Table**: Hash table for position caching
- **Opening Book**: Map of FEN → best moves
- **Hash Keys**: Zobrist hashing for position identification

### 6. External Services

**Purpose**: Specialized services for evaluation and perfect play

**Key Files**:
- `evaluate.h` / `evaluate.cpp` - Position evaluation
- `perfect/` - Perfect play database system
- `opening_book.cpp` - Opening move database
- `self_play.h` / `self_play.cpp` - Training data generation

**Responsibilities**:
- Static position evaluation
- Perfect play database queries
- Opening move lookups
- Training data generation for NNUE

## Data Flow

### Move Search Flow

```
1. GUI sends "go" command
   ↓
2. UCI::loop() parses command
   ↓
3. EngineController::handleCommand() processes
   ↓
4. SearchEngine::runSearch() initiates search
   ↓
5. Iterative Deepening loop (if enabled)
   ↓
6. For each depth:
   a. Check opening book (if enabled)
   b. Search::search() or Search::MTDF()
   c. Position::do_move() / Position::undo_move()
   d. Evaluate::evaluate() at leaf nodes
   e. TranspositionTable::probe() / store()
   ↓
7. Check perfect database (if available)
   ↓
8. Select best move
   ↓
9. Send "bestmove" to GUI
```

### Position Update Flow

```
1. GUI sends "position" command
   ↓
2. UCI parses FEN string or move list
   ↓
3. Position::set(fen) initializes board
   ↓
4. For each move in list:
   a. Parse move notation
   b. Validate move legality
   c. Position::do_move()
   d. Update position hash
   e. Check game ending
   ↓
5. Position ready for search
```

## Key Design Patterns

### 1. Singleton Pattern
**Used in**: Options, TranspositionTable
**Reason**: Global state that should have single instance

### 2. Strategy Pattern
**Used in**: Search algorithms (Alpha-Beta, MTD(f), MCTS)
**Reason**: Interchangeable search strategies

### 3. Command Pattern
**Used in**: UCI command handling
**Reason**: Encapsulate requests as objects

### 4. Flyweight Pattern
**Used in**: Move representation (32-bit encoded)
**Reason**: Minimize memory footprint

### 5. Template Method Pattern
**Used in**: Search framework (IDS, aspiration windows)
**Reason**: Define algorithm skeleton with customizable steps

## Memory Management

### Stack Allocation
- Position objects (auto-allocated in search tree)
- Small temporary data structures
- **Performance**: Fast allocation/deallocation

### Heap Allocation
- Transposition table (large, persistent)
- Opening book data
- Search stack (if needed)
- **Performance**: Longer lifetime, shared across searches

### Memory Layout
```
Stack (per search):
├── Position stack (~50 positions × 200 bytes = 10 KB)
├── Search local variables (~10 KB)
└── Move arrays (~5 KB)

Heap (persistent):
├── Transposition table (~16-256 MB configurable)
├── Opening book data (~1-10 MB)
└── Perfect database (if loaded, ~100+ MB)

Total typical: ~50-300 MB depending on configuration
```

## Thread Model

### Current Implementation: Single-Threaded

The engine is primarily single-threaded for simplicity and debugging:
- Main thread handles UCI communication and search
- No lock contention or synchronization overhead
- Deterministic behavior for testing

### Concurrency Points

**Thread-Safe Components**:
- UCI I/O (can be on separate thread)
- Time management (timeout checks)

**Not Thread-Safe**:
- Position state
- Search state
- Transposition table (single-threaded access)

### Future Multi-Threading (Planned)

```
Main Thread (UCI)
   ↓
   ├─→ Search Thread 1 (root)
   ├─→ Search Thread 2 (helper)
   └─→ Search Thread N (helper)
   
Shared:
- Transposition Table (with locks)
- Global abort flag (atomic)
- Best move accumulator (mutex)
```

## Performance Characteristics

### Time Complexity

**Search Algorithms**:
- Alpha-Beta: O(b^d) where b = branching factor (~30), d = depth
- MTD(f): O(b^d) but with fewer nodes than Alpha-Beta
- MCTS: O(n × d) where n = simulations, d = avg depth

**Position Operations**:
- do_move(): O(1) - bitboard operations
- legal_move_generation(): O(m) where m = legal moves (~5-30)
- mill_detection(): O(1) - precomputed mill table

### Space Complexity

**Per Position**: ~200 bytes
- Bitboards: 3 × 4 bytes = 12 bytes
- State info: ~50 bytes
- History: ~138 bytes

**Search Stack**: depth × 200 bytes
- Depth 8: ~1.6 KB
- Depth 12: ~2.4 KB

**Transposition Table**: Configurable (16-256 MB typical)

### Typical Performance

**Positions Evaluated per Second** (depth-dependent):
- Placing phase: ~100K-500K nodes/sec
- Moving phase: ~50K-200K nodes/sec
- Endgame: ~200K-1M nodes/sec

**Search Depth** (1 second per move):
- Opening: 6-8 plies
- Midgame: 8-10 plies
- Endgame: 10-14 plies
- Perfect DB: Instant (if in database)

## Configuration and Options

### Engine Options (UCI)

```cpp
// Configurable via "setoption" command
option("Algorithm", 1);              // 1=Alpha-Beta, 2=MTD(f), 3=MCTS
option("DrawOnHumanExperience", true);
option("ConsiderMobility", true);
option("DeveloperMode", false);
option("SkillLevel", 10);            // 1-10
option("MoveTime", 1000);            // milliseconds
option("Depth", 8);                  // plies
option("PerfectDatabase", true);
// ... more options
```

### Build-Time Configuration

**Makefile flags**:
```makefile
TRANSPOSITION_TABLE_ENABLE    # Enable TT caching
OPENING_BOOK                  # Enable opening book
GABOR_MALOM_PERFECT_AI       # Enable perfect play DB
NNUE_GENERATE_TRAINING_DATA  # Generate NNUE training data
```

## Integration Points

### Flutter Integration

**Method Channel**: `com.calcitem.sanmill/engine`

**Commands**:
```dart
// Dart calls C++ via platform channel
engine.send("position fen ...");
engine.send("go depth 8");
String bestMove = await engine.receive();
```

**Data Flow**:
```
Flutter UI → MethodChannel → mill_engine.cpp → UCI parser → Engine
Engine → mill_engine.cpp → MethodChannel → Flutter UI
```

### Qt Integration (Legacy)

**Direct API calls**: Qt GUI directly calls engine functions
**Status**: Deprecated, use Flutter for new development

## Error Handling

### Philosophy
- **Fail-fast**: Use assertions for programming errors
- **No exceptions**: C++ code avoids try/catch
- **Graceful degradation**: Return safe defaults on recoverable errors

### Error Categories

**Programming Errors** (assertions):
```cpp
assert(depth > 0);
assert(move != MOVE_NONE);
assert(pos != nullptr);
```

**User Errors** (return codes):
```cpp
if (!valid_fen) return false;  // Invalid FEN string
if (illegal_move) return MOVE_NONE;
```

**System Errors** (handled at caller):
```cpp
if (!file_open) {
    // Continue without opening book
}
```

## Testing Strategy

### Unit Tests

**Location**: `tests/test_*.cpp`

**Coverage**:
- Position operations (do_move, undo_move)
- Move generation (all phases)
- Mill detection
- Rule validation
- Search algorithms (basic functionality)

### Integration Tests

**Perft Testing**: Verify move generation correctness
**Benchmark Suite**: Performance regression detection
**Perfect Play Verification**: Compare with perfect database

### Performance Testing

```bash
cd src
make bench           # Run benchmark suite
make profile         # Run with profiler
```

## Debugging and Profiling

### Debug Builds

```bash
cd src
make debug           # Build with debug symbols
gdb ./sanmill        # Debug with GDB
```

### Debug Output

```cpp
#ifdef DEBUG_MODE
debugPrintf("Search depth: %d, value: %d\n", depth, value);
#endif
```

### Profiling

```bash
# Linux/macOS
make profile
perf record ./sanmill
perf report

# Windows
# Use Visual Studio Profiler
```

## Future Enhancements

### Planned Features

1. **Multi-Threading**
   - Lazy SMP parallel search
   - Shared transposition table with locks

2. **NNUE Evaluation**
   - Neural network evaluation
   - Training data generation (partial implementation exists)

3. **Enhanced Opening Book**
   - Larger opening database
   - Learning from self-play

4. **Syzygy-Style Endgame Tables**
   - Compressed endgame databases
   - Faster probing

## References

### Internal Documentation
- [UCI Protocol](UCI_PROTOCOL.md) - UCI command reference
- [Components](CPP_COMPONENTS.md) - Component catalog
- [API Documentation](api/) - Detailed API docs
- [Workflows](CPP_WORKFLOWS.md) - Development workflows

### External References
- UCI Protocol (Chess): http://wbec-ridderkerk.nl/html/UCIProtocol.html
- Alpha-Beta Pruning: https://en.wikipedia.org/wiki/Alpha-beta_pruning
- MTD(f): https://people.csail.mit.edu/plaat/mtdf.html
- MCTS: https://en.wikipedia.org/wiki/Monte_Carlo_tree_search

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3

