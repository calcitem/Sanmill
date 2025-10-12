# Sanmill C++ Engine Component Catalog

## Overview

This document provides a comprehensive catalog of all C++ components in the Sanmill engine. Components are organized by functional category to help developers (human and AI) quickly locate and understand the building blocks of the engine.

## Component Categories

- [Core Game Components](#core-game-components)
- [Search Components](#search-components)
- [Data Structures](#data-structures)
- [Utilities](#utilities)
- [Interface Components](#interface-components)
- [Perfect Play System](#perfect-play-system)

---

## Core Game Components

### Position

**Location**: `src/position.h`, `src/position.cpp`

**Purpose**: Core class representing the game board state and managing move execution

**Key Responsibilities**:
- Bitboard-based piece tracking (white, black, banned squares)
- Move execution (do_move) and retraction (undo_move)
- Mill detection and counting
- Game phase management (placing, moving, flying, game over)
- FEN string parsing and generation
- Game ending detection (win/loss/draw conditions)

**Public API** (Selected methods):
- `set(fen)`: Initialize position from FEN string
- `fen()`: Export position to FEN string
- `do_move(move)`: Execute a move
- `undo_move(stack)`: Retract last move
- `legal(move)`: Check if move is legal
- `side_to_move()`: Get current player
- `get_phase()`: Get current game phase
- `mills_count(square)`: Count mills through square
- `is_all_in_mills(color)`: Check if all pieces in mills

**Dependencies**: Bitboard, Rule, MoveGen, Stack

**Usage Context**: Central to all game operations

**Performance**: Critical path - optimized with bitboards

**See Also**: [Position API Documentation](api/Position.md)

---

### MoveGen

**Location**: `src/movegen.h`, `src/movegen.cpp`

**Purpose**: Generate legal moves for the current position

**Key Responsibilities**:
- Generate placing phase moves (empty squares)
- Generate moving phase moves (adjacent empty squares)
- Generate flying phase moves (any empty square)
- Generate removal moves (opponent pieces, preferably not in mills)
- Filter illegal moves

**Public API**:
- `generate<LEGAL>(pos, moves)`: Generate all legal moves
- `generate_moves(pos)`: Generate moves for current phase

**Dependencies**: Position, Bitboard

**Usage Context**: Called by search algorithms for move iteration

**Performance**: Medium criticality - called frequently in search

---

### Rule

**Location**: `src/rule.h`, `src/rule.cpp`

**Purpose**: Define and manage game rule variants

**Key Responsibilities**:
- Store rule configurations (piece count, flying rules, mill actions)
- Provide rule presets (Nine Men's Morris, Twelve Men's Morris, etc.)
- Rule selection and validation

**Data Structure**:
```cpp
struct Rule {
    char name[32];
    char description[512];
    int pieceCount;              // Pieces per player
    int flyPieceCount;           // Flying threshold
    bool hasDiagonalLines;       // Board topology
    MillFormationActionInPlacingPhase millFormationActionInPlacingPhase;
    bool mayFly;                 // Flying allowed
    // ... 20+ more configuration fields
};
```

**Global Variables**:
- `RULES[N_RULES]`: Array of predefined rule variants
- `rule`: Currently active rule

**Public API**:
- `set_rule(index)`: Select rule variant by index

**Dependencies**: None (pure data)

**Usage Context**: Loaded at startup, consulted during gameplay

**See Also**: [Rule System Guide](RULE_SYSTEM_GUIDE.md)

---

### Mills

**Location**: `src/mills.h`, `src/mills.cpp`

**Purpose**: Mill (three-in-a-row) detection and manipulation

**Key Responsibilities**:
- Precomputed mill tables (which squares form mills)
- Mill detection for a given position
- Mill counting for evaluation

**Data Structures**:
- Mill lookup tables (constexpr arrays)
- Mill masks for bitboard operations

**Public API**:
- Mill detection functions (used internally by Position)

**Dependencies**: Bitboard

**Usage Context**: Used by Position for mill detection

**Performance**: Very critical - uses precomputed tables

---

## Search Components

### SearchEngine

**Location**: `src/search_engine.h`, `src/search_engine.cpp`

**Purpose**: Coordinate game tree search and move selection

**Key Responsibilities**:
- Manage search state (root position, best move, search depth)
- Execute iterative deepening search
- Integrate different search algorithms
- Handle search interruption and timeout
- Coordinate with transposition table
- Integrate perfect play database

**Public API**:
- `setRootPosition(pos)`: Set position to search from
- `runSearch()`: Execute search and find best move
- `getBestMove()`: Retrieve best move found
- `getBestValue()`: Retrieve evaluation of best move
- `get_depth()`: Get current search depth
- `abort()`: Interrupt ongoing search

**Dependencies**: Position, Search namespace, TranspositionTable, OpeningBook

**Usage Context**: Primary interface for AI move generation

**Performance**: Critical - coordinates all search activity

**See Also**: [SearchEngine API Documentation](api/SearchEngine.md)

---

### Search Namespace

**Location**: `src/search.h`, `src/search.cpp`

**Purpose**: Implement game tree search algorithms

**Key Responsibilities**:
- Alpha-Beta pruning search
- Principal Variation Search (PVS)
- MTD(f) search
- Quiescence search
- Random search (for testing)

**Public API**:
```cpp
namespace Search {
    Value search(SearchEngine &, Position*, Stack<Position>&, 
                 Depth, Depth, Value alpha, Value beta, Move &bestMove);
    
    Value MTDF(SearchEngine &, Position*, Stack<Position>&,
               Value firstguess, Depth, Depth, Move &bestMove);
    
    Value pvs(SearchEngine &, Position*, Stack<Position>&,
              Depth, Depth, Value alpha, Value beta, Move &, int, Color, Color);
    
    Value qsearch(SearchEngine &, Position*, Stack<Position>&,
                  Depth, Depth, Value alpha, Value beta, Move &);
    
    Value random_search(Position*, Move &);
}
```

**Dependencies**: Position, SearchEngine, Evaluate, TranspositionTable

**Usage Context**: Called by SearchEngine to perform actual search

**Performance**: Ultra-critical - most CPU time spent here

**See Also**: [Search Algorithms Documentation](api/Search.md)

---

### MCTS

**Location**: `src/mcts.h`, `src/mcts.cpp`

**Purpose**: Monte Carlo Tree Search implementation

**Key Responsibilities**:
- Build search tree through simulations
- UCB1 formula for node selection
- Random playout for evaluation
- Backpropagation of results

**Public API**:
- `monte_carlo_tree_search(pos, bestMove)`: Execute MCTS

**Dependencies**: Position

**Usage Context**: Alternative search algorithm (selectable)

**Performance**: Medium - fewer nodes than Alpha-Beta but more overhead

---

### MovePick

**Location**: `src/movepick.h`, `src/movepick.cpp`

**Purpose**: Move ordering for search efficiency

**Key Responsibilities**:
- Order moves by likelihood of being best
- Prioritize hash move, captures, quiet moves
- Use history heuristic for move ordering

**Public API**:
- Move ordering functions (used internally by search)

**Dependencies**: Position, Move

**Usage Context**: Called during move generation in search

**Performance**: Important for search efficiency

---

### Evaluate

**Location**: `src/evaluate.h`, `src/evaluate.cpp`

**Purpose**: Static position evaluation

**Key Responsibilities**:
- Calculate material balance
- Evaluate mobility (available moves)
- Assess mill potential
- Consider board control

**Public API**:
- `evaluate(pos)`: Return position evaluation score

**Dependencies**: Position

**Usage Context**: Called at leaf nodes of search tree

**Performance**: High frequency calls - should be fast

---

## Data Structures

### Bitboard

**Location**: `src/bitboard.h`, `src/bitboard.cpp`

**Purpose**: Efficient bit-level board representation

**Key Responsibilities**:
- Bitwise operations (AND, OR, XOR, NOT)
- Bit counting (population count)
- Bit manipulation (set, clear, test)
- Square-to-bit mapping

**Type Definition**:
```cpp
using Bitboard = uint32_t;  // 32 bits for 24-square board + metadata
```

**Public API**:
- `sq_bb(square)`: Get bitboard with single bit set
- `more_than_one(bb)`: Check if multiple bits set
- `popcount(bb)`: Count set bits
- `lsb(bb)`: Get least significant bit

**Dependencies**: None (low-level primitive)

**Usage Context**: Used by Position for piece tracking

**Performance**: Ultra-critical - many operations per move

---

### TranspositionTable

**Location**: `src/tt.h`, `src/tt.cpp`

**Purpose**: Cache evaluated positions to avoid re-computation

**Key Responsibilities**:
- Store position evaluations with depth and bounds
- Probe cache for previously evaluated positions
- Handle hash collisions
- Age old entries

**Data Structure**:
```cpp
struct TTEntry {
    Key key;           // Position hash (partial)
    Value value;       // Evaluation score
    Depth depth;       // Search depth
    // ... more fields
};
```

**Public API**:
- `probe(key)`: Look up position in table
- `store(key, value, depth, ...)`: Save evaluation
- `clear()`: Clear entire table

**Dependencies**: Position (for key generation)

**Usage Context**: Used by search algorithms

**Performance**: Critical - can reduce search by 10x

---

### Stack

**Location**: `src/stack.h`

**Purpose**: Efficient stack data structure for position history

**Type Definition**:
```cpp
template<typename T>
class Stack {
    // Custom stack implementation
    // Optimized for Position objects
};
```

**Public API**:
- `push(item)`: Add item to stack
- `pop()`: Remove and return top item
- `top()`: Access top item without removal
- `size()`: Get stack size

**Dependencies**: None (generic template)

**Usage Context**: Store position history for undo operations

---

### HashMap

**Location**: `src/hashmap.h`

**Purpose**: Generic hash map implementation

**Type Definition**:
```cpp
template<typename Key, typename Value>
class HashMap {
    // Hash map implementation
};
```

**Public API**:
- `insert(key, value)`: Add key-value pair
- `find(key)`: Lookup value by key
- `erase(key)`: Remove entry

**Dependencies**: None (generic template)

**Usage Context**: Used for various lookup tables

---

## Utilities

### UCI

**Location**: `src/uci.h`, `src/uci.cpp`

**Purpose**: Implement UCI-like protocol for GUI communication

**Key Responsibilities**:
- Parse UCI commands from stdin
- Send UCI responses to stdout
- Manage engine options
- Handle position setup and search commands

**Public API**:
- `UCI::loop()`: Main UCI communication loop
- `UCI::move(move)`: Convert move to UCI notation
- `UCI::square(sq)`: Convert square to UCI notation

**Dependencies**: Position, SearchEngine, Options

**Usage Context**: Entry point for engine-GUI communication

**See Also**: [UCI Protocol Documentation](UCI_PROTOCOL.md)

---

### EngineController

**Location**: `src/engine_controller.h`, `src/engine_controller.cpp`

**Purpose**: High-level command handling and engine coordination

**Key Responsibilities**:
- Process UCI commands
- Maintain engine state
- Coordinate position updates and searches

**Public API**:
- `handleCommand(cmd, pos)`: Process a command string

**Dependencies**: SearchEngine, Position

**Usage Context**: Used by UCI loop and platform channels

---

### EngineCommands

**Location**: `src/engine_commands.h`, `src/engine_commands.cpp`

**Purpose**: Parse and execute individual UCI commands

**Key Responsibilities**:
- Parse command syntax
- Validate command parameters
- Execute command actions

**Public API**:
- Individual command handlers (position, go, setoption, etc.)

**Dependencies**: Position, SearchEngine

**Usage Context**: Called by EngineController

---

### Option

**Location**: `src/option.h`, `src/option.cpp`

**Purpose**: Manage engine configuration options

**Key Responsibilities**:
- Store option values (skill level, algorithm, time limits)
- Validate option values
- Provide option access to engine components

**Data Structure**:
```cpp
class GameOptions {
    int skillLevel;
    int algorithm;
    bool usePerfectDatabase;
    int moveTime;
    // ... more options
};
```

**Public API**:
- Getter/setter methods for each option
- Option registration for UCI

**Dependencies**: None

**Usage Context**: Global configuration accessed throughout engine

---

### Misc

**Location**: `src/misc.h`, `src/misc.cpp`

**Purpose**: Miscellaneous utility functions

**Key Responsibilities**:
- Time management (now(), elapsed time)
- String utilities
- Logging and debug output
- Platform-specific utilities

**Public API**:
- `now()`: Get current time
- `sync_cout/sync_endl`: Thread-safe console output
- `debugPrintf(...)`: Debug logging

**Dependencies**: Platform headers

**Usage Context**: Used throughout codebase

---

### OpeningBook

**Location**: `src/opening_book.h`, `src/opening_book.cpp`

**Purpose**: Opening move database for fast game starts

**Key Responsibilities**:
- Load opening book from file
- Query best opening moves
- Handle multiple book moves

**Public API**:
- `OpeningBook::probe(fen)`: Get opening moves for position

**Dependencies**: Position

**Usage Context**: Consulted before expensive searches

**Performance**: Very fast - simple lookup

---

## Interface Components

### Mill Engine (Flutter)

**Location**: `src/ui/flutter_app/command/mill_engine.h`, `mill_engine.cpp`

**Purpose**: Platform channel interface for Flutter integration

**Key Responsibilities**:
- Receive commands from Flutter
- Send responses back to Flutter
- Manage command queue
- Handle threading

**Public API**:
- Platform-specific channel methods

**Dependencies**: EngineController, Platform APIs

**Usage Context**: Bridge between Dart and C++

---

### Command Channel

**Location**: `src/ui/flutter_app/command/command_channel.h`, `command_channel.cpp`

**Purpose**: Command queuing and processing

**Key Responsibilities**:
- Queue incoming commands
- Process commands asynchronously
- Synchronize responses

**Public API**:
- `enqueue(command)`: Add command to queue
- `process()`: Process next command

**Dependencies**: EngineController

**Usage Context**: Used by platform channel

---

## Perfect Play System

### Perfect API

**Location**: `src/perfect/perfect_api.h`, `perfect_api.cpp`

**Purpose**: Interface to perfect play endgame databases

**Key Responsibilities**:
- Query perfect database for position
- Return exact game-theoretic value
- Handle database not found

**Public API**:
- `perfect_search(pos, bestMove)`: Query database

**Dependencies**: Perfect database files, Position

**Usage Context**: Called by SearchEngine for solved positions

**Performance**: Very fast - direct lookup

**Configuration**: Requires `GABOR_MALOM_PERFECT_AI` flag

---

### Perfect Database Components

**Location**: `src/perfect/` (multiple files)

**Components**:
- `perfect_game_state.h/.cpp` - Game state representation
- `perfect_player.h/.cpp` - Player logic
- `perfect_rules.h/.cpp` - Perfect play rules
- `perfect_hash.h` - Position hashing
- `perfect_adaptor.h/.cpp` - Adapter for Sanmill integration

**Purpose**: Complete perfect play system (ported from Gabor Malom)

**Status**: Advanced feature, optional compilation

---

## Thread Management

### Thread

**Location**: `src/thread.h`, `src/thread.cpp`

**Purpose**: Thread abstraction layer

**Key Responsibilities**:
- Platform-independent thread operations
- Thread creation and management
- Sleep and synchronization primitives

**Public API**:
- `Thread::create(fn)`: Create new thread
- `Thread::join()`: Wait for thread completion

**Dependencies**: Platform headers (pthread or Windows threads)

**Usage Context**: Placeholder for future multi-threading

---

### ThreadPool

**Location**: `src/thread_pool.h`, `src/thread_pool.cpp`

**Purpose**: Manage pool of worker threads

**Key Responsibilities**:
- Thread pool management
- Task queuing
- Work distribution

**Public API**:
- `ThreadPool::submit(task)`: Submit task to pool

**Dependencies**: Thread, TaskQueue

**Usage Context**: Future feature (not actively used)

---

### TaskQueue

**Location**: `src/task_queue.h`

**Purpose**: Thread-safe task queue

**Type Definition**:
```cpp
template<typename Task>
class TaskQueue {
    // Lock-based queue for tasks
};
```

**Public API**:
- `push(task)`: Add task
- `pop()`: Get next task
- `empty()`: Check if empty

**Dependencies**: Thread synchronization primitives

**Usage Context**: Used by ThreadPool

---

## Testing Components

### Benchmark

**Location**: `src/benchmark.h`, `src/benchmark.cpp`

**Purpose**: Performance benchmarking suite

**Key Responsibilities**:
- Run standard positions
- Measure search performance
- Compare with baseline
- Generate performance report

**Public API**:
- `benchmark()`: Run benchmark suite

**Dependencies**: Position, SearchEngine

**Usage Context**: Performance regression testing

---

### SelfPlay

**Location**: `src/self_play.h`, `src/self_play.cpp`

**Purpose**: Generate training data through self-play

**Key Responsibilities**:
- Play games between engine instances
- Record positions and outcomes
- Generate NNUE training data

**Public API**:
- `self_play()`: Run self-play session

**Dependencies**: Position, SearchEngine

**Usage Context**: NNUE training data generation

**Configuration**: Requires `NNUE_GENERATE_TRAINING_DATA` flag

---

## Endgame

**Location**: `src/endgame.h`, `src/endgame.cpp`

**Purpose**: Specialized endgame evaluation and handling

**Key Responsibilities**:
- Recognize special endgame positions
- Provide endgame-specific evaluations
- Handle theoretical draw recognition

**Public API**:
- `Endgame::probe(pos)`: Check for special endgames

**Dependencies**: Position

**Usage Context**: Called during position evaluation

---

## Configuration Files

### types.h

**Location**: `src/types.h`

**Purpose**: Central type definitions and constants

**Contents**:
- Enumerations (Color, Phase, Action, GameOverReason)
- Type aliases (Bitboard, Key, Move)
- Constants (MAX_MOVES, MAX_PLY, VALUE_*)
- Compiler and platform detection

**Dependencies**: None (included by all files)

**Usage Context**: Fundamental types used throughout codebase

---

### config.h

**Location**: `include/config.h`

**Purpose**: Build configuration and feature flags

**Contents**:
- Feature enable/disable macros
- Platform-specific settings
- Version information

**Dependencies**: None

**Usage Context**: Included by types.h, controls compilation

---

### debug.h

**Location**: `src/debug.h`

**Purpose**: Debug macros and utilities

**Contents**:
- Debug printf macros
- Assertion helpers
- Conditional compilation for debug features

**Dependencies**: None

**Usage Context**: Used throughout codebase for debugging

---

## Component Dependencies

### High-Level Dependency Graph

```
UCI/Platform Channels
        ↓
    EngineController
        ↓
    SearchEngine
        ↓
    Search Algorithms
        ↓
    Position ←→ MoveGen
        ↓
    Bitboard ← Rule
        
    TranspositionTable → Position (for hashing)
    Evaluate → Position
    OpeningBook → Position
    Perfect DB → Position
```

### Low-Level Dependencies

**No Dependencies (Primitives)**:
- types.h, config.h, debug.h
- bitboard.h
- rule.h
- stack.h, hashmap.h

**First Level (Use Primitives)**:
- position.h (uses Bitboard, Rule, Stack)
- movegen.h (uses Position, Bitboard)
- mills.h (uses Bitboard)

**Second Level (Use Position)**:
- search.h (uses Position)
- evaluate.h (uses Position)
- tt.h (uses Position for keys)
- opening_book.h (uses Position)

**Third Level (Use Search)**:
- search_engine.h (uses Search, Position)
- mcts.h (uses Position)

**Top Level (Interfaces)**:
- uci.h (uses SearchEngine, Position)
- engine_controller.h (uses SearchEngine, Position)

---

## Usage Patterns

### Creating and Managing Positions

```cpp
#include "position.h"

// Create position
Position pos;

// Initialize from FEN
pos.set("initial_fen_string");

// Make moves
Move move = /* generate or parse move */;
pos.do_move(move);

// Undo move
Sanmill::Stack<Position> history;
pos.undo_move(history);

// Query position
Color side = pos.side_to_move();
Phase phase = pos.get_phase();
bool legal = pos.legal(move);
```

### Running Search

```cpp
#include "search_engine.h"
#include "position.h"

// Create engine
SearchEngine engine;

// Set position
Position pos;
pos.set("fen_string");
engine.setRootPosition(&pos);

// Configure search
gameOptions.setDepth(8);

// Execute search
engine.runSearch();

// Get result
Move bestMove = engine.getBestMove();
Value eval = engine.getBestValue();
```

### Using UCI Interface

```cpp
#include "uci.h"

// Start UCI loop (blocks until "quit" command)
UCI::loop(argc, argv);

// Parse move
std::string move_str = "a1b2";
Move move = UCI::to_move(pos, move_str);

// Format move
std::string formatted = UCI::move(move);
```

---

## Performance-Critical Components

### Ultra-Critical (>40% CPU time)
1. **Search::search()** - Core search loop
2. **Position::do_move() / undo_move()** - Move execution
3. **Bitboard operations** - Low-level bit manipulation

### Critical (10-40% CPU time)
4. **MoveGen::generate_legal_moves()** - Move generation
5. **Position::is_all_in_mills()** - Mill detection
6. **Evaluate::evaluate()** - Position evaluation

### Important (1-10% CPU time)
7. **TranspositionTable::probe/store()** - Cache operations
8. **MovePick ordering** - Move sorting

**Performance Guidelines**:
- Avoid memory allocation in critical paths
- Use bitboard operations instead of loops
- Prefer stack allocation over heap
- Minimize function call overhead in hot paths

---

## Compilation Units

### Main Executable

**Entry Point**: `src/main.cpp`

**Linked Objects**:
```
main.o
position.o
bitboard.o
movegen.o
rule.o
mills.o
search_engine.o
search.o
mcts.o
evaluate.o
tt.o
uci.o
engine_controller.o
engine_commands.o
option.o
opening_book.o
misc.o
thread.o
thread_pool.o
benchmark.o
self_play.o
endgame.o
movepick.o
ucioption.o
+ perfect/*.o (if enabled)
```

**Output**: `sanmill` (or `sanmill.exe` on Windows)

---

## References

### Internal Documentation
- [C++ Architecture](CPP_ARCHITECTURE.md) - System architecture
- [API Documentation](api/) - Detailed API reference
- [UCI Protocol](UCI_PROTOCOL.md) - Communication protocol
- [Workflows](CPP_WORKFLOWS.md) - Development workflows

### Related Documentation
- [Flutter Components](../ui/flutter_app/docs/COMPONENTS.md) - Flutter component catalog
- [AGENTS.md](../../AGENTS.md) - AI agent guidelines

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3

