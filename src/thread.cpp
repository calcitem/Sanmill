/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2015-2018 liuweilhy (NineChess author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

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
#include "movegen.h"
#include "search.h"
#include "thread.h"
#include "uci.h"
#include "tt.h"
#include "option.h"

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
#ifdef QT_UI
               , QObject *parent
#endif
) :
    idx(n), stdThread(&Thread::idle_loop, this),
#ifdef QT_UI
    QObject(parent),
#endif
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
#ifdef HOSTORY_HEURISTIC
    clearHistoryScore();
#endif // HOSTORY_HEURISTIC
    start_searching();
    stdThread.join();
}

/// Thread::clear() reset histories, usually before a new game

void Thread::clear()
{
    // TODO
}

/// Thread::start_searching() wakes up the thread that will start the search

void Thread::start_searching()
{
    clearHistoryScore();

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
            if (search() == 3) {
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
#ifdef QT_UI
    emit command(strCommand);
#else
    loggerDebug("%s\n", strCommand.c_str());
    rootPos->command(strCommand.c_str());
    us = rootPos->side_to_move();
    analyze(rootPos->side_to_move());
#endif // QT_UI
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
        sprintf_s(str, 16, "(%d,%d)", file, rank);
    } else {
        sprintf_s(str, 16, "-(%d,%d)", file, rank);
    }
}
#endif // OPENING_BOOK

void Thread::analyze(Color c)
{
    static int nbwin = 0;
    static int nwwin = 0;
    static int ndraw = 0;

    int d = (int)originDepth;
    int v = (int)bestvalue;
    int lv = (int)lastvalue;
    bool win = v >= VALUE_MATE;
    bool lose = v <= -VALUE_MATE;
    int np = v / VALUE_EACH_PIECE;

    string strUs = (c == BLACK ? "黑方" : "白方");
    string strThem = (c == BLACK ? "白方" : "黑方");

    loggerDebug("Depth: %d\n\n", adjustedDepth);

    Position *p = rootPos;

    cout << *p << "\n" << endl;
    cout << std::dec;

    switch (p->get_phase()) {
    case PHASE_PLACING:
        cout << "摆子阶段" << endl;
        break;
    case PHASE_MOVING:
        cout << "走子阶段" << endl;
        break;
    case PHASE_GAMEOVER:
        if (p->get_winner() == DRAW) {
            cout << "和棋" << endl;
            ndraw++;
        } else if (p->get_winner() == BLACK) {
            cout << "黑方胜" << endl;
            nbwin++;
        } else if (p->get_winner() == WHITE) {
            cout << "白方胜" << endl;
            nwwin++;
        }
        goto out;
        break;
    case PHASE_NONE:
        cout << "无棋局" << endl;
        break;
    default:
        cout << "未知阶段" << endl;
    }

    if (v == VALUE_UNIQUE) {
        cout << "唯一着法" << endl << endl << endl;
        return;
    }

    if (lv < -VALUE_EACH_PIECE && v == 0) {
        cout << strThem << "坏棋, 被" << strUs << "拉回均势!" << endl;
    }

    if (lv < 0 && v > 0) {
        cout << strThem << "坏棋, 被" << strUs << "翻转了局势!" << endl;
    }

    if (lv == 0 && v > VALUE_EACH_PIECE) {
        cout << strThem << "败着!" << endl;
    }

    if (lv > VALUE_EACH_PIECE && v == 0) {
        cout << strThem << "好棋, 拉回均势!" << endl;
    }

    if (lv > 0 && v < 0) {
        cout << strThem << "好棋, 翻转了局势!" << endl;
    }

    if (lv == 0 && v < -VALUE_EACH_PIECE) {
        cout << strThem << "秒棋!" << endl;
    }

    if (lv != v) {
        if (lv < 0 && v < 0) {
            if (abs(lv) < abs(v)) {
                cout << strThem << "领先幅度扩大" << endl;
            } else if (abs(lv) > abs(v)) {
                cout << strThem << "领先幅度缩小" << endl;
            }
        }

        if (lv > 0 && v > 0) {
            if (abs(lv) < abs(v)) {
                cout << strThem << "落后幅度扩大" << endl;
            } else if (abs(lv) > abs(v)) {
                cout << strThem << "落后幅度缩小" << endl;
            }
        }
    }

    if (win) {
        cout << strThem << "将在 " << d << " 步后输棋!" << endl;
    } else if (lose) {
        cout << strThem << "将在 " << d << " 步后赢棋!" << endl;
    } else if (np == 0) {
        cout << "将在 " << d << " 步后双方保持均势" << endl;
    } else if (np > 0) {
        cout << strThem << "将在 " << d << " 步后落后 " << np << " 子" << endl;
    } else if (np < 0) {
        cout << strThem << "将在 " << d << " 步后领先 " << -np << " 子" << endl;
    }

    if (p->side_to_move() == BLACK) {
        cout << "轮到黑方行棋" << endl;
    } else {
        cout << "轮到白方行棋" << endl;
    }

    cout << "比分: " << nbwin << " : " << nwwin << " : " << ndraw << endl;

out:
    cout << endl << endl;
}

