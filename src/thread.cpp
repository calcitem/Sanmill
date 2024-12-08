// This file is part of Sanmill.
// See AUTHORS file for the list of contributors.
//
// Copyright (C) 2004-2024 The Stockfish developers
// Copyright (C) 2019-2024 The Sanmill developers
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

#include <iomanip>
#include <sstream>
#include <string>
#include <utility>

#include "mills.h"
#include "option.h"
#include "thread.h"
#include "uci.h"

#if defined(GABOR_MALOM_PERFECT_AI)
#include "perfect/perfect_adaptor.h"
#endif

#ifdef FLUTTER_UI
#include "engine_main.h"
#endif

#ifdef OPENING_BOOK
#include <deque>
#endif

using std::cout;
using std::string;

ThreadPool Threads; // Global object

/// Thread constructor launches the thread and waits until it goes to sleep
/// in idle_loop(). Note that 'searching' and 'exit' should be already set.

Thread::Thread(size_t n
#ifdef QT_GUI_LIB
               ,
               QObject *parent
#endif
               )
    :
#ifdef QT_GUI_LIB
    QObject(parent)
    ,
#endif
    idx(n)
    , stdThread(&Thread::idle_loop, this)
    , timeLimit(3600)
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

/// Thread::clear() reset histories, usually before a new game

void Thread::clear() noexcept
{
    // TODO(calcitem): Reset histories
    return;
}

/// Thread::start_searching() wakes up the thread that will start the search

void Thread::start_searching()
{
    std::lock_guard lk(mutex);
    searching = true;
    cv.notify_one(); // Wake up the thread in idle_loop()
}

void Thread::pause()
{
    std::lock_guard lk(mutex);
    searching = false;
    cv.notify_one(); // Wake up the thread in idle_loop()
}

/// Thread::wait_for_search_finished() blocks on the condition variable
/// until the thread has finished searching.

void Thread::wait_for_search_finished()
{
    std::unique_lock lk(mutex);
    cv.wait(lk, [&] { return !searching; });
}

#ifdef NNUE_GENERATE_TRAINING_DATA
extern Value nnueTrainingDataBestValue;
#endif /* NNUE_GENERATE_TRAINING_DATA */

/// Thread::idle_loop() is where the thread is parked, blocked on the
/// condition variable, when it has no work to do.

void Thread::idle_loop()
{
    while (true) {
        std::unique_lock lk(mutex);

        // Wait until we have work (searching == true) or we should exit
        // 此时不改变 searching, 保持上次的状态即可
        // 保证每一次 loop 开始都先等待条件满足后再继续
        cv.notify_all();
        cv.wait(lk, [this] { return searching || exit; });

        if (exit) {
            // 线程即将结束
            return;
        }

        // 如果有并行搜索任务
        if (hasTask) {
            // 有任务：解锁并执行任务
            lk.unlock();
            do_task();
            lk.lock();
            // 任务完成后标记 searching = false, 通知等待的线程
            hasTask = false;
            searching = false;
            cv.notify_all();
            // 任务结束后将继续循环等待新的任务或退出
            continue;
        }

        // 此处表示没有并行任务
        // 如果 rootPos 为 null 或者不是当前 us 的回合，那么无需搜索
        if (!rootPos || rootPos->side_to_move() != us) {
            // 没有可执行的搜索: 将 searching = false 并通知
            searching = false;
            cv.notify_all();
            // 再次循环进入等待状态
            continue;
        }

        // 如果有 rootPos，并且是 us 的回合，则执行主搜索逻辑
        // 解锁执行搜索
        lk.unlock();

#ifdef OPENING_BOOK
        if (!openingBookDeque.empty()) {
            char obc[16] = {0};
            sq2str(obc);
            bestMoveString = obc;
            emitCommand();

            // 处理完后重新加锁并将 searching = false
            lk.lock();
            searching = false;
            cv.notify_all();
            lk.unlock();
        } else {
#endif
            // 执行主搜索
            const int ret = search();

#ifdef NNUE_GENERATE_TRAINING_DATA
            nnueTrainingDataBestValue = (rootPos->sideToMove == WHITE) ?
                                            bestvalue :
                                            -bestvalue;
#endif

            if (ret == 3 || ret == 50 || ret == 10) {
                debugPrintf("Draw\n\n");
                bestMoveString = "draw";
                emitCommand();
            } else {
                bestMoveString = next_move();
                if (!bestMoveString.empty() && bestMoveString != "error!") {
                    emitCommand();
                }
            }

            lk.lock();
            searching = false; // 搜索完成，通知可能等待此状态的线程
            cv.notify_all();
            lk.unlock();

#ifdef OPENING_BOOK
        }
#endif
    }
}

