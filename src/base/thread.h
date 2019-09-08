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

#ifndef AITHREAD_H
#define AITHREAD_H

#include <QThread>
#include <QMutex>
#include <QWaitCondition>
#include <QTimer>
#include "millgame.h"
#include "search.h"
#include "server.h"
#include "client.h"

class AiThread : public QThread
{
    Q_OBJECT

public:
    explicit AiThread(int id, QObject *parent = nullptr);
    ~AiThread() override;

signals:
    // 着法信号
    void command(const QString &cmdline, bool update = true);

    // 开始计算的信号
    void calcStarted();

    // 计算结束的信号
    void calcFinished();

protected:
    void run() override;

public:
    // AI设置
    void setAi(const MillGame &chess);
    void setAi(const MillGame &chess, depth_t depth, int time);

    Server *getServer()
    {
        return server;
    }

    Client *getClient()
    {
        return client;
    }

    // 深度和限时
    void getDepthTime(depth_t &depth, int &time)
    {
        depth = aiDepth;
        time = aiTime;
    }

public slots:
    // 强制出招，不退出线程
    void act();

    // 线程暂停
    void pause();

    // 线程继续
    void resume();

    // 退出线程
    void stop();

    // 发射着法信号
    void emitCommand();

private:
    // 玩家ID
    int id;

    // 发射的指令
    const char* strCommand {};

    // 互斥锁
    QMutex mutex;

    // 线程等待标识，这里没用到，留着以后扩展用
    bool waiting_;

    // 等待条件，这里没用到，留着以后扩展用
    QWaitCondition pauseCondition;

    // 主线程棋对象的引用
    const MillGame *chess_;

    // Alpha-Beta剪枝算法类
    MillGameAi_ab ai_ab;

    // AI的层数
    depth_t aiDepth;

    // AI的限时
    int aiTime;

    // 定时器
    QTimer timer;

    // 网络
    Server *server;
    Client *client;
};

#endif // AITHREAD_H