Depth Thread::adjustDepth()
{
    Depth d = 0;

#ifdef _DEBUG
    Depth reduce = 0;
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
    };

    const Depth placingDepthTable_9[] = {
         +1, 7,  +7,  10,     /* 0 ~ 3 */
        +10, 12, +12, 12,     /* 4 ~ 7 */
        +12, 13, +13, 13,     /* 8 ~ 11 */
        +13, 13, +13, 13,     /* 12 ~ 15 */
        +13, 13, +13          /* 16 ~ 18 */
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
        0, 0, 0,               /* 0 ~ 2 */
        0, 0, 0, 0, 0,       /* 3 ~ 7 */
        0, 0, 0, 0, 0          /* 8 ~ 12 */
    };
#else
    const Depth movingDiffDepthTable[] = {
        0, 0, 0,               /* 0 ~ 2 */
        11, 11, 10, 9, 8,       /* 3 ~ 7 */
        7, 6, 5, 4, 3          /* 8 ~ 12 */
    };
#endif /* ENDGAME_LEARNING */

    const Depth flyingDepth = 9;

    if (rootPos->phase & PHASE_PLACING) {
        if (rule->nTotalPiecesEachSide == 12) {
            d = placingDepthTable_12[rule->nTotalPiecesEachSide * 2 - rootPos->count<IN_HAND>(BLACK) - rootPos->count<IN_HAND>(WHITE)];
        } else {
            d = placingDepthTable_9[rule->nTotalPiecesEachSide * 2 - rootPos->count<IN_HAND>(BLACK) - rootPos->count<IN_HAND>(WHITE)];
        }
    }

    if (rootPos->phase & PHASE_MOVING) {
        int pb = rootPos->count<ON_BOARD>(BLACK);
        int pw = rootPos->count<ON_BOARD>(WHITE);

        int pieces = pb + pw;
        int diff = pb - pw;

        if (diff < 0) {
            diff = -diff;
        }

        d = movingDiffDepthTable[diff];

        if (d == 0) {
            d = movingDepthTable[pieces];
        }

        // Can fly
        if (rule->allowFlyWhenRemainThreePieces) {
            if (pb == rule->nPiecesAtLeast ||
                pw == rule->nPiecesAtLeast) {
                d = flyingDepth;
            }

            if (pb == rule->nPiecesAtLeast &&
                pw == rule->nPiecesAtLeast) {
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
    if (strcmp(rule->name, rule->name) != 0) {
#ifdef TRANSPOSITION_TABLE_ENABLE
        TranspositionTable::clear();
#endif // TRANSPOSITION_TABLE_ENABLE

#ifdef ENDGAME_LEARNING
        // TODO: ??????????
        //clearEndgameHashMap();
        //endgameList.clear();
#endif // ENDGAME_LEARNING

        moveHistory.clear();
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
#ifdef HOSTORY_HEURISTIC
            root->children[i]->score,
#else
            0,
#endif
            charSelect);

        moveIndex++;
    }

    Color side = position->sideToMove;

#ifdef ENDGAME_LEARNING
    // Check if very weak
    if (gameOptions.getLearnEndgameEnabled()) {
        if (bestValue <= -VALUE_KNOWN_WIN) {
            Endgame endgame;
            endgame.type = state->position->playerSideToMove == PLAYER_BLACK ?
                ENDGAME_PLAYER_WHITE_WIN : ENDGAME_PLAYER_BLACK_WIN;
            key_t endgameHash = position->key(); // TODO: Do not generate hash repeately
            recordEndgameHash(endgameHash, endgame);
        }
    }
#endif /* ENDGAME_LEARNING */

    if (gameOptions.getResignIfMostLose() == true) {
        if (root->value <= -VALUE_MATE) {
            gameoverReason = LOSE_REASON_RESIGN;
            //sprintf(cmdline, "Player%d give up!", position->sideToMove);
            return cmdline;
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
bool Thread::findEndgameHash(key_t posKey, Endgame &endgame)
{
    return endgameHashMap.find(posKey, endgame);
}

int Thread::recordEndgameHash(key_t posKey, const Endgame &endgame)
{
    //hashMapMutex.lock();
    key_t hashValue = endgameHashMap.insert(posKey, endgame);
    unsigned addr = hashValue * (sizeof(posKey) + sizeof(endgame));
    //hashMapMutex.unlock();

    loggerDebug("[endgame] Record 0x%08I32x (%d) to Endgame Hash map, TTEntry: 0x%08I32x, Address: 0x%08I32x\n", posKey, endgame.type, hashValue, addr);

    return 0;
}

void Thread::clearEndgameHashMap()
{
    //hashMapMutex.lock();
    endgameHashMap.clear();
    //hashMapMutex.unlock();
}

void Thread::recordEndgameHashMapToFile()
{
    const QString filename = "endgame.txt";
    endgameHashMap.dump(filename);

    loggerDebug("[endgame] Dump hash map to file\n");
}

void Thread::loadEndgameFileToHashMap()
{
    const QString filename = "endgame.txt";
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
        TT.resize((size_t)Options["Hash"]);
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
    // be deduced from a fen string, so set() clears them and to not lose the info
    // we need to backup and later restore setupStates->back(). Note that setupStates
    // is shared by threads but is accessed in read-only mode.
    //StateInfo tmp = setupStates->back();

    for (Thread *th : *this) {
        // TODO
        //th->rootPos->set(pos->fen(), &setupStates->back(), th);
        th->rootPos = pos;
    }

    main()->start_searching();
}
