#include "endgame.h"
#include "evaluate.h"
#include "mcts.h"
#include "movepick.h"
#include "option.h"
#include "uci.h"
#include "thread.h"

#if defined(GABOR_MALOM_PERFECT_AI)
#include "perfect_adaptor.h"
#endif

#include <fstream>

using Eval::evaluate;
using std::string;

// Forward declarations
Value MTDF(Position *pos, Sanmill::Stack<Position> &ss, Value firstguess,
           Depth depth, Depth originDepth, Move &bestMove);

Value pvs(Position *pos, Sanmill::Stack<Position> &ss, Depth depth,
          Depth originDepth, Value alpha, Value beta, Move &bestMove, int i,
          const Color before, const Color after);

Value search(Position *pos, Sanmill::Stack<Position> &ss, Depth depth,
             Depth originDepth, Value alpha, Value beta, Move &bestMove);

Value random_search(Position *pos, Move &bestMove);

bool is_timeout(TimePoint startTime);

#ifdef TRANSPOSITION_TABLE_ENABLE

/// OpeningBook namespace handles loading the opening book into the TT
namespace OpeningBook {

/// Initializes the opening book by loading from a file and storing entries in
/// TT
void init()
{
    // Load the opening book from a binary file
    std::ifstream bookFile("book.bin", std::ios::binary);
    if (!bookFile) {
        // Opening book file not found or cannot be opened
        // You can add error handling or logging here
        return;
    }

    Key key;
    Move move;
    int weight;
    while (bookFile.read(reinterpret_cast<char *>(&key), sizeof(Key))) {
        if (!bookFile.read(reinterpret_cast<char *>(&move), sizeof(Move))) {
            // Error reading move data
            break;
        }
        // Read the weight if available, default to 1 if not
        if (!bookFile.read(reinterpret_cast<char *>(&weight), sizeof(int))) {
            weight = 1;
        }
        // Save the move into the TT with a high depth and BOUND_EXACT
        // We can use a special value to indicate an opening book move
        Value value = VALUE_BOOK; // Define VALUE_BOOK as needed
        Depth depth = DEPTH_MAX;  // Use maximum depth to prioritize book moves
        Bound bound = BOUND_EXACT;

        // Save multiple times if weight > 1 to represent frequency
        for (int i = 0; i < weight; ++i) {
            TranspositionTable::save(value, depth, bound, key
#ifdef TT_MOVE_ENABLE
                                     ,
                                     move
#endif // TT_MOVE_ENABLE
            );
        }
    }

    bookFile.close();
}

/// Clears the opening book entries (optional since TT will be cleared)
void clear()
{
    // No action needed if TT is cleared elsewhere
}
} // namespace OpeningBook

#endif // TRANSPOSITION_TABLE_ENABLE

vector<Key> posKeyHistory;

/// Search::init() is called at startup
void Search::init() noexcept
{
#ifdef TRANSPOSITION_TABLE_ENABLE
    // Initialize the opening book by loading entries into TT
    OpeningBook::init();
#endif
}

/// Search::clear() resets search state to its initial value
void Search::clear()
{
    Threads.main()->wait_for_search_finished();

#ifdef TRANSPOSITION_TABLE_ENABLE
    TT.clear();
#endif
    Threads.clear();

    // OpeningBook::clear(); // Optional, TT is already cleared
}

#ifdef NNUE_GENERATE_TRAINING_DATA
extern Value nnueTrainingDataBestValue;
#endif /* NNUE_GENERATE_TRAINING_DATA */

