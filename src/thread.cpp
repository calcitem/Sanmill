/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <iomanip>

#include "thread.h"
#include "uci.h"
#include "option.h"
#include "mills.h"

#ifdef PERFECT_AI_SUPPORT
#include "perfect/perfect.h"
#endif

#ifdef FLUTTER_UI
#include "engine_main.h"
#endif

Thread *mainThread; // Global object

#ifdef OPENING_BOOK
#include <deque>
using namespace std;
#endif

#if _MSC_VER >= 1600
#pragma warning(disable:4695)
#pragma execution_character_set("ANSI")
#endif


/// Thread constructor launches the thread and waits until it goes to sleep
/// in idle_loop(). Note that 'searching' and 'exit' should be already set.

Thread::Thread(
#ifdef QT_GUI_LIB
               QObject *parent
#endif
) :
#ifdef QT_GUI_LIB
    QObject(parent),
#endif
    stdThread(&Thread::idle_loop, this),
    timeLimit(3600)
{
    wait_for_search_finished();
}


/// Thread destructor wakes up the thread in idle_loop() and waits
/// for its termination. Thread should be already waiting.

Thread::~Thread()
{
    assert(!searching);

    exit = true;
    start_searching();
    stdThread.join();
}


/// Thread::start_searching() wakes up the thread that will start the search

void Thread::start_searching()
{
    std::lock_guard<std::mutex> lk(mutex);
    searching = true;
    cv.notify_one(); // Wake up the thread in idle_loop()
}


/// Thread::wait_for_search_finished() blocks on the condition variable
/// until the thread has finished searching.

void Thread::wait_for_search_finished()
{
    std::unique_lock<std::mutex> lk(mutex);
    cv.wait(lk, [&] { return !searching; });
}


/// Thread::idle_loop() is where the thread is parked, blocked on the
/// condition variable, when it has no work to do.

void Thread::idle_loop()
{
    while (true) {
        std::unique_lock<std::mutex> lk(mutex);
        searching = false;

        cv.notify_one(); // Wake up anyone waiting for search finished
        cv.wait(lk, [&] { return searching; });

        if (exit)
            return;

        lk.unlock();

        // Note: Stockfish doesn't have this
        if (rootPos == nullptr || rootPos->side_to_move() != us) {
            continue;
        }

        clear_tt();

#ifdef PERFECT_AI_SUPPORT
        if (gameOptions.getPerfectAiEnabled()) {
            bestMove = perfect_search();
            assert(bestMove != MOVE_NONE);
            strCommand = next_move();
            if (strCommand != "" && strCommand != "error!") {
                emitCommand();
            }
        } else {
#endif // PERFECT_AI_SUPPORT
#ifdef OPENING_BOOK
            // gameOptions.getOpeningBook()
            if (!openingBookDeque.empty()) {
                char obc[16] = { 0 };
                sq2str(obc);
                strCommand = obc;
                emitCommand();
            } else {
#endif
                int ret = search();

                if (ret == 3 || ret == 50) {
                    loggerDebug("Draw\n\n");
                    strCommand = "draw";
                    emitCommand();
                } else {
                    strCommand = next_move();
                    if (strCommand != "" && strCommand != "error!") {
                        emitCommand();
                    }
                }
#ifdef OPENING_BOOK
            }
#endif
#ifdef PERFECT_AI_SUPPORT
        }
#endif // PERFECT_AI_SUPPORT
    }
}


////////////////////////////////////////////////////////////////////////////

void Thread::setAi(Position *p)
{
    std::lock_guard<std::mutex> lk(mutex);

    this->rootPos = p;

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef CLEAR_TRANSPOSITION_TABLE
    TranspositionTable::clear();
#endif
#endif
}

void Thread::setAi(Position *p, int tl)
{
    setAi(p);

    timeLimit = tl;
}

