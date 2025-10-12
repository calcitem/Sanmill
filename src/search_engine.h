// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// search_engine.h

#ifndef SEARCH_ENGINE_H_INCLUDED
#define SEARCH_ENGINE_H_INCLUDED

#include "config.h"

#include <string>
#include <functional>
#include <atomic>
#include <mutex>
#include <condition_variable>
#ifdef QT_GUI_LIB
#include <QObject>
#endif
#include "position.h"
#include "misc.h"

/// Search Engine
///
/// Core class responsible for coordinating game tree search and move selection.
/// Integrates multiple search algorithms (Alpha-Beta, MTD(f), MCTS), manages
/// search state, and coordinates with transposition table and perfect databases.
///
/// **Thread Safety**: Not thread-safe - use separate instance per thread or
/// synchronize access with mutexes.
///
/// **Lifecycle**: Create → setRootPosition → runSearch → get results
///
/// @note This is a coordinator class, actual search algorithms are in Search namespace
/// @see Search::search(), Search::MTDF(), Search::random_search()
class SearchEngine
#ifdef QT_GUI_LIB
    : public QObject
#endif
{
#ifdef QT_GUI_LIB
    Q_OBJECT
#endif

public:
    /// Constructor
    ///
    /// @param parent  Qt parent object (Qt GUI only)
    explicit SearchEngine(
#ifdef QT_GUI_LIB
        QObject *parent = nullptr
#endif
    );

    // ========================================================================
    // Public Methods
    // ========================================================================

    /// Emit command to GUI (Qt or platform channel)
    ///
    /// Sends the best move command to the GUI for display and execution.
    void emitCommand();

    /// Emit analysis result to GUI
    ///
    /// Sends analysis information to GUI for display.
    void emitAnalyze();

    /// Get next move as UCI string
    ///
    /// @return  Best move in UCI notation (e.g., "a1b2")
    std::string next_move() const;

    /// Analyze position for given color
    ///
    /// @param c  Color to analyze for
    void analyze(Color c) const;

    /// Get configured search depth
    ///
    /// @return  Depth in plies (half-moves)
    Depth get_depth() const;

    /// Execute search algorithm
    ///
    /// Low-level search execution. Called by runSearch().
    ///
    /// @return  Status code (implementation-defined)
    /// @note Prefer runSearch() over this for normal usage
    int executeSearch();

    /// Get evaluation as string
    ///
    /// @return  Evaluation value as string
    std::string get_value() const;

    /// Set root position for search
    ///
    /// @param p  Pointer to position (must remain valid during search)
    /// @note Position is not copied - pointer must stay valid
    void setRootPosition(Position *p);

    /// Get best move as string
    ///
    /// @return  Best move in UCI notation
    std::string getBestMoveString() const;

    /// Set best move from string
    ///
    /// @param move  Move in UCI notation
    void setBestMoveString(const std::string &move);

    /// Look up best move from opening book
    ///
    /// Sets bestMove and bestMoveString if position found in book.
    void getBestMoveFromOpeningBook();

    /// Initialize new search session
    ///
    /// Prepares engine for new search, resets abort flag, assigns unique ID.
    ///
    /// @param p  Root position for search
    /// @return   Unique search ID for tracking
    uint64_t beginNewSearch(Position *p);

    /// Initialize new analysis session
    ///
    /// Prepares engine for position analysis.
    ///
    /// @param p  Position to analyze
    /// @return   Unique analysis ID for tracking
    uint64_t beginNewAnalyze(Position *p);

    /// Execute search and find best move
    ///
    /// Main entry point for move search. Blocks until search completes
    /// or is aborted.
    ///
    /// **Preconditions**: Root position set via setRootPosition() or beginNewSearch()
    ///
    /// **Search Process**:
    /// 1. Check opening book (if enabled)
    /// 2. Execute iterative deepening (if enabled)
    /// 3. Run selected search algorithm
    /// 4. Query perfect database (if available)
    /// 5. Store best move and evaluation
    ///
    /// **Side Effects**:
    /// - Updates bestMove and bestvalue
    /// - May emit signals (Qt GUI)
    /// - Blocks calling thread
    ///
    /// @note This is a blocking call - consider running in separate thread
    void runSearch();

    /// Execute position analysis
    ///
    /// Analyzes position and generates evaluation report.
    void runAnalyze();

    // ========================================================================
    // Public Data Members
    // ========================================================================

    /// Root position for search
    ///
    /// Pointer to the position to search from. Must remain valid during search.
    /// Set via setRootPosition() or beginNewSearch().
    Position *rootPos {nullptr};

    /// Check if search time limit exceeded
    ///
    /// @param startTime  Search start timestamp
    /// @return           true if allocated time exceeded
    /// @note Called periodically during search (~every 1000 nodes)
    bool is_timeout(TimePoint startTime);

    // ========================================================================
    // Atomic Flags and Synchronization
    // ========================================================================

    /// Search abort flag
    ///
    /// Set to true to interrupt ongoing search. Search will terminate
    /// gracefully at next check point (~1000 nodes).
    ///
    /// @note Thread-safe: can be set from any thread
    std::atomic_bool searchAborted {false};

    /// Analysis in progress flag
    ///
    /// Indicates whether analysis is currently running.
    std::atomic_bool analyzeInProgress {false};

    /// Current search unique identifier
    ///
    /// Unique ID for tracking searches, increments with each new search.
    std::atomic<uint64_t> currentSearchId {0};

    /// Current analysis unique identifier
    std::atomic<uint64_t> currentAnalyzeId {0};

    /// Search start timestamp
    ///
    /// Recorded when search begins, used for timeout calculations.
    TimePoint searchStartTime;

    // ========================================================================
    // Search Results
    // ========================================================================

    /// Original search depth requested
    ///
    /// May differ from actual depth reached if search was time-limited
    /// or aborted early.
    Depth originDepth {0};

    /// Best move found by search
    ///
    /// Set by search algorithm. MOVE_NONE if no legal moves or search
    /// not completed.
    Move bestMove {MOVE_NONE};

    /// Evaluation of best move
    ///
    /// Centipawn evaluation from side-to-move perspective.
    /// Positive = advantage, negative = disadvantage.
    Value bestvalue {VALUE_ZERO};

    /// Previous iteration's evaluation
    ///
    /// Used for aspiration windows in iterative deepening.
    Value lastvalue {VALUE_ZERO};

    /// Source of best move
    ///
    /// Indicates whether move came from search algorithm, perfect database,
    /// or both (consensus).
    AiMoveType aiMoveType {AiMoveType::unknown};

    /// Best move as UCI string
    ///
    /// String representation of best move (e.g., "a1b2").
    std::string bestMoveString;

    /// Analysis result string
    ///
    /// Detailed analysis information for display.
    std::string analyzeResult;

    // ========================================================================
    // Synchronization Primitives
    // ========================================================================

    /// Mutex for best move access
    ///
    /// Protects bestMove and bestMoveString from concurrent access.
    std::mutex bestMoveMutex;

    /// Condition variable for best move notification
    std::condition_variable bestMoveCV;

    /// Best move ready flag
    ///
    /// Set when best move is available, used with bestMoveCV.
    bool bestMoveReady {false};

    /// Mutex for analysis access
    std::mutex analyzeMutex;

    /// Condition variable for analysis notification
    std::condition_variable analyzeCV;

    /// Analysis ready flag
    bool analyzeReady {false};

#ifdef QT_GUI_LIB
signals:
    /// Signal that carries a command string (e.g., for AI moves)
    void command(const std::string &cmd, bool update);

    /// Signal that notifies listeners that the search has completed
    void searchCompleted();

    /// Signal that notifies listeners that the analyze has completed
    void analyzeCompleted();

    /// Signal that notifies listeners that the evaluation has completed
    void evaluationCompleted();
#endif

private:
    std::atomic<uint64_t> searchCounter {0};
    std::atomic<uint64_t> analyzeCounter {0};

#ifdef TIME_STAT
#ifdef QT_GUI_LIB
    TimePoint sortTime {0};
#endif
#endif

#ifdef CYCLE_STAT
    stopwatch::rdtscp_clock::time_point sortCycleStart;
    stopwatch::timer<std::chrono::system_clock>::duration sortCycleDuration {0};
    stopwatch::timer<std::chrono::system_clock>::period sortCyclePeriod;
#endif

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef TRANSPOSITION_TABLE_DEBUG
    size_t tteCount {0};
    size_t ttHitCount {0};
    size_t ttMissCount {0};
    size_t ttInsertNewCount {0};
    size_t ttAddrHitCount {0};
    size_t ttReplaceCozDepthCount {0};
    size_t ttReplaceCozHashCount {0};
#endif // TRANSPOSITION_TABLE_DEBUG
#endif // TRANSPOSITION_TABLE_ENABLE
};

#endif // SEARCH_ENGINE_H_INCLUDED
