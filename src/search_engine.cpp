// search_engine.cpp

#include "search_engine.h"
#include "thread.h"
#include "uci.h"
#include "mills.h"
#include <iostream>
#include <sstream>

#ifdef FLUTTER_UI
#include "engine_main.h"
#endif

SearchEngine::SearchEngine(Thread *thread)
    : thread(thread)
{ }

void SearchEngine::emitCommand()
{
    std::ostringstream ss;
    std::string aiMoveTypeStr;

    if (thread->rootPos->side_to_move() == BLACK) {
        thread->bestvalue = -thread->bestvalue;
    }

    switch (thread->aiMoveType) {
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

    ss << "info score " << static_cast<int>(thread->bestvalue) << aiMoveTypeStr
       << " bestmove " << thread->bestMoveString;

#ifdef QT_GUI_LIB
    emit thread->command(ss.str()); // Origin: bestMoveString
#else
    std::cout << ss.str() << std::endl;

#ifdef FLUTTER_UI
    println(ss.str().c_str());
#endif

#ifdef UCI_DO_BEST_MOVE
    thread->rootPos->command(ss.str());
    thread->us = thread->rootPos->side_to_move();

    if (thread->bestMoveString.size() > strlen("-(1,2)")) {
        posKeyHistory.push_back(thread->rootPos->key());
    } else {
        posKeyHistory.clear();
    }
#endif

#ifdef ANALYZE_POSITION
    analyze(thread->rootPos->side_to_move());
#endif
#endif // QT_GUI_LIB
}

std::string SearchEngine::next_move() const
{
#ifdef ENDGAME_LEARNING
    // Check if very weak
    if (gameOptions.isEndgameLearningEnabled()) {
        if (thread->bestvalue <= -VALUE_KNOWN_WIN) {
            Endgame endgame;
            endgame.type = thread->rootPos->side_to_move() == WHITE ?
                               EndGameType::blackWin :
                               EndGameType::whiteWin;
            Key endgameHash = thread->rootPos->key(); // TODO: Avoid repeated
                                                      // hash generation
            thread->saveEndgameHash(endgameHash, endgame);
        }
    }
#endif /* ENDGAME_LEARNING */

    if (gameOptions.getResignIfMostLose()) {
        if (thread->bestvalue <= -VALUE_MATE) {
            thread->rootPos->set_gameover(~thread->rootPos->side_to_move(),
                                          GameOverReason::loseResign);
            snprintf(thread->rootPos->record, Position::RECORD_LEN_MAX,
                     LOSE_REASON_PLAYER_RESIGNS,
                     thread->rootPos->side_to_move());
            return thread->rootPos->record;
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

    return UCI::move(thread->bestMove);
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

    const int d = thread->originDepth;
    const int v = thread->bestvalue;
    const int lv = thread->lastvalue;
    const bool win = v >= VALUE_MATE;
    const bool lose = v <= -VALUE_MATE;
    const int np = v / VALUE_EACH_PIECE;

    const std::string strUs = (c == WHITE ? "White" : "Black");
    const std::string strThem = (c == WHITE ? "Black" : "White");

    const auto flags = std::cout.flags();

    debugPrintf("Depth: %d\n\n", thread->originDepth);

    const Position *p = thread->rootPos;

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