////////////////////////////////////////////////////////////////////////////

void Thread::setAi(Position *p)
{
    std::lock_guard lk(mutex);

    this->rootPos = p;

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef CLEAR_TRANSPOSITION_TABLE
    TranspositionTable::clear();
#endif
#endif
}

void Thread::setAi(Position *p, int time)
{
    setAi(p);

    timeLimit = time;
}

void Thread::emitCommand()
{
    std::ostringstream ss;
    std::string aiMoveTypeStr;

    if (rootPos->sideToMove == BLACK) {
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

    ss << "info score " << (int)bestvalue << aiMoveTypeStr << " bestmove "
       << bestMoveString;

#ifdef QT_GUI_LIB
    emit command(ss.str()); // Origin: bestMoveString
#else
    sync_cout << ss.str();
    std::cout << sync_endl;

#ifdef FLUTTER_UI
    println(ss.str().c_str());
#endif

#ifdef UCI_DO_BEST_MOVE
    rootPos->command(ss.str());
    us = rootPos->side_to_move();

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

#ifdef OPENING_BOOK
deque<int> openingBookDeque({
    /* B W */
    21,
    23,
    19,
    20,
    17,
    18,
    15,
});

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

void Thread::analyze(Color c) const
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

    const string strUs = (c == WHITE ? "White" : "Black");
    const string strThem = (c == WHITE ? "Black" : "White");

    const auto flags = cout.flags();

    debugPrintf("Depth: %d\n\n", originDepth);

    const Position *p = rootPos;

    cout << *p << std::endl;
    cout << std::dec;

    switch (p->get_phase()) {
    case Phase::ready:
        cout << "Ready phrase" << std::endl;
        break;
    case Phase::placing:
        cout << "Placing phrase" << std::endl;
        break;
    case Phase::moving:
        cout << "Moving phase" << std::endl;
        break;
    case Phase::gameOver:
        if (p->get_winner() == DRAW) {
            cout << "Draw" << std::endl;
#ifndef QT_GUI_LIB
            nDraw += 0.5f; // TODO(calcitem)
#endif
        } else if (p->get_winner() == WHITE) {
            cout << "White wins" << std::endl;
#ifndef QT_GUI_LIB
            nBlackWin += 0.5f; // TODO(calcitem)
#endif
        } else if (p->get_winner() == BLACK) {
            cout << "Black wins" << std::endl;
#ifndef QT_GUI_LIB
            nWhiteWin += 0.5f; // TODO(calcitem)
#endif
        }
        cout << std::endl << std::endl;
        return;
    case Phase::none:
        cout << "None phase" << std::endl;
        break;
    }

    if (v == VALUE_UNIQUE) {
        cout << "Unique move" << std::endl << std::endl << std::endl;
        return;
    }

    if (lv < -VALUE_EACH_PIECE && v == 0) {
        cout << strThem << " made a bad move, " << strUs
             << " pulled back the balance of power!" << std::endl;
    }

    if (lv < 0 && v > 0) {
        cout << strThem << " made a bad move, " << strUs
             << " reversed the situation!" << std::endl;
    }

    if (lv == 0 && v > VALUE_EACH_PIECE) {
        cout << strThem << "Bad move!" << std::endl;
    }

    if (lv > VALUE_EACH_PIECE && v == 0) {
        cout << strThem << "made a good move, pulled back the balance of power"
             << std::endl;
    }

    if (lv > 0 && v < 0) {
        cout << strThem << "made a good move, reversed the situation!"
             << std::endl;
    }

    if (lv == 0 && v < -VALUE_EACH_PIECE) {
        cout << strThem << " made a good move!" << std::endl;
    }

    if (lv != v) {
        if (lv < 0 && v < 0) {
            if (abs(lv) < abs(v)) {
                cout << strThem << " has expanded its lead" << std::endl;
            } else if (abs(lv) > abs(v)) {
                cout << strThem << " has narrowed its lead" << std::endl;
            }
        }

        if (lv > 0 && v > 0) {
            if (abs(lv) < abs(v)) {
                cout << strThem << " has expanded its lead" << std::endl;
            } else if (abs(lv) > abs(v)) {
                cout << strThem << " has narrowed its backwardness"
                     << std::endl;
            }
        }
    }

    if (win) {
        cout << strThem << " will lose in " << d << " moves!" << std::endl;
    } else if (lose) {
        cout << strThem << " will win in " << d << " moves!" << std::endl;
    } else if (np == 0) {
        cout << "The two sides will maintain a balance of power after " << d
             << " moves" << std::endl;
    } else if (np > 0) {
        cout << strThem << " after " << d << " moves will backward " << np
             << " pieces" << std::endl;
    } else if (np < 0) {
        cout << strThem << " after " << d << " moves will lead " << -np
             << " pieces" << std::endl;
    }

    if (p->side_to_move() == WHITE) {
        cout << "White to move" << std::endl;
    } else {
        cout << "Black to move" << std::endl;
    }

#ifndef QT_GUI_LIB
    total = nBlackWin + nWhiteWin + nDraw;

    if (total < 0.01) {
        blackWinRate = 0;
        whiteWinRate = 0;
        drawRate = 0;
    } else {
        blackWinRate = nBlackWin * 100 / total;
        whiteWinRate = nWhiteWin * 100 / total;
        drawRate = nDraw * 100 / total;
    }

    cout << "Score: " << static_cast<int>(nBlackWin) << " : "
         << static_cast<int>(nWhiteWin) << " : " << static_cast<int>(nDraw)
         << "\ttotal: " << static_cast<int>(total) << std::endl;
    cout << std::fixed << std::setprecision(2) << blackWinRate
         << "% : " << whiteWinRate << "% : " << drawRate << "%" << std::endl;
#endif // !QT_GUI_LIB

    cout.flags(flags);

    cout << std::endl << std::endl;
}

Depth Thread::get_depth() const
{
    return Mills::get_search_depth(rootPos);
}

string Thread::get_value() const
{
    string value = std::to_string(bestvalue);
    return value;
}

string Thread::next_move() const
{
#ifdef ENDGAME_LEARNING
    // Check if very weak
    if (gameOptions.isEndgameLearningEnabled()) {
        if (bestvalue <= -VALUE_KNOWN_WIN) {
            Endgame endgame;
            endgame.type = rootPos->side_to_move() == WHITE ?
                               EndGameType::blackWin :
                               EndGameType::whiteWin;
            Key endgameHash = rootPos->key(); // TODO(calcitem): Do not generate
                                              // hash repeatedly
            saveEndgameHash(endgameHash, endgame);
        }
    }
#endif /* ENDGAME_LEARNING */

    if (gameOptions.getResignIfMostLose() == true) {
        if (bestvalue <= -VALUE_MATE) {
            rootPos->set_gameover(~rootPos->sideToMove,
                                  GameOverReason::loseResign);
            snprintf(rootPos->record, Position::RECORD_LEN_MAX,
                     LOSE_REASON_PLAYER_RESIGNS, rootPos->sideToMove);
            return rootPos->record;
        }
    }

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef TRANSPOSITION_TABLE_DEBUG
    size_t hashProbeCount = ttHitCount + ttMissCount;
    if (hashProbeCount) {
        debugPrintf("[posKey] probe: %llu, hit: %llu, miss: %llu, hit rate: "
                    "%llu%%\n",
                    hashProbeCount, ttHitCount, ttMissCount,
                    ttHitCount * 100 / hashProbeCount);
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

    debugPrintf("[endgame] Record 0x%08I32x (%d) to Endgame hash map, TTEntry: "
                "0x%08I32x, Address: 0x%08I32x\n",
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

    debugPrintf("[endgame] Dump hash map to file\n");
}

void Thread::loadEndgameFileToHashMap()
{
    const string filename = "endgame.txt";
    endgameHashMap.load(filename);
}

#endif // ENDGAME_LEARNING

Value search(Position *pos, Sanmill::Stack<Position> &ss, Depth depth,
             Depth originDepth, Value alpha, Value beta, Move &bestMove);

void Thread::do_task()
{
    // Instead of using pos directly, create a local copy of pos
    Position localPos = *currentTask.pos;

    Depth depth = currentTask.depth;
    Depth origDepth = currentTask.originDepth;
    Value alpha = currentTask.alpha;
    Value beta = currentTask.beta;

    Value bestValue = -VALUE_INFINITE;
    Move best_local_move = MOVE_NONE;

    // For each move in the assigned subset
    for (Move m : currentTask.moves) {
        if (Threads.stop.load(std::memory_order_relaxed))
            break;

        // Use the local position copy and stack
        Sanmill::Stack<Position> ss;
        ss.push(localPos);

        const Color before = localPos.sideToMove;
        localPos.do_move(m);
        const Color after = localPos.sideToMove;

        Move tempBest = MOVE_NONE;
        Value value = (after != before) ?
                          -::search(&localPos, ss, depth - 1, origDepth, -beta,
                                    -alpha, tempBest) :
                          ::search(&localPos, ss, depth - 1, origDepth, alpha,
                                   beta, tempBest);

        localPos.undo_move(ss);

        if (value > bestValue) {
            bestValue = value;
            best_local_move = m;
            if (value > alpha) {
                alpha = value;
                if (alpha >= beta) {
                    break;
                }
            }
        }
    }

    // Update thread local best result
    localBestValue = bestValue;
    localBestMove = best_local_move;
}

/// ThreadPool::set() creates/destroys threads to match the requested number.
/// Created and launched threads will immediately go to sleep in idle_loop.
/// Upon resizing, threads are recreated to allow for binding if necessary.

void ThreadPool::set(size_t requested)
{
    if (!empty()) {
        // destroy any existing thread(s)
        main()->wait_for_search_finished();

        while (!empty()) {
            delete back();
            pop_back();
        }
    }

    if (requested > 0) {
        // create new thread(s)
        push_back(new MainThread(0));

        while (size() < requested)
            push_back(new Thread(size()));
        clear();

#ifdef TRANSPOSITION_TABLE_ENABLE
        // Reallocate the hash with the new thread pool size
        // TT.resize(static_cast<size_t>(Options["Hash"]));
#endif

        // Init thread number dependent search params.
        Search::init();
    }
}

/// ThreadPool::clear() sets threadPool data to initial values.

void ThreadPool::clear() const
{
    for (const Thread *th : *this)
        th->clear();
}

/// ThreadPool::start_thinking() wakes up main thread waiting in idle_loop() and
/// returns immediately. Main thread will wake up other threads and start the
/// search.

void ThreadPool::start_thinking(Position *pos, bool ponderMode)
{
    main()->wait_for_search_finished();

    main()->stopOnPonderhit = stop = false;
    increaseDepth = true;
    main()->ponder = ponderMode;

    // We use Position::set() to set root position across threads.
    for (Thread *th : *this) {
        // Fix CID 338443: Data race condition (MISSING_LOCK)
        // missing_lock: Accessing th->rootPos without holding lock
        // Thread.mutex. Elsewhere, Thread.rootPos is accessed with Thread.mutex
        // held 1 out of 2 times (1 of these accesses strongly imply that it is
        // necessary).
        std::lock_guard lk(th->mutex);
        th->rootPos = pos;
    }

    main()->start_searching();
}

void ThreadPool::parallel_search(Position *pos, Depth depth, Depth originDepth,
                                 Value alpha, Value beta,
                                 const std::vector<Move> &moves)
{
    size_t threadCount = size();
    size_t movesPerThread = (moves.size() + threadCount - 1) / threadCount;

    size_t startIndex = 0;
    for (size_t i = 0; i < threadCount; i++) {
        size_t endIndex = std::min(startIndex + movesPerThread, moves.size());
        std::vector<Move> subset(moves.begin() + startIndex,
                                 moves.begin() + endIndex);
        startIndex = endIndex;

        {
            std::lock_guard<std::mutex> lk((*this)[i]->mutex);
            (*this)[i]->currentTask.pos = pos;
            (*this)[i]->currentTask.depth = depth;
            (*this)[i]->currentTask.originDepth = originDepth;
            (*this)[i]->currentTask.alpha = alpha;
            (*this)[i]->currentTask.beta = beta;
            (*this)[i]->currentTask.moves = std::move(subset);
            (*this)[i]->hasTask = true;
            (*this)[i]->searching = true;
            (*this)[i]->cv.notify_one();
        }
    }

    // 等待所有线程任务完成
    for (Thread *th : *this) {
        th->wait_for_search_finished();
    }

    // 合并结果：选出所有线程中最好值的走子
    Value globalBest = -VALUE_INFINITE;
    Move globalBestMove = MOVE_NONE;
    for (Thread *th : *this) {
        if (th->localBestValue > globalBest) {
            globalBest = th->localBestValue;
            globalBestMove = th->localBestMove;
        }
    }

    // globalBestMove 与 globalBest 是并行搜索的最终结果
    // 可将其赋予主线程或返回调用者使用
    main()->bestMove = globalBestMove;
    main()->bestvalue = globalBest;
}
