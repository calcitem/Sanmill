// search_engine.cpp

#include "search_engine.h"
#include "search.h"
#include "thread.h"
#include "uci.h"
#include "mills.h"
#include "mcts.h"
#include "perfect_api.h"
#include "tt.h"
#include "movegen.h"
#include <iostream>
#include <sstream>
#include <iomanip>
#include <string>

using std::string;

#ifdef FLUTTER_UI
#include "engine_main.h"
#endif

SearchEngine SearchEngine::instance;

SearchEngine::SearchEngine() { }

SearchEngine &SearchEngine::getInstance()
{
    return instance;
}

void SearchEngine::emitCommand()
{
    std::ostringstream ss;
    std::string aiMoveTypeStr;

    if (rootPos->side_to_move() == BLACK) {
        bestvalue = -bestvalue;
    }

    switch (aiMoveType) {
    case AiMoveType::traditional:
        aiMoveTypeStr = "";
        break;
    case AiMoveType::perfect:
        aiMoveTypeStr = " aimovetype perfect";
        break;
    case AiMoveType::consensus:
        aiMoveTypeStr = " aimovetype consensus";
        break;
    default:
        break;
    }

    ss << "info score " << static_cast<int>(bestvalue) << aiMoveTypeStr
       << " bestmove " << bestMoveString;

#ifdef QT_GUI_LIB
    emit thread->command(ss.str()); // Origin: bestMoveString
#else
    std::cout << ss.str() << std::endl;

#ifdef FLUTTER_UI
    println(ss.str().c_str());
#endif

#ifdef UCI_DO_BEST_MOVE
    rootPos->command(ss.str());
    thread->us = rootPos->side_to_move();

    if (bestMoveString.size() > strlen("-(1,2)")) {
        posKeyHistory.push_back(rootPos->key());
    } else {
        posKeyHistory.clear();
    }
#endif

#ifdef ANALYZE_POSITION
    analyze(rootPos->side_to_move());
#endif
#endif // QT_GUI_LIB
}

void SearchEngine::setRootPosition(Position *p)
{
    rootPos = p;

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef CLEAR_TRANSPOSITION_TABLE
    TranspositionTable::clear();
#endif
#endif
}

void SearchEngine::setBestMoveString(const std::string &move)
{
    bestMoveString = move;
}

std::string SearchEngine::getBestMoveString() const
{
    return bestMoveString;
}

void SearchEngine::getBestMoveFromOpeningBook()
{
#ifdef OPENING_BOOK
    bestMoveString = OpeningBook::get_best_move();
    emitCommand();
#endif
}

string SearchEngine::get_value() const
{
    string value = std::to_string(bestvalue);
    return value;
}

std::string SearchEngine::next_move() const
{
#ifdef ENDGAME_LEARNING
    // Check if very weak
    if (gameOptions.isEndgameLearningEnabled()) {
        if (bestvalue <= -VALUE_KNOWN_WIN) {
            Endgame endgame;
            endgame.type = rootPos->side_to_move() == WHITE ?
                               EndGameType::blackWin :
                               EndGameType::whiteWin;
            Key endgameHash = rootPos->key(); // TODO: Avoid repeated
                                              // hash generation
            saveEndgameHash(endgameHash, endgame);
        }
    }
#endif /* ENDGAME_LEARNING */

    if (gameOptions.getResignIfMostLose()) {
        if (bestvalue <= -VALUE_MATE) {
            rootPos->set_gameover(~rootPos->side_to_move(),
                                  GameOverReason::loseResign);
            snprintf(rootPos->record, Position::RECORD_LEN_MAX,
                     LOSE_REASON_PLAYER_RESIGNS, rootPos->side_to_move());
            return rootPos->record;
        }
    }

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef TRANSPOSITION_TABLE_DEBUG
    size_t hashProbeCount = thread->ttHitCount + thread->ttMissCount;
    if (hashProbeCount) {
        debugPrintf("[posKey] probe: %llu, hit: %llu, miss: %llu, hit rate: "
                    "%llu%%\n",
                    hashProbeCount, thread->ttHitCount, thread->ttMissCount,
                    thread->ttHitCount * 100 / hashProbeCount);
    }
#endif // TRANSPOSITION_TABLE_DEBUG
#endif // TRANSPOSITION_TABLE_ENABLE

    return UCI::move(bestMove);
}

