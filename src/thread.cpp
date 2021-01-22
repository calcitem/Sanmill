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

#include <cassert>

#include <algorithm> // For std::count
#include <iomanip>
#include "movegen.h"
#include "search.h"
#include "thread.h"
#include "uci.h"
#include "tt.h"
#include "option.h"

#ifdef FLUTTER_UI
#include "engine_main.h"
#endif

ThreadPool Threads; // Global object

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

Thread::Thread(size_t n
#ifdef QT_GUI_LIB
               , QObject *parent
#endif
) :
#ifdef QT_GUI_LIB
    QObject(parent),
#endif
    idx(n), stdThread(&Thread::idle_loop, this),
    timeLimit(3600)
{
    perfect_init();

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

/// Thread::clear() reset histories, usually before a new game

void Thread::clear() noexcept
{
    // TODO
}

/// Thread::start_searching() wakes up the thread that will start the search

void Thread::start_searching()
{
    std::lock_guard<std::mutex> lk(mutex);
    searching = true;
    cv.notify_one(); // Wake up the thread in idle_loop()
}

void Thread::pause()
{
    // TODO: Can work?
    std::lock_guard<std::mutex> lk(mutex);
    searching = false;
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
    //bestvalue = lastvalue = VALUE_ZERO;

    while (true) {
        std::unique_lock<std::mutex> lk(mutex);
        searching = false;  

        cv.notify_one(); // Wake up anyone waiting for search finished
        cv.wait(lk, [&] { return searching; });

        if (exit)
            return;

        lk.unlock();

        // TODO: Stockfish doesn't have this
        if (rootPos == nullptr || rootPos->side_to_move() != us) {
            continue;
        }

        clearTT();

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
                strCommand = nextMove();
                if (strCommand != "" && strCommand != "error!") {
                    emitCommand();
                }
            }
#ifdef OPENING_BOOK
        }
#endif
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

    loggerDebug("Depth: %d\n\n", adjustedDepth);

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
        cout << strThem << " made a bad move, " << strUs << "pulled back the balance of power!" << endl;
    }

    if (lv < 0 && v > 0) {
        cout << strThem << " made a bad move, " << strUs << "reversed the situation!" << endl;
    }

    if (lv == 0 && v > VALUE_EACH_PIECE) {
        cout << strThem << "Bad move!" << endl;
    }

    if (lv > VALUE_EACH_PIECE && v == 0) {
        cout << strThem << "Good move, pulled back the balance of power" << endl;
    }

    if (lv > 0 && v < 0) {
        cout << strThem << "Good move, reversed the situation!" << endl;
    }

    if (lv == 0 && v < -VALUE_EACH_PIECE) {
        cout << strThem << "made a good move!" << endl;
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

Depth Thread::adjustDepth()
{
    Depth d = 0;

#ifdef _DEBUG
    constexpr Depth reduce = 0;
#else
    Depth reduce = 0;
#endif

    const Depth placingDepthTable_12[] = {
         +1,  2,  +2,  4,     /* 0 ~ 3 */
         +4, 12, +12, 18,     /* 4 ~ 7 */
        +12, 16, +16, 16,     /* 8 ~ 11 */
        +16, 16, +16, 17,     /* 12 ~ 15 */
        +17, 16, +16, 15,     /* 16 ~ 19 */
        +15, 14, +14, 14,     /* 20 ~ 23 */
        +14                   /* 24 */
    };

    const Depth placingDepthTable_9[] = {
         +1, 7,  +7,  10,     /* 0 ~ 3 */
        +10, 12, +12, 12,     /* 4 ~ 7 */
        +12, 13, +13, 13,     /* 8 ~ 11 */
        +13, 13, +13, 13,     /* 12 ~ 15 */
        +13, 13, +13,         /* 16 ~ 18 */
        +13                   /* 19 */
    };

    const Depth movingDepthTable[] = {
         1,  1,  1,  1,     /* 0 ~ 3 */
         1,  1, 11, 11,     /* 4 ~ 7 */
        11, 11, 11, 11,     /* 8 ~ 11 */
        11, 11, 11, 11,     /* 12 ~ 15 */
        11, 11, 11, 11,     /* 16 ~ 19 */
        12, 12, 13, 14,     /* 20 ~ 23 */
    };

#ifdef ENDGAME_LEARNING
    const Depth movingDiffDepthTable[] = {
        0, 0, 0,                /* 0 ~ 2 */
        0, 0, 0, 0, 0,          /* 3 ~ 7 */
        0, 0, 0, 0, 0           /* 8 ~ 12 */
    };
#else
    const Depth movingDiffDepthTable[] = {
        0, 0, 0,                /* 0 ~ 2 */
        11, 11, 10, 9, 8,       /* 3 ~ 7 */
        7, 6, 5, 4, 3           /* 8 ~ 12 */
    };
#endif /* ENDGAME_LEARNING */

    constexpr Depth flyingDepth = 9;

    if (rootPos->phase == Phase::placing) {
        const int index = rule.piecesCount * 2 - rootPos->count<IN_HAND>(BLACK) - rootPos->count<IN_HAND>(WHITE);

        if (rule.piecesCount == 12) {
            assert(0 <= index && index <= 24);
            d = placingDepthTable_12[index];
        } else {
            assert(0 <= index && index <= 19);
            d = placingDepthTable_9[index];
        }
    }

    if (rootPos->phase == Phase::moving) {
        const int pb = rootPos->count<ON_BOARD>(BLACK);
        const int pw = rootPos->count<ON_BOARD>(WHITE);

        const int pieces = pb + pw;
        int diff = pb - pw;

        if (diff < 0) {
            diff = -diff;
        }

        d = movingDiffDepthTable[diff];

        if (d == 0) {
            d = movingDepthTable[pieces];
        }

        // Can fly
        if (rule.mayFly) {
            if (pb == rule.piecesAtLeastCount ||
                pw == rule.piecesAtLeastCount) {
                d = flyingDepth;
            }

            if (pb == rule.piecesAtLeastCount &&
                pw == rule.piecesAtLeastCount) {
                d = flyingDepth / 2;
            }
        }
    }

    if (unlikely(d > reduce)) {
        d -= reduce;
    }

    d += DEPTH_ADJUST;

    d = d >= 1 ? d : 1;

#if defined(FIX_DEPTH)
    d = FIX_DEPTH;
#endif

    assert(d <= 32);

    //loggerDebug("Depth: %d\n", d);

    return d;
}

void Thread::clearTT()
{
    if (strcmp(rule.name, rule.name) != 0) {
#ifdef TRANSPOSITION_TABLE_ENABLE
        TranspositionTable::clear();
#endif // TRANSPOSITION_TABLE_ENABLE
    }
}

string Thread::nextMove()
{
#if 0
    char charSelect = '*';

    Position::print_board();

    int moveIndex = 0;
    bool foundBest = false;

    int cs = root->childrenSize;
    for (int i = 0; i < cs; i++) {
        if (root->children[i]->move != bestMove) {
            charSelect = ' ';
        } else {
            charSelect = '*';
            foundBest = true;
        }

        loggerDebug("[%.2d] %d\t%s\t%d\t%u %c\n", moveIndex,
                    root->children[i]->move,
                    UCI::move(root->children[i]->move).c_str();
        root->children[i]->value,
            0,
            charSelect);

        moveIndex++;
    }

    Color side = position->sideToMove;

#ifdef ENDGAME_LEARNING
    // Check if very weak
    if (gameOptions.isEndgameLearningEnabled()) {
        if (bestValue <= -VALUE_KNOWN_WIN) {
            Endgame endgame;
            endgame.type = state->position->playerSideToMove == PLAYER_BLACK ?
                whiteWin : blackWin;
            Key endgameHash = position->key(); // TODO: Do not generate hash repeately
            saveEndgameHash(endgameHash, endgame);
        }
    }
#endif /* ENDGAME_LEARNING */

    if (gameOptions.getResignIfMostLose() == true) {
        if (root->value <= -VALUE_MATE) {
            gameOverReason = loseReasonResign;
            //snprintf(record, Position::RECORD_LEN_MAX, "Player%d give up!", position->sideToMove);
            return record;
        }
    }

    nodeCount = 0;

#endif

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef TRANSPOSITION_TABLE_DEBUG
    size_t hashProbeCount = ttHitCount + ttMissCount;
    if (hashProbeCount) {
        loggerDebug("[posKey] probe: %llu, hit: %llu, miss: %llu, hit rate: %llu%%\n",
                    hashProbeCount, ttHitCount, ttMissCount, ttHitCount * 100 / hashProbeCount);
    }
#endif // TRANSPOSITION_TABLE_DEBUG
#endif // TRANSPOSITION_TABLE_ENABLE

#if 0
    if (foundBest == false) {
        loggerDebug("Warning: Best Move NOT Found\n");
    }
#endif

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

/// ThreadPool::set() creates/destroys threads to match the requested number.
/// Created and launched threads will immediately go to sleep in idle_loop.
/// Upon resizing, threads are recreated to allow for binding if necessary.

void ThreadPool::set(size_t requested)
{
    if (size() > 0) { // destroy any existing thread(s)
        main()->wait_for_search_finished();

        while (size() > 0)
            delete back(), pop_back();
    }

    if (requested > 0) { // create new thread(s)
        push_back(new MainThread(0));

        while (size() < requested)
            push_back(new Thread(size()));
        clear();

#ifdef TRANSPOSITION_TABLE_ENABLE
        // Reallocate the hash with the new threadpool size
        TT.resize(size_t(Options["Hash"]));
#endif

        // Init thread number dependent search params.
        Search::init();
    }
}

/// ThreadPool::clear() sets threadPool data to initial values.

void ThreadPool::clear()
{
    for (Thread *th : *this)
        th->clear();
}


/// ThreadPool::start_thinking() wakes up main thread waiting in idle_loop() and
/// returns immediately. Main thread will wake up other threads and start the search.

void ThreadPool::start_thinking(Position *pos, bool ponderMode)
{
    main()->wait_for_search_finished();

    main()->stopOnPonderhit = stop = false;
    increaseDepth = true;
    main()->ponder = ponderMode;

    // We use Position::set() to set root position across threads. But there are
    // some StateInfo fields (previous, pliesFromNull, capturedPiece) that cannot
    // be deduced from a fen string, so set() clears them and they are set from
    // setupStates->back() later. The rootState is per thread, earlier states are shared
    // since they are read-only.
    for (Thread *th : *this) {
        // TODO
        //th->rootPos->set(pos->fen(), &setupStates->back(), th);
        th->rootPos = pos;
    }

    main()->start_searching();
}


////////////////////////////////////////////////////////////////////////////

int Thread::perfect_init(void)
{
#ifdef _DEBUG
    char databaseDirectory[] = "D:\\database";
#elif _RELEASE_X64
    char databaseDirectory[] = "";
#endif

    mill = new Mill();
    ai = new PerfectAI(databaseDirectory);
    ai->setDatabasePath(databaseDirectory);
    mill->beginNewGame(ai, ai, fieldStruct::playerOne);

    return 0;
}

Square Thread::perfect_sq_to_sq(unsigned int sq)
{
    Square map[] = {
        SQ_31, SQ_24, SQ_25, SQ_23, SQ_16, SQ_17, SQ_15, SQ_8,
        SQ_9, SQ_30, SQ_22, SQ_14, SQ_10, SQ_18, SQ_26, SQ_13,
        SQ_12, SQ_11, SQ_21, SQ_20, SQ_19, SQ_29, SQ_28, SQ_27,
        SQ_0 };

    return map[sq];
}

Move Thread::perfect_move_to_move(unsigned int from, unsigned int to)
{
    if (mill->mustStoneBeRemoved())
        return (Move)-perfect_sq_to_sq(to);
    else if (mill->inSettingPhase())
        return (Move)perfect_sq_to_sq(to);
    else
        return (Move)(make_move(perfect_sq_to_sq(from), perfect_sq_to_sq(to)));
}

unsigned Thread::sq_to_perfect_sq(Square sq)
{
    int map[] = {
        -1, -1, -1, -1, -1, -1, -1, -1,
        7, 8, 12, 17, 16, 15, 11, 6,    /* 8 - 15 */
        4, 5, 13, 20, 19, 18, 10, 3,    /* 16 - 23 */
        1, 2, 14, 23, 22, 21, 9, 0,     /* 24 - 31 */
        -1, -1, -1, -1, -1, -1, -1, -1,
    };

    return map[sq];
}

void Thread::move_to_perfect_move(Move move, unsigned int &from, unsigned int &to)
{
    Square f = from_sq(move);
    Square t = to_sq(move);

    if (mill->mustStoneBeRemoved()) {
        from = fieldStruct::size;
        to = sq_to_perfect_sq(t);
    } else if (mill->inSettingPhase()) {
        from = fieldStruct::size;
        to = sq_to_perfect_sq(t);
    } else {
        from = sq_to_perfect_sq(f);
        to = sq_to_perfect_sq(t);
    }
}

int Thread::perfect_search()
{
    unsigned int from, to;
    mill->getComputersChoice(&from, &to);

    cout << "\nlast move was from " << (char)(mill->getLastMoveFrom() + 'a') << " to " << (char)(mill->getLastMoveTo() + 'a') << "\n\n";

    mill->printBoard();

    bestMove = perfect_move_to_move(mill->getLastMoveFrom(), mill->getLastMoveTo());

    return 0;
}

bool Thread::perfect_do_move(Move move)
{
    bool ret;
    unsigned int from, to;

    move_to_perfect_move(move, from, to);

    ret = mill->doMove(from, to);
    return ret;
}

// mill->getWinner() == 0
// mill->getCurrentPlayer() == fieldStruct::playerTwo