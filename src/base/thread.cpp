/*****************************************************************************
 * Copyright (C) 2018-2019 MillGame authors
 *
 * Authors: liuweilhy <liuweilhy@163.com>
 *          Calcitem <calcitem@outlook.com>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#include <QTimer>
#include "thread.h"
#include "tt.h"
#include "player.h"

AiThread::AiThread(int id, QObject *parent) :
    QThread(parent),
    waiting_(false),
    game_(nullptr),
    aiDepth(2),
    aiTime(3600)
{
    this->id = id;

    // 连接定时器启动，减去118毫秒的返回时间
    connect(this, &AiThread::calcStarted, this, [=]() {timer.start(aiTime * 1000 - 118); }, Qt::QueuedConnection);

    // 连接定时器停止
    connect(this, &AiThread::calcFinished, this, [=]() {timer.stop(); }, Qt::QueuedConnection);

    // 连接定时器处理函数
    connect(&timer, &QTimer::timeout, this, &AiThread::act, Qt::QueuedConnection);

    // 网络
    if (id == 1) {
        server = new Server(nullptr, 30001);    // TODO: WARNING: ThreadSanitizer: data race
        uint16_t clientPort = server->getPort() == 30001 ? 30002 : 30001;
        client = new Client(nullptr, clientPort);
    }
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

void AiThread::setAi(const Game &game)
{
    mutex.lock();

    this->game_ = &game;
    ai.setGame(*(this->game_));

#ifdef TRANSPOSITION_TABLE_ENABLE
    // 新下一盘前清除哈希表 (注意可能同时存在每步之前清除)
#ifdef CLEAR_TRANSPOSITION_TABLE
    TranspositionTable::clearTranspositionTable();
#endif
#endif

    mutex.unlock();
}

void AiThread::setAi(const Game &game, depth_t depth, int time)
{
    mutex.lock();
    this->game_ = &game;
    ai.setGame(game);
    aiDepth = depth;
    aiTime = time;
    mutex.unlock();
}

void AiThread::emitCommand()
{
    emit command(strCommand);
}

void AiThread::run()
{
    // 测试用数据
#ifdef DEBUG_MODE
    int iTemp = 0;
#endif

    // 设一个标识，1号线程只管玩家1，2号线程只管玩家2
    int i = 0;

    loggerDebug("Thread %d start\n", id);

    while (!isInterruptionRequested()) {
        mutex.lock();

        i = Player::toId(game_->position.turn);

        if (i != id || waiting_) {
            pauseCondition.wait(&mutex);
            mutex.unlock();
            continue;
        }

        ai.setGame(*game_);
        emit calcStarted();
        mutex.unlock();

        if (ai.alphaBetaPruning(aiDepth) == 3) {
            // 三次重复局面和
            loggerDebug("Draw\n\n");
            strCommand = "draw";
            QTimer::singleShot(EMIT_COMMAND_DELAY, this, &AiThread::emitCommand);
        } else {
            strCommand = ai.bestMove();
            if (strCommand && strcmp(strCommand, "error!") != 0) {
                loggerDebug("Computer: %s\n\n", strCommand);
                QTimer::singleShot(EMIT_COMMAND_DELAY, this, &AiThread::emitCommand);
            }
        }

        emit calcFinished();

        // 执行完毕后继续判断
        mutex.lock();
        if (!isInterruptionRequested()) {
            pauseCondition.wait(&mutex);
        }
        mutex.unlock();
    }

    loggerDebug("Thread %d quit\n", id);
}

void AiThread::act()
{
    if (isFinished() || !isRunning())
        return;

    mutex.lock();
    waiting_ = false;
    ai.quit();
    mutex.unlock();
}

void AiThread::pause()
{
    mutex.lock();
    waiting_ = true;
    mutex.unlock();
}

void AiThread::resume()
{
    mutex.lock();
    waiting_ = false;
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
        waiting_ = false;
        ai.quit();
        pauseCondition.wakeAll();
        mutex.unlock();
    }
}
