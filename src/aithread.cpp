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

#include <QTimer>
#include "aithread.h"
#include "tt.h"
#include "uci.h"
#include "option.h"

#ifdef OPENING_BOOK
#include <deque>
using namespace std;
#endif

#if _MSC_VER >= 1600
#pragma execution_character_set("GB2312")
#endif

Value MTDF(Position *pos, Sanmill::Stack<Position> &ss, Value firstguess, Depth depth, Depth originDepth, Move &bestMove);

AiThread::AiThread(int color, QObject *parent) :
    QThread(parent),
    timeLimit(3600)
{
    this->us = color;

    connect(this, &AiThread::searchStarted, this, [=]() {timer.start(timeLimit * 1000 - 118 /* 118ms is return time */); }, Qt::QueuedConnection);
    connect(this, &AiThread::searchFinished, this, [=]() {timer.stop(); }, Qt::QueuedConnection);
    connect(&timer, &QTimer::timeout, this, &AiThread::act, Qt::QueuedConnection);

#ifndef TRAINING_MODE
    if (color == 1) {
        server = new Server(nullptr, 30001);    // TODO: WARNING: ThreadSanitizer: data race
        uint16_t clientPort = server->getPort() == 30001 ? 30002 : 30001;
        client = new Client(nullptr, clientPort);
    }
#endif  // TRAINING_MODE
}

AiThread::~AiThread()
{
    //delete server;
    //delete client;

    stop();
    quit();
    wait();
}

void AiThread::setAi(Position *p)
{
    mutex.lock();

    this->pos = p;
    setPosition(p);

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef CLEAR_TRANSPOSITION_TABLE
    TranspositionTable::clear();
#endif
#endif

    mutex.unlock();
}

void AiThread::setAi(Position *p, int tl)
{
    mutex.lock();
    this->pos = p;
    setPosition(p);
    timeLimit = tl;
    mutex.unlock();
}

