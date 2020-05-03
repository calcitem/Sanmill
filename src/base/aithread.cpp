﻿/*
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
#include "player.h"

#ifdef OPENING_BOOK
#include <deque>
using namespace std;
#endif

AiThread::AiThread(int id, QObject *parent) :
    QThread(parent),
    state(nullptr),
    depth(2),
    timeLimit(3600)
{
    this->playerId = id;

    // 连接定时器启动，减去118毫秒的返回时间
    connect(this, &AiThread::searchStarted, this, [=]() {timer.start(timeLimit * 1000 - 118); }, Qt::QueuedConnection);

    // 连接定时器停止
    connect(this, &AiThread::searchFinished, this, [=]() {timer.stop(); }, Qt::QueuedConnection);

    // 连接定时器处理函数
    connect(&timer, &QTimer::timeout, this, &AiThread::act, Qt::QueuedConnection);

#ifndef TRAINING_MODE
    // 网络
    if (id == 1) {
        server = new Server(nullptr, 30001);    // TODO: WARNING: ThreadSanitizer: data race
        uint16_t clientPort = server->getPort() == 30001 ? 30002 : 30001;
        client = new Client(nullptr, clientPort);
    }
#endif  // TRAINING_MODE
}

AiThread::~AiThread()
{
    // 网络相关
    //delete server;
    //delete client;

    stop();
    quit();
    wait();
}

void AiThread::setAi(const StateInfo &g)
{
    mutex.lock();

    this->state = &g;
    ai.setState(*(this->state));

#ifdef TRANSPOSITION_TABLE_ENABLE
    // 新下一盘前清除哈希表 (注意可能同时存在每步之前清除)
#ifdef CLEAR_TRANSPOSITION_TABLE
    TT::clear();
#endif
#endif

    mutex.unlock();
}

void AiThread::setAi(const StateInfo &g, depth_t d, int tl)
{
    mutex.lock();
    this->state = &g;
    ai.setState(g);
    depth = d;
    timeLimit = tl;
    mutex.unlock();
}

void AiThread::emitCommand()
{
    emit command(strCommand);
}

#ifdef MCTS_AI
move_t computeMove(StateInfo state,
                   const MCTSOptions options);
#endif // MCTS_AI

#ifdef OPENING_BOOK
deque<int> openingBookDeque(
    {
        /* B W */
        21, 23,
        19, 20,
        17, 18,
        15, 10,
        26, 12,
        28, 11,
        27, 9, -15,
        29, -12, 25,
        13, -25
    }
);

deque<int> openingBookDequeBak;

void sq2str(char *str)
{
    int sq = openingBookDeque.front();
    openingBookDeque.pop_front();
    openingBookDequeBak.push_back(sq);

    int r = 0;
    int s = 0;
    int sig = 1;

    if (sq < 0) {
        sq = -sq;
        sig = 0;
    }

    Board::squareToPolar((square_t)sq, r, s);

    if (sig == 1) {
        sprintf_s(str, 16, "(%d,%d)", r, s);
    } else {
        sprintf_s(str, 16, "-(%d,%d)", r, s);
    }
}
#endif // OPENING_BOOK

void AiThread::run()
{
    // 测试用数据
#ifdef DEBUG_MODE
    int iTemp = 0;
#endif

    // 设一个标识，1号线程只管玩家1，2号线程只管玩家2
    int sideId = 0;

    loggerDebug("Thread %d start\n", playerId);

    while (!isInterruptionRequested()) {
        mutex.lock();

        sideId = Player::toId(state->position->sideToMove);

        if (sideId != playerId) {
            pauseCondition.wait(&mutex);
            mutex.unlock();
            continue;
        }

        ai.setState(*state);
        emit searchStarted();
        mutex.unlock();

#ifdef MCTS_AI
        MCTSOptions mctsOptions;

        move_t move = ai.computeMove(*state, mctsOptions);
        
        strCommand = ai.moveToCommand(move);
        emitCommand();
#else  // MCTS_AI

#ifdef OPENING_BOOK
        // gameOptions.getOpeningBook()
        if (!openingBookDeque.empty()) {
            char obc[16] = { 0 };
            sq2str(obc);
            strCommand = obc;
            emitCommand();
        } else {
#endif
            if (ai.search(depth) == 3) {
                // 三次重复局面和
                loggerDebug("Draw\n\n");
                strCommand = "draw";
                emitCommand();
            } else {
                strCommand = ai.ttMove();
                if (strCommand && strcmp(strCommand, "error!") != 0) {
                    loggerDebug("Computer: %s\n\n", strCommand);
                    emitCommand();
                }
            }
#ifdef OPENING_BOOK
        }
#endif

#endif // MCTS_AI

        emit searchFinished();

        // 执行完毕后继续判断
        mutex.lock();
        if (!isInterruptionRequested()) {
            pauseCondition.wait(&mutex);
        }
        mutex.unlock();
    }

    loggerDebug("Thread %d quit\n", playerId);
}

void AiThread::act()
{
    if (isFinished() || !isRunning())
        return;

    mutex.lock();
    ai.quit();
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
        ai.quit();
        pauseCondition.wakeAll();
        mutex.unlock();
    }
}