void Thread::emitCommand()
{
#ifdef QT_GUI_LIB
    emit command(strCommand);
#else
    sync_cout << "bestmove " << strCommand.c_str();
    std::cout << sync_endl;

#ifdef FLUTTER_UI
    println("bestmove %s", strCommand.c_str());
#endif

#ifdef UCI_DO_BEST_MOVE
    rootPos->command(strCommand.c_str());
    us = rootPos->side_to_move();

    if (strCommand.size() > strlen("-(1,2)")) {
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

#ifdef OPENING_BOOK
deque<int> openingBookDeque(
    {
        /* B W */
        21, 23,
        19, 20,
        17, 18,
        15,
    }
);

deque<int> openingBookDequeBak;

void sq2str(char *str)
{
    int sq = openingBookDeque.front();
    openingBookDeque.pop_front();
    openingBookDequeBak.push_back(sq);

    File file = FILE_A;
    Rank rank = RANK_1;
    int sig = 1;

    if (sq < 0) {
        sq = -sq;
        sig = 0;
    }

    file = file_of(sq);
    rank = rank_of(sq);

    if (sig == 1) {
        snprintf(str, Position::RECORD_LEN_MAX, 16, "(%d,%d)", file, rank);
    } else {
        snprintf(str, Position::RECORD_LEN_MAX, "-(%d,%d)", file, rank);
    }
}
#endif // OPENING_BOOK

void Thread::analyze(Color c)
{
    static float nbwin = 0;
    static float nwwin = 0;
    static float ndraw = 0;
#ifndef QT_GUI_LIB
    float total;
    float bwinrate, wwinrate, drawrate;
#endif // !QT_GUI_LIB

    const int d = (int)originDepth;
    const int v = (int)bestvalue;
    const int lv = (int)lastvalue;
    const bool win = v >= VALUE_MATE;
    const bool lose = v <= -VALUE_MATE;
    const int np = v / VALUE_EACH_PIECE;

    string strUs = (c == BLACK ? "Black" : "White");
    string strThem = (c == BLACK ? "White" : "Black");

    loggerDebug("Depth: %d\n\n", originDepth);

    const Position *p = rootPos;

    cout << *p << "\n" << endl;
    cout << std::dec;

    switch (p->get_phase()) {
    case Phase::placing:
        cout << "Placing phrase" << endl;
        break;
    case Phase::moving:
        cout << "Moving phase" << endl;
        break;
    case Phase::gameOver:
        if (p->get_winner() == DRAW) {
            cout << "Draw" << endl;
            ndraw += 0.5;   // TODO
        } else if (p->get_winner() == BLACK) {
            cout << "Black wins" << endl;
            nbwin += 0.5;  // TODO
        } else if (p->get_winner() == WHITE) {
            cout << "White wins" << endl;
            nwwin += 0.5;    // TODO
        }
        goto out;
        break;
    case Phase::none:
        cout << "None phase" << endl;
        break;
    default:
        cout << "Known phase" << endl;
    }

    if (v == VALUE_UNIQUE) {
        cout << "Unique move" << endl << endl << endl;
        return;
    }

    if (lv < -VALUE_EACH_PIECE && v == 0) {
        cout << strThem << " made a bad move, " << strUs << " pulled back the balance of power!" << endl;
    }

    if (lv < 0 && v > 0) {
        cout << strThem << " made a bad move, " << strUs << " reversed the situation!" << endl;
    }

    if (lv == 0 && v > VALUE_EACH_PIECE) {
        cout << strThem << "Bad move!" << endl;
    }

    if (lv > VALUE_EACH_PIECE && v == 0) {
        cout << strThem << "made a good move, pulled back the balance of power" << endl;
    }

    if (lv > 0 && v < 0) {
        cout << strThem << "made a good move, reversed the situation!" << endl;
    }

    if (lv == 0 && v < -VALUE_EACH_PIECE) {
        cout << strThem << " made a good move!" << endl;
    }

    if (lv != v) {
        if (lv < 0 && v < 0) {
            if (abs(lv) < abs(v)) {
                cout << strThem << " has expanded its lead" << endl;
            } else if (abs(lv) > abs(v)) {
                cout << strThem << " has narrowed its lead" << endl;
            }
        }

        if (lv > 0 && v > 0) {
            if (abs(lv) < abs(v)) {
                cout << strThem << " has expanded its lead" << endl;
            } else if (abs(lv) > abs(v)) {
                cout << strThem << " has narrowed its backwardness" << endl;
            }
        }
    }

    if (win) {
        cout << strThem << " will lose in " << d << " moves!" << endl;
    } else if (lose) {
        cout << strThem << " will win in " << d << " moves!" << endl;
    } else if (np == 0) {
        cout << "The two sides will maintain a balance of power after " << d << " moves" << endl;
    } else if (np > 0) {
        cout << strThem << " after " << d << " moves will backward " << np << " pieces" << endl;
    } else if (np < 0) {
        cout << strThem << " after " << d << " moves will lead " << -np << " pieces" << endl;
    }

    if (p->side_to_move() == BLACK) {
        cout << "Black to move" << endl;
    } else {
        cout << "White to move" << endl;
    }

#ifndef QT_GUI_LIB
    total = nbwin + nwwin + ndraw;

    if (total < 0.01) {
        bwinrate = 0;
        wwinrate = 0;
        drawrate = 0;
    } else {
        bwinrate = (float)nbwin * 100 / total;
        wwinrate = (float)nwwin * 100 / total;
        drawrate = (float)ndraw * 100 / total;
    }

    cout << "Score: " << (int)nbwin << " : " << (int)nwwin << " : " << (int)ndraw << "\ttotal: " << (int)total << endl;
    cout << fixed << setprecision(2) << bwinrate << "% : " << wwinrate << "% : " << drawrate << "%" << endl;
#endif // !QT_GUI_LIB

out:
    cout << endl << endl;
}

Depth Thread::get_depth()
{
    return Mills::get_search_depth(rootPos);
}

void Thread::clear_tt()
{
    if (strcmp(rule.name, rule.name) != 0) {
#ifdef TRANSPOSITION_TABLE_ENABLE
        TranspositionTable::clear();
#endif // TRANSPOSITION_TABLE_ENABLE
    }
}

string Thread::next_move()
{
#ifdef ENDGAME_LEARNING
    // Check if very weak
    if (gameOptions.isEndgameLearningEnabled()) {
        if (bestvalue <= -VALUE_KNOWN_WIN) {
            Endgame endgame;
            endgame.type = rootPos->side_to_move() == BLACK ?
                EndGameType::whiteWin : EndGameType::blackWin;
            Key endgameHash = rootPos->key(); // TODO: Do not generate hash repeatedly
            saveEndgameHash(endgameHash, endgame);
        }
    }
#endif /* ENDGAME_LEARNING */

    if (gameOptions.getResignIfMostLose() == true) {
        if (bestvalue <= -VALUE_MATE) {
            rootPos->set_gameover(~rootPos->sideToMove, GameOverReason::loseReasonResign);
            snprintf(rootPos->record, Position::RECORD_LEN_MAX, loseReasonResignStr, rootPos->sideToMove);
            return rootPos->record;
        }
    }

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef TRANSPOSITION_TABLE_DEBUG
    size_t hashProbeCount = ttHitCount + ttMissCount;
    if (hashProbeCount) {
        loggerDebug("[posKey] probe: %llu, hit: %llu, miss: %llu, hit rate: %llu%%\n",
                    hashProbeCount, ttHitCount, ttMissCount, ttHitCount * 100 / hashProbeCount);
    }
#endif // TRANSPOSITION_TABLE_DEBUG
#endif // TRANSPOSITION_TABLE_ENABLE

    return UCI::move(bestMove);
}

#ifdef ENDGAME_LEARNING
bool Thread::probeEndgameHash(Key posKey, Endgame &endgame)
{
    return endgameHashMap.find(posKey, endgame);
}

int Thread::saveEndgameHash(Key posKey, const Endgame &endgame)
{
    Key hashValue = endgameHashMap.insert(posKey, endgame);
    unsigned addr = hashValue * (sizeof(posKey) + sizeof(endgame));

    loggerDebug("[endgame] Record 0x%08I32x (%d) to Endgame hash map, TTEntry: 0x%08I32x, Address: 0x%08I32x\n",
                posKey, endgame.type, hashValue, addr);

    return 0;
}

void Thread::clearEndgameHashMap()
{
    endgameHashMap.clear();
}

void Thread::saveEndgameHashMapToFile()
{
    const string filename = "endgame.txt";
    endgameHashMap.dump(filename);

    loggerDebug("[endgame] Dump hash map to file\n");
}

void Thread::loadEndgameFileToHashMap()
{
    const string filename = "endgame.txt";
    endgameHashMap.load(filename);
}

#endif // ENDGAME_LEARNING

/// Thread::set() creates/destroys thread
/// Created and launched thread will immediately go to sleep in idle_loop.
/// Upon resizing, thread are recreated to allow for binding if necessary.

void Thread::set(size_t requested)
{
    if (mainThread != nullptr) { // destroy any existing thread(s)
        wait_for_search_finished();

        delete mainThread;
        mainThread = nullptr;
    }

    if (requested > 0) { // create new thread(s)
        mainThread = new Thread();

#ifdef TRANSPOSITION_TABLE_ENABLE
        // Reallocate the hash with the new thread pool size
        TT.resize(size_t(Options["Hash"]));
#endif
    }
}


/// Thread::start_thinking() wakes up thread waiting in idle_loop() and
/// returns immediately. Thread will wake up other threads and start the search.

void Thread::start_thinking(Position *pos)
{
    wait_for_search_finished();
    stop = false;
    rootPos = pos;
    start_searching();
}
