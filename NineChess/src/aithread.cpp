/*****************************************************************************
 * Copyright (C) 2018-2019 NineChess authors
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

#include <QDebug>
#include "aithread.h"

AiThread::AiThread(int id, QObject *parent) :
    QThread(parent),
    chess_(nullptr),
    waiting_(false),
    aiDepth(2),
    aiTime(120)
{
    this->id = id;

    // 连接定时器启动，减去118毫秒的返回时间
    connect(this, &AiThread::calcStarted, this, [=]() {timer.start(aiTime * 1000 - 118); }, Qt::QueuedConnection);

    // 连接定时器停止
    connect(this, &AiThread::calcFinished, this, [=]() {timer.stop(); }, Qt::QueuedConnection);

    // 连接定时器处理函数
    connect(&timer, &QTimer::timeout, this, &AiThread::act, Qt::QueuedConnection);
}

AiThread::~AiThread()
{
    stop();
    quit();
    wait();
}

void AiThread::setAi(const NineChess &chess)
{
    mutex.lock();

    this->chess_ = &chess;
    ai_ab.setChess(*(this->chess_));

#ifdef HASH_MAP_ENABLE
    // 新下一盘前清除哈希表 (注意可能同时存在每步之前清除)
    ai_ab.clearHashMap();
#endif

    mutex.unlock();
}

void AiThread::setAi(const NineChess &chess, int depth, int time)
{
    mutex.lock();
    this->chess_ = &chess;
    ai_ab.setChess(chess);
    aiDepth = depth;
    aiTime = time;
    mutex.unlock();
}

void AiThread::run()
{
    // 测试用数据
#ifdef DEBUG_MODE
    int iTemp = 0;
#endif

    // 设一个标识，1号线程只管玩家1，2号线程只管玩家2
    int i = 0;

    qDebug() << "Thread" << id << "start";

    while (!isInterruptionRequested()) {
        mutex.lock();

        if (chess_->whosTurn() == NineChess::PLAYER1)
            i = 1;
        else if (chess_->whosTurn() == NineChess::PLAYER2)
            i = 2;
        else
            i = 0;

        if (i != id || waiting_) {
            pauseCondition.wait(&mutex);
            mutex.unlock();
            continue;
        }

        ai_ab.setChess(*chess_);
        emit calcStarted();
        mutex.unlock();

        if (ai_ab.alphaBetaPruning(aiDepth) == 3) {
            qDebug() << "Draw\n";
            const char *str = "draw";
            emit command(str);
        } else {
            const char *str = ai_ab.bestMove();
            qDebug() << "Computer:" << str << "\n";
            if (strcmp(str, "error!"))
                emit command(str);
        }

#ifdef DEBUG_MODE
        qDebug() << "Thread" << id << "run" << ++iTemp << "times";
#endif

        emit calcFinished();

        // 执行完毕后继续判断
        mutex.lock();
        if (!isInterruptionRequested()) {
            pauseCondition.wait(&mutex);
        }
        mutex.unlock();
    }
    qDebug() << "Thread" << id << "quit";
}

void AiThread::act()
{
    if (isFinished() || !isRunning())
        return;

    mutex.lock();
    waiting_ = false;
    ai_ab.quit();
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
        ai_ab.quit();
        pauseCondition.wakeAll();
        mutex.unlock();
    }
}