void AiThread::emitCommand()
{
    emit command(strCommand);
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

void AiThread::analyze(Color c)
{
    int d = (int)originDepth;
    int v = (int)bestvalue;
    int lv = (int)lastvalue;
    bool win = v >= VALUE_MATE;
    bool lose = v <= -VALUE_MATE;
    int np = v / VALUE_EACH_PIECE;

    string strUs = (c == BLACK ? "黑方" : "白方");
    string strThem = (c == BLACK ? "白方" : "黑方");

    loggerDebug("Depth: %d\n\n", newDepth);

    Position *p = position();

    cout << *p << "\n" << endl;
    cout << std::dec;

    switch (p->get_phase())
    {
    case PHASE_PLACING:
        cout << "摆子阶段" << endl;
        break;
    case PHASE_MOVING:
        cout << "走子阶段" << endl;
        break;
    case PHASE_GAMEOVER:
        if (p->get_winner() == DRAW) {
            cout << "和棋" << endl;
        } else if (p->get_winner() == BLACK) {
            cout << "黑方胜" << endl;
        } else if (p->get_winner() == WHITE) {
            cout << "白方胜" << endl;
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
        cout << "轮到黑方行棋";
    } else {
        cout << "轮到白方行棋";
    }

out:
    cout << endl << endl;
}

void AiThread::run()
{
#ifdef DEBUG_MODE
    int iTemp = 0;
#endif

    Color sideToMove = NOCOLOR;

    loggerDebug("Thread %d start\n", us);

    bestvalue = lastvalue = VALUE_ZERO;

    while (!isInterruptionRequested()) {
        mutex.lock();

        sideToMove = pos->sideToMove;

        if (sideToMove != us) {
            pauseCondition.wait(&mutex);
            mutex.unlock();
            continue;
        }

        setPosition(pos);
        emit searchStarted();
        mutex.unlock();

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

        emit searchFinished();

        mutex.lock();
        if (!isInterruptionRequested()) {
            pauseCondition.wait(&mutex);
        }
        mutex.unlock();
    }

    loggerDebug("Thread %d quit\n", us);
}

void AiThread::act()
{
    if (isFinished() || !isRunning())
        return;

    mutex.lock();
    quit();
    mutex.unlock();
}

void AiThread::resume()
{
    mutex.lock();
    pauseCondition.wakeAll();
    mutex.unlock();
}

void AiThread::stop()
{
    if (isFinished() || !isRunning())
        return;

    if (!isInterruptionRequested()) {
        requestInterruption();
        mutex.lock();
        quit();
        pauseCondition.wakeAll();
        mutex.unlock();
    }
}

///////////////

Depth AiThread::changeDepth()
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

    if (pos->phase & PHASE_PLACING) {
        if (rule.nTotalPiecesEachSide == 12) {
            d = placingDepthTable_12[rule.nTotalPiecesEachSide * 2 - pos->count<IN_HAND>(BLACK) - pos->count<IN_HAND>(WHITE)];
        } else {
            d = placingDepthTable_9[rule.nTotalPiecesEachSide * 2 - pos->count<IN_HAND>(BLACK) - pos->count<IN_HAND>(WHITE)];
        }
    }

    if (pos->phase & PHASE_MOVING) {
        int pb = pos->count<ON_BOARD>(BLACK);
        int pw = pos->count<ON_BOARD>(WHITE);

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
        if (rule.allowFlyWhenRemainThreePieces) {
            if (pb == rule.nPiecesAtLeast ||
                pw == rule.nPiecesAtLeast) {
                d = flyingDepth;
            }

            if (pb == rule.nPiecesAtLeast &&
                pw == rule.nPiecesAtLeast) {
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

void AiThread::setPosition(Position *p)
{
    if (strcmp(rule.name, rule.name) != 0) {
#ifdef TRANSPOSITION_TABLE_ENABLE
        TranspositionTable::clear();
#endif // TRANSPOSITION_TABLE_ENABLE

#ifdef ENDGAME_LEARNING
        // TODO: 规则改变时清空残局库
        //clearEndgameHashMap();
        //endgameList.clear();
#endif // ENDGAME_LEARNING

        moveHistory.clear();
    }

    //position = p;
    pos = p;
    // position = pos;

     //requiredQuit = false;
}


/// Thread::search() is the main iterative deepening loop. It calls search()
/// repeatedly with increasing depth until the allocated thinking time has been
/// consumed, the user stops the search, or the maximum search depth is reached.

int AiThread::search()
{
    Sanmill::Stack<Position> ss;

    Value value = VALUE_ZERO;

    Depth d = changeDepth();
    newDepth = d;

    time_t time0 = time(nullptr);
    srand(static_cast<unsigned int>(time0));

#ifdef TIME_STAT
    auto timeStart = chrono::steady_clock::now();
    chrono::steady_clock::time_point timeEnd;
#endif
#ifdef CYCLE_STAT
    auto cycleStart = stopwatch::rdtscp_clock::now();
    chrono::steady_clock::time_point cycleEnd;
#endif

#ifdef THREEFOLD_REPETITION
    static int nRepetition = 0;

    if (pos->get_phase() == PHASE_MOVING) {
        Key key = pos->key();

        if (std::find(moveHistory.begin(), moveHistory.end(), key) != moveHistory.end()) {
            nRepetition++;
            if (nRepetition == 3) {
                nRepetition = 0;
                return 3;
            }
        } else {
            moveHistory.push_back(key);
        }
    }

    if (pos->get_phase() == PHASE_PLACING) {
        moveHistory.clear();
    }
#endif // THREEFOLD_REPETITION

    MoveList<LEGAL>::shuffle();

    Value alpha = -VALUE_INFINITE;
    Value beta = VALUE_INFINITE;

    if (gameOptions.getIDSEnabled()) {
        loggerDebug("IDS: ");

        Depth depthBegin = 2;
        Value lastValue = VALUE_ZERO;

        loggerDebug("\n==============================\n");
        loggerDebug("==============================\n");
        loggerDebug("==============================\n");

        for (Depth i = depthBegin; i < d; i += 1) {
#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef CLEAR_TRANSPOSITION_TABLE
            TranspositionTable::clear();
#endif
#endif

#ifdef MTDF_AI
            value = MTDF(pos, ss, value, i, originDepth, bestMove);
#else
            value = search(pos, ss, i, originDepth, alpha, beta, bestMove);
#endif

            loggerDebug("%d(%d) ", value, value - lastValue);

            lastValue = value;
        }

#ifdef TIME_STAT
        timeEnd = chrono::steady_clock::now();
        loggerDebug("\nIDS Time: %llus\n", chrono::duration_cast<chrono::seconds>(timeEnd - timeStart).count());
#endif
    }

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef CLEAR_TRANSPOSITION_TABLE
    TranspositionTable::clear();
#endif
#endif

    if (gameOptions.getIDSEnabled()) {
        alpha = -VALUE_INFINITE;
        beta = VALUE_INFINITE;
    }

    originDepth = d;

#ifdef MTDF_AI
    value = MTDF(pos, ss, value, d, originDepth, bestMove);
#else
    value = search(pos, ss, d, originDepth, alpha, beta, bestMove);
#endif

#ifdef TIME_STAT
    timeEnd = chrono::steady_clock::now();
    loggerDebug("Total Time: %llus\n", chrono::duration_cast<chrono::seconds>(timeEnd - timeStart).count());
#endif

    lastvalue = bestvalue;
    bestvalue = value;

    return 0;
}

string AiThread::nextMove()
{
    return UCI::move(bestMove);

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

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef TRANSPOSITION_TABLE_DEBUG
    size_t hashProbeCount = ttHitCount + ttMissCount;
    if (hashProbeCount) {
        loggerDebug("[posKey] probe: %llu, hit: %llu, miss: %llu, hit rate: %llu%%\n",
                    hashProbeCount, ttHitCount, ttMissCount, ttHitCount * 100 / hashProbeCount);
    }
#endif // TRANSPOSITION_TABLE_DEBUG
#endif // TRANSPOSITION_TABLE_ENABLE

    if (foundBest == false) {
        loggerDebug("Warning: Best Move NOT Found\n");
    }

    return UCI::move(bestMove).c_str();
#endif
}

#ifdef ENDGAME_LEARNING
bool AiThread::findEndgameHash(key_t posKey, Endgame &endgame)
{
    return endgameHashMap.find(posKey, endgame);
}

int AiThread::recordEndgameHash(key_t posKey, const Endgame &endgame)
{
    //hashMapMutex.lock();
    key_t hashValue = endgameHashMap.insert(posKey, endgame);
    unsigned addr = hashValue * (sizeof(posKey) + sizeof(endgame));
    //hashMapMutex.unlock();

    loggerDebug("[endgame] Record 0x%08I32x (%d) to Endgame Hash map, TTEntry: 0x%08I32x, Address: 0x%08I32x\n", posKey, endgame.type, hashValue, addr);

    return 0;
}

void AiThread::clearEndgameHashMap()
{
    //hashMapMutex.lock();
    endgameHashMap.clear();
    //hashMapMutex.unlock();
}

void AiThread::recordEndgameHashMapToFile()
{
    const QString filename = "endgame.txt";
    endgameHashMap.dump(filename);

    loggerDebug("[endgame] Dump hash map to file\n");
}

void AiThread::loadEndgameFileToHashMap()
{
    const QString filename = "endgame.txt";
    endgameHashMap.load(filename);
}

#endif // ENDGAME_LEARNING