void SearchEngine::analyze(Color c) const
{
#ifndef QT_GUI_LIB
    static float nWhiteWin = 0;
    static float nBlackWin = 0;
    static float nDraw = 0;

    float total;
    float blackWinRate, whiteWinRate, drawRate;
#endif // !QT_GUI_LIB

    const int d = originDepth;
    const int v = bestvalue;
    const int lv = lastvalue;
    const bool win = v >= VALUE_MATE;
    const bool lose = v <= -VALUE_MATE;
    const int np = v / VALUE_EACH_PIECE;

    const std::string strUs = (c == WHITE ? "White" : "Black");
    const std::string strThem = (c == WHITE ? "Black" : "White");

    const auto flags = std::cout.flags();

    debugPrintf("Depth: %d\n\n", originDepth);

    const Position *p = rootPos;

    std::cout << *p << std::endl;
    std::cout << std::dec;

    switch (p->get_phase()) {
    case Phase::ready:
        std::cout << "Ready phase" << std::endl;
        break;
    case Phase::placing:
        std::cout << "Placing phase" << std::endl;
        break;
    case Phase::moving:
        std::cout << "Moving phase" << std::endl;
        break;
    case Phase::gameOver:
        if (p->get_winner() == DRAW) {
            std::cout << "Draw" << std::endl;
#ifndef QT_GUI_LIB
            nDraw += 0.5f; // TODO: Implement properly
#endif
        } else if (p->get_winner() == WHITE) {
            std::cout << "White wins" << std::endl;
#ifndef QT_GUI_LIB
            nBlackWin += 0.5f; // TODO: Implement properly
#endif
        } else if (p->get_winner() == BLACK) {
            std::cout << "Black wins" << std::endl;
#ifndef QT_GUI_LIB
            nWhiteWin += 0.5f; // TODO: Implement properly
#endif
        }
        std::cout << std::endl << std::endl;
        return;
    case Phase::none:
        std::cout << "None phase" << std::endl;
        break;
    }

    if (v == VALUE_UNIQUE) {
        std::cout << "Unique move" << std::endl << std::endl << std::endl;
        return;
    }

    if (lv < -VALUE_EACH_PIECE && v == 0) {
        std::cout << strThem << " made a bad move, " << strUs
                  << " pulled back the balance of power!" << std::endl;
    }

    if (lv < 0 && v > 0) {
        std::cout << strThem << " made a bad move, " << strUs
                  << " reversed the situation!" << std::endl;
    }

    if (lv == 0 && v > VALUE_EACH_PIECE) {
        std::cout << strThem << " made a bad move!" << std::endl;
    }

    if (lv > VALUE_EACH_PIECE && v == 0) {
        std::cout << strThem
                  << " made a good move, pulled back the balance of power"
                  << std::endl;
    }

    if (lv > 0 && v < 0) {
        std::cout << strThem << " made a good move, reversed the situation!"
                  << std::endl;
    }

    if (lv == 0 && v < -VALUE_EACH_PIECE) {
        std::cout << strThem << " made a good move!" << std::endl;
    }

    if (lv != v) {
        if (lv < 0 && v < 0) {
            if (abs(lv) < abs(v)) {
                std::cout << strThem << " has expanded its lead" << std::endl;
            } else if (abs(lv) > abs(v)) {
                std::cout << strThem << " has narrowed its lead" << std::endl;
            }
        }

        if (lv > 0 && v > 0) {
            if (abs(lv) < abs(v)) {
                std::cout << strThem << " has expanded its lead" << std::endl;
            } else if (abs(lv) > abs(v)) {
                std::cout << strThem << " has narrowed its backwardness"
                          << std::endl;
            }
        }
    }

    if (win) {
        std::cout << strThem << " will lose in " << d << " moves!" << std::endl;
    } else if (lose) {
        std::cout << strThem << " will win in " << d << " moves!" << std::endl;
    } else if (np == 0) {
        std::cout << "The two sides will maintain a balance of power after "
                  << d << " moves" << std::endl;
    } else if (np > 0) {
        std::cout << strThem << " after " << d << " moves will backward " << np
                  << " pieces" << std::endl;
    } else if (np < 0) {
        std::cout << strThem << " after " << d << " moves will lead " << -np
                  << " pieces" << std::endl;
    }

    if (p->side_to_move() == WHITE) {
        std::cout << "White to move" << std::endl;
    } else {
        std::cout << "Black to move" << std::endl;
    }

#ifndef QT_GUI_LIB
    total = nBlackWin + nWhiteWin + nDraw;

    if (total < 0.01f) {
        blackWinRate = 0;
        whiteWinRate = 0;
        drawRate = 0;
    } else {
        blackWinRate = nBlackWin * 100 / total;
        whiteWinRate = nWhiteWin * 100 / total;
        drawRate = nDraw * 100 / total;
    }

    std::cout << "Score: " << static_cast<int>(nBlackWin) << " : "
              << static_cast<int>(nWhiteWin) << " : " << static_cast<int>(nDraw)
              << "\ttotal: " << static_cast<int>(total) << std::endl;
    std::cout << std::fixed << std::setprecision(2) << blackWinRate
              << "% : " << whiteWinRate << "% : " << drawRate << "%"
              << std::endl;
#endif // !QT_GUI_LIB

    std::cout.flags(flags);

    std::cout << std::endl << std::endl;
}

