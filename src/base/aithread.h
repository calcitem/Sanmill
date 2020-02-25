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

#ifndef AITHREAD_H
#define AITHREAD_H

#include <QThread>
#include <QMutex>
#include <QWaitCondition>
#include <QTimer>
#include "position.h"
#include "search.h"
#include "server.h"
#include "client.h"
#include "test.h"

class AiThread : public QThread
{
    Q_OBJECT

public:
    explicit AiThread(QObject *parent = nullptr);
    explicit AiThread(int id, QObject *parent = nullptr);
    ~AiThread() override;

signals:
    // 着法信号
    void command(const QString &cmdline, bool update = true);

    // 开始搜索的信号
    void searchStarted();

    // 计算搜索的信号
    void searchFinished();

protected:
    void run() override;

public:
    // AI设置
    void setAi(const Game &game);
    void setAi(const Game &game, depth_t depth, int time);

    Server *getServer()
    {
        return server;
    }

    Client *getClient()
    {
        return client;
    }

    // 深度和限时
    depth_t getDepth()
    {
        return depth;
    }

    int getTimeLimit()
    {
        return timeLimit;
    }

public slots:
    // 强制出招，不退出线程
    void act();

    // 线程继续
    void resume();

    // 退出线程
    void stop();

    // 发射着法信号
    void emitCommand();

public:
    // 玩家ID
    int playerId;

private:

    // 发射的指令
    const char* strCommand {};

    // 互斥锁
    QMutex mutex;

    // 等待条件，这里没用到，留着以后扩展用
    QWaitCondition pauseCondition;

public:
    // 主线程棋对象的引用
    const Game *game;

public: // TODO: Change to private
    // AI 算法类
    AIAlgorithm ai;

private:

    // AI的层数
    depth_t depth;

    // AI的限时
    int timeLimit;

    // 定时器
    QTimer timer;

    // 网络
    Server *server;
    Client *client;
};

#endif // AITHREAD_H