/// Thread::search() is the main iterative deepening loop.
int Thread::search()
{
    Sanmill::Stack<Position> ss;

#if defined(GABOR_MALOM_PERFECT_AI)
    Move fallbackMove = MOVE_NONE;
    Value fallbackValue = VALUE_UNKNOWN;
#endif // GABOR_MALOM_PERFECT_AI

    Value value = VALUE_ZERO;
    const Depth d = get_depth();

    if (gameOptions.getAiIsLazy()) {
        const int np = bestvalue / VALUE_EACH_PIECE;
        if (np > 1) {
            if (d < 4) {
                originDepth = 1;
                sync_cout << "Lazy Mode: depth = " << originDepth << sync_endl;
            } else {
                originDepth = 4;
                sync_cout << "Lazy Mode: depth = " << originDepth << sync_endl;
            }
        } else {
            originDepth = d;
        }
    } else {
        originDepth = d;
    }

    const time_t time0 = time(nullptr);
    srand(static_cast<unsigned int>(time0));

#ifdef TIME_STAT
    auto timeStart = std::chrono::steady_clock::now();
    std::chrono::steady_clock::time_point timeEnd;
#endif
#ifdef CYCLE_STAT
    auto cycleStart = stopwatch::rdtscp_clock::now();
    std::chrono::steady_clock::time_point cycleEnd;
#endif

    bool isMovingOrMayMoveInPlacing = (rootPos->get_phase() == Phase::moving) ||
                                      (rootPos->get_phase() == Phase::placing &&
                                       rule.mayMoveInPlacingPhase);

    if (isMovingOrMayMoveInPlacing) {
#ifdef RULE_50
        if (posKeyHistory.size() >= rule.nMoveRule) {
            return 50;
        }

        if (rule.endgameNMoveRule < rule.nMoveRule &&
            rootPos->is_three_endgame() &&
            posKeyHistory.size() >= rule.endgameNMoveRule) {
            return 10;
        }
#endif // RULE_50

        if (rule.threefoldRepetitionRule && rootPos->has_game_cycle()) {
            return 3;
        }

        assert(posKeyHistory.size() < 256);
    }

    if (rootPos->get_phase() == Phase::placing && !rule.mayMoveInPlacingPhase) {
        posKeyHistory.clear();
        rootPos->st.rule50 = 0;
    } else if (isMovingOrMayMoveInPlacing) {
        rootPos->st.rule50 = static_cast<unsigned>(posKeyHistory.size());
    }

    MoveList<LEGAL>::shuffle();

    Value alpha = VALUE_NONE;
    Value beta = VALUE_NONE;

    if (gameOptions.getAlgorithm() != 2 /* !MTD(f) */) {
        alpha = -VALUE_INFINITE;
        beta = VALUE_INFINITE;
    }

    // Probe the TT at the root position for an opening book move
#ifdef TRANSPOSITION_TABLE_ENABLE
    Move ttMove = MOVE_NONE;
    Bound bound = BOUND_NONE;
    Value ttValue = TranspositionTable::probe(rootPos->key(), DEPTH_MAX, bound
#ifdef TT_MOVE_ENABLE
                                              ,
                                              ttMove
#endif // TT_MOVE_ENABLE
    );

    if (ttValue == VALUE_BOOK && bound == BOUND_EXACT && ttMove != MOVE_NONE) {
        // Found an opening book move in TT
        bestMove = ttMove;
        aiMoveType = AiMoveType::book;
        debugPrintf("Opening book move found in TT: %s\n",
                    UCI::move(bestMove).c_str());
        return 0;
    }
#endif // TRANSPOSITION_TABLE_ENABLE

    // Rest of the search code remains unchanged...

    if (gameOptions.getMoveTime() > 0 || gameOptions.getIDSEnabled()) {
        debugPrintf("IDS: ");

        constexpr Depth depthBegin = 2;
        Value lastValue = VALUE_ZERO;

        const TimePoint startTime = now();

        for (Depth i = depthBegin; i < originDepth; i += 1) {
#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef CLEAR_TRANSPOSITION_TABLE
            TranspositionTable::clear();
#endif
#endif

            if (gameOptions.getAlgorithm() == 2 /* MTD(f) */) {
                // MTD(f) algorithm
                value = MTDF(rootPos, ss, value, i, i, bestMove);
            } else if (gameOptions.getAlgorithm() == 3 /* MCTS */) {
                value = monte_carlo_tree_search(rootPos, bestMove);
            } else if (gameOptions.getAlgorithm() == 4 /* Random */) {
                value = random_search(rootPos, bestMove);
            } else {
                value = ::search(rootPos, ss, i, i, alpha, beta, bestMove);
            }

#if defined(GABOR_MALOM_PERFECT_AI)
            fallbackMove = bestMove;
            fallbackValue = value;
#endif // GABOR_MALOM_PERFECT_AI
            aiMoveType = AiMoveType::traditional;

            debugPrintf("Algorithm bestMove = %s\n",
                        UCI::move(bestMove).c_str());

#if defined(GABOR_MALOM_PERFECT_AI)
            if (gameOptions.getUsePerfectDatabase() == true) {
                value = perfect_search(rootPos, bestMove);
                if (value != VALUE_UNKNOWN) {
                    debugPrintf("perfect_search OK.\n");
                    debugPrintf("DB bestMove = %s\n",
                                UCI::move(bestMove).c_str());
                    if (bestMove == fallbackMove) {
                        aiMoveType = AiMoveType::consensus;
                    } else {
                        aiMoveType = AiMoveType::perfect;
                    }
                    goto next;
                } else {
                    debugPrintf("perfect_search failed.\n");
                    bestMove = fallbackMove;
                    value = fallbackValue;
                    aiMoveType = AiMoveType::traditional;
                }
            }
#endif // GABOR_MALOM_PERFECT_AI

#if defined(GABOR_MALOM_PERFECT_AI)
next:
#endif // GABOR_MALOM_PERFECT_AI

            debugPrintf("%d(%d) ", value, value - lastValue);

            lastValue = value;

            if (is_timeout(startTime)) {
                debugPrintf("originDepth = %d, depth = %d\n", originDepth, i);
                goto out;
            }
        }

#ifdef TIME_STAT
        timeEnd = std::chrono::steady_clock::now();
        sync_cout << "\nIDS Time: "
                  << std::chrono::duration_cast<std::chrono::seconds>(timeEnd -
                                                                      timeStart)
                         .count()
                  << "s\n";
#endif
    }

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef CLEAR_TRANSPOSITION_TABLE
    TranspositionTable::clear();
#endif
#endif

    if (gameOptions.getAlgorithm() != 2 /* !MTD(f) */
        && gameOptions.getIDSEnabled()) {
        alpha = -VALUE_INFINITE;
        beta = VALUE_INFINITE;
    }

    if (gameOptions.getAlgorithm() == 2 /* MTD(f) */) {
        value = MTDF(rootPos, ss, value, originDepth, originDepth, bestMove);
    } else if (gameOptions.getAlgorithm() == 3 /* MCTS */) {
        value = monte_carlo_tree_search(rootPos, bestMove);
    } else if (gameOptions.getAlgorithm() == 4 /* Random */) {
        value = random_search(rootPos, bestMove);
    } else {
        value = ::search(rootPos, ss, d, originDepth, alpha, beta, bestMove);
    }

#if defined(GABOR_MALOM_PERFECT_AI)
    fallbackMove = bestMove;
    fallbackValue = value;
#endif // GABOR_MALOM_PERFECT_AI
    aiMoveType = AiMoveType::traditional;

    debugPrintf("Algorithm bestMove = %s\n", UCI::move(bestMove).c_str());

#if defined(GABOR_MALOM_PERFECT_AI)
    if (gameOptions.getUsePerfectDatabase() == true) {
        value = perfect_search(rootPos, bestMove);
        if (value != VALUE_UNKNOWN) {
            debugPrintf("perfect_search OK.\n");
            debugPrintf("DB bestMove = %s\n", UCI::move(bestMove).c_str());
            if (bestMove == fallbackMove) {
                aiMoveType = AiMoveType::consensus;
            } else {
                aiMoveType = AiMoveType::perfect;
            }
            goto out;
        } else {
            debugPrintf("perfect_search failed.\n");
            bestMove = fallbackMove;
            value = fallbackValue;
            aiMoveType = AiMoveType::traditional;
        }
    }
#endif // GABOR_MALOM_PERFECT_AI

out:

#ifdef TIME_STAT
    timeEnd = std::chrono::steady_clock::now();
    auto duration = timeEnd - timeStart;
    if (std::chrono::duration_cast<std::chrono::seconds>(duration).count() >
        100) {
        debugPrintf(
            "Total Time: %llu s\n",
            std::chrono::duration_cast<std::chrono::seconds>(duration).count());
    } else {
        debugPrintf(
            "Total Time: %llu ms\n",
            std::chrono::duration_cast<std::chrono::milliseconds>(duration)
                .count());
    }
#endif

    lastvalue = bestvalue;
    bestvalue = value;

    return 0;
}

// Rest of the code remains unchanged...