Depth SearchEngine::get_depth() const
{
    return Mills::get_search_depth(rootPos);
}

/// Function to check if the search has timed out
bool SearchEngine::is_timeout(TimePoint startTime)
{
    const auto limit = gameOptions.getMoveTime() * 1000;
    const TimePoint elapsed = now() - startTime;

    if (elapsed > limit) {
#ifdef _WIN32
        debugPrintf("\nTimeout. elapsed = %lld\n", elapsed);
#endif
        return true;
    }

    return false;
}

#ifdef NNUE_GENERATE_TRAINING_DATA
extern Value nnueTrainingDataBestValue;
#endif /* NNUE_GENERATE_TRAINING_DATA */

// Execute the search using the Search namespace
int SearchEngine::executeSearch()
{
    Sanmill::Stack<Position> ss;

#if defined(GABOR_MALOM_PERFECT_AI)
    Move fallbackMove = MOVE_NONE;
    Value fallbackValue = VALUE_UNKNOWN;
#endif // GABOR_MALOM_PERFECT_AI

    Move bestMoveSoFar = MOVE_NONE;
    Value bestValSoFar = VALUE_ZERO;

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

#if 0
    // TODO: Only NMM
    if (rootPos->piece_on_board_count(WHITE)
                + rootPos->piece_on_board_count(BLACK)
            <= 1
        && !rule.hasDiagonalLines && gameOptions.getShufflingEnabled()) {
        const uint32_t seed = static_cast<uint32_t>(now());
        std::shuffle(MoveList<LEGAL>::movePriorityList.begin(),
            MoveList<LEGAL>::movePriorityList.end(),
            std::default_random_engine(seed));
    }
#endif

    Value alpha = VALUE_NONE;
    Value beta = VALUE_NONE;

    if (gameOptions.getAlgorithm() != 2 /* !MTD(f) */) {
        alpha = -VALUE_INFINITE;
        beta = VALUE_INFINITE;
    }

    // ---------------------------------------------------------------------
    // IDS
    // ---------------------------------------------------------------------
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
            if (is_timeout(startTime)) {
                SearchEngine::getInstance().searchAborted.store(
                    true, std::memory_order_relaxed);
                debugPrintf("time out, break\n");
                break;
            }

            if (searchAborted.load(std::memory_order_relaxed)) {
                debugPrintf("originDepth = %d, but break at depth = %d\n",
                            originDepth, i);
                break;
            }

            if (gameOptions.getAlgorithm() == 2 /* MTD(f) */) {
                value = Search::MTDF(rootPos, ss, value, i, i, bestMove);
            } else if (gameOptions.getAlgorithm() == 3 /* MCTS */) {
                value = monte_carlo_tree_search(rootPos, bestMove);
            } else if (gameOptions.getAlgorithm() == 4 /* Random */) {
                value = Search::random_search(rootPos, bestMove);
            } else {
                value = Search::search(rootPos, ss, i, i, alpha, beta,
                                       bestMove);
            }

            if (!searchAborted.load(std::memory_order_relaxed)) {
                bestMoveSoFar = bestMove;
                bestValSoFar = value;
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
                Value v2 = perfect_search(rootPos, bestMove);
                if (v2 != VALUE_UNKNOWN) {
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
        } // end for

#ifdef TIME_STAT
        timeEnd = std::chrono::steady_clock::now();
        sync_cout << "\nIDS Time: "
                  << std::chrono::duration_cast<std::chrono::seconds>(timeEnd -
                                                                      timeStart)
                         .count()
                  << "s\n";
#endif
    } // end if(IDS)

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

    if (!searchAborted.load(std::memory_order_relaxed)) {
        if (gameOptions.getAlgorithm() == 2 /* MTD(f) */) {
            value = Search::MTDF(rootPos, ss, value, originDepth, originDepth,
                                 bestMove);
        } else if (gameOptions.getAlgorithm() == 3 /* MCTS */) {
            value = monte_carlo_tree_search(rootPos, bestMove);
        } else if (gameOptions.getAlgorithm() == 4 /* Random */) {
            value = Search::random_search(rootPos, bestMove);
        } else {
            value = Search::search(rootPos, ss, d, originDepth, alpha, beta,
                                   bestMove);
        }

        bestMoveSoFar = bestMove;
        bestValSoFar = value;
    }

#if defined(GABOR_MALOM_PERFECT_AI)
    fallbackMove = bestMoveSoFar;
    fallbackValue = bestValSoFar;
#endif // GABOR_MALOM_PERFECT_AI

    aiMoveType = AiMoveType::traditional;

    debugPrintf("Algorithm bestMove = %s\n", UCI::move(bestMoveSoFar).c_str());

#if defined(GABOR_MALOM_PERFECT_AI)
    if (gameOptions.getUsePerfectDatabase() == true &&
        !searchAborted.load(std::memory_order_relaxed)) {
        Value v3 = perfect_search(rootPos, bestMoveSoFar);
        if (v3 != VALUE_UNKNOWN) {
            debugPrintf("perfect_search OK.\n");
            debugPrintf("DB bestMove = %s\n", UCI::move(bestMoveSoFar).c_str());
            if (bestMoveSoFar == fallbackMove) {
                aiMoveType = AiMoveType::consensus;
            } else {
                aiMoveType = AiMoveType::perfect;
            }
        } else {
            debugPrintf("perfect_search failed.\n");
            bestMoveSoFar = fallbackMove;
            bestValSoFar = fallbackValue;
            aiMoveType = AiMoveType::traditional;
        }
    }
#endif // GABOR_MALOM_PERFECT_AI

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
    bestvalue = bestValSoFar;
    bestMove = bestMoveSoFar;

    return 0;
}

void SearchEngine::runSearch()
{
#ifdef OPENING_BOOK
    // Use Opening Book module to get the best move string
    if (OpeningBook::has_moves()) {
        getBestMoveFromOpeningBook();
        emitCommand();
    } else {
#endif
        int ret = executeSearch();

#ifdef NNUE_GENERATE_TRAINING_DATA
        extern Value nnueTrainingDataBestValue;
        nnueTrainingDataBestValue = rootPos->side_to_move() == WHITE ?
                                        getBestValue() :
                                        -getBestValue();
#endif /* NNUE_GENERATE_TRAINING_DATA */

        if (ret == 3 || ret == 50 || ret == 10) {
            debugPrintf("Draw\n\n");
            setBestMoveString("draw");
            emitCommand();
        } else {
            setBestMoveString(next_move());
            if (!getBestMoveString().empty() && getBestMoveString() != "error"
                                                                       "!") {
                emitCommand();
            }
        }
#ifdef OPENING_BOOK
    }
#endif
}
