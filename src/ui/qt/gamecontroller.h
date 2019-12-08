/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2015-2018 liuweilhy (NineChess author)
  Copyright (C) 2019 Calcitem <calcitem@outlook.com>

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

/* 这个类处理场景对象QGraphicsScene
 * 它是本程序MVC模型中唯一的控制模块
 * 它不对主窗口中的控件做任何操作，只向主窗口发出信号
 * 本来可以重载QGraphicsScene实现它，还能省去写事件过滤器的麻烦
 * 但用一个场景类做那么多控制模块的操作看上去不太好
 */

#ifndef GAMECONTROLLER_H
#define GAMECONTROLLER_H

#include <map>
#include <vector>

#include <QTime>
#include <QPointF>
#include <QTextStream>
#include <QStringListModel>
#include <QModelIndex>

#include "position.h"
#include "gamescene.h"
#include "pieceitem.h"
#include "aithread.h"
#include "server.h"
#include "client.h"
#include "stopwatch.h"

using namespace std;

class GameController : public QObject
{
    Q_OBJECT

public:
    GameController(
#ifndef TRAINING_MODE
        GameScene &scene,
#endif
        QObject *parent = nullptr
    );
    ~GameController() override;

    //主窗口菜单栏明细
    const map<int, QStringList> getActions();

    int getRuleIndex()
    {
        return ruleIndex;
    }

    int getTimeLimit()
    {
        return timeLimit;
    }

    int getStepsLimit()
    {
        return stepsLimit;
    }

    bool isAnimation()
    {
        return hasAnimation;
    }

    void setDurationTime(int i)
    {
        durationTime = i;
    }

    int getDurationTime()
    {
        return durationTime;
    }

    QStringListModel *getManualListModel()
    {
        return &manualListModel;
    }

    void setAiDepthTime(depth_t depth1, int time1, depth_t depth2, int time2);
    void getAiDepthTime(depth_t &depth1, int &time1, depth_t &depth2, int &time2);

signals:

    // 玩家1(先手）赢盘数改变的信号
    void score1Changed(const QString &score);

    // 玩家2(后手）赢盘 数改变的信号
    void score2Changed(const QString &score);

    // 和棋数改变的信号
    void scoreDrawChanged(const QString &score);

    // 玩家1(先手）用时改变的信号
    void time1Changed(const QString &time);

    // 玩家2(后手）用时改变的信号
    void time2Changed(const QString &time);

    // 通知主窗口更新状态栏的信号
    void statusBarChanged(const QString &message);

public slots:

    // 设置规则
    void setRule(int ruleNo, step_t stepLimited = std::numeric_limits<uint16_t>::max(), int timeLimited = -1);

    // 游戏开始
    void gameStart();

    // 游戏重置
    void gameReset();

    // 设置编辑棋局状态
    void setEditing(bool arg = true);

    // 设置黑白反转状态
    void setInvert(bool arg = true);

    // id为1时让电脑执先手, id为2时让的电脑执后手
    void setEngine(int id, bool arg = true);
    void setEngine1(bool arg);
    void setEngine2(bool arg);

    // 是否有落子动画
    void setAnimation(bool arg = true);

    // 是否有落子音效
    void setSound(bool arg = true);

    // 播放声音
    void playSound(const QString &soundPath);

    // 是否必败时认输
    void setGiveUpIfMostLose(bool enabled);

    // 是否自动开局
    void setAutoRestart(bool enabled = false);

    // AI 是否随机走子
    void setRandomMove(bool enabled);

    // AI 是否记录残局库
    void setLearnEndgame(bool enabled);

    // 上下翻转
    void flip();

    // 左右镜像
    void mirror();

    // 视图须时针旋转90°
    void turnRight();

    // 视图逆时针旋转90°
    void turnLeft();

    bool isAIsTurn();

    void threadsSetAi(const Game &g)
    {
        aiThread[BLACK]->setAi(g);
        aiThread[WHITE]->setAi(g);
    }

    void resetAiPlayers()
    {
        isAiPlayer[BLACK] = false;
        isAiPlayer[WHITE] = false;
    }

    void createAiThreads()
    {
        aiThread[BLACK] = new AiThread(1);
        aiThread[WHITE] = new AiThread(2);
    }

    void startAiThreads()
    {
        if (isAiPlayer[BLACK]) {
            aiThread[BLACK]->start();
        }

        if (isAiPlayer[WHITE]) {
            aiThread[WHITE]->start();
        }
    }

    void stopAndWaitAiThreads()
    {
        if (isAiPlayer[BLACK]) {
            aiThread[BLACK]->stop();
            aiThread[BLACK]->wait();
        }
        if (isAiPlayer[WHITE]) {
            aiThread[WHITE]->stop();
            aiThread[WHITE]->wait();
        }
    }

    void stopThreads()
    {
        aiThread[BLACK]->stop();
        aiThread[WHITE]->stop();
    }

    void waitThreads()
    {
        aiThread[BLACK]->wait();
        aiThread[WHITE]->wait();
    }

    void stopAndWaitThreads()
    {
        stopThreads();
        waitThreads();
    }

    void resumeAiThreads(player_t sideToMove)
    {
        if (sideToMove == PLAYER_BLACK) {
            if (isAiPlayer[BLACK]) {
                aiThread[BLACK]->resume();
            }
        } else {
            if (isAiPlayer[WHITE]) {
                aiThread[WHITE]->resume();
            }
        }
    }

    void deleteAiThreads()
    {
        delete aiThread[BLACK];
        delete aiThread[WHITE];
    }

    // 根据QGraphicsScene的信号和状态来执行选子、落子或去子
    bool actionPiece(QPointF p);

    // 认输
    bool giveUp();

    // 棋谱的命令行执行
    bool command(const QString &cmd, bool update = true);

    // 历史局面及局面改变
    bool phaseChange(int row, bool forceUpdate = false);

    // 更新棋局显示，每步后执行才能刷新局面
    bool updateScence();
    bool updateScence(Game &game);

    // 显示网络配置窗口
    void showNetworkWindow();

    void saveScore();

#ifdef TEST_MODE
    // 定时器超时
    void onTimeOut();
#endif // TEST_MODE

protected:
    //bool eventFilter(QObject * watched, QEvent * event);
    // 定时器
    void timerEvent(QTimerEvent *event) override;

private:
    // 棋对象的数据模型
    Game game;

    // 棋对象的数据模型（临时）
    Game tempGame;

#ifdef TEST_MODE
    // 测试
    Test *gameTest;
#endif // TEST_MODE

private:
    // 2个AI的线程
    AiThread *aiThread[COLOR_COUNT];

#ifndef TRAINING_MODE
    // 棋局的场景类
    GameScene &scene;
#endif

    // 所有棋子
    vector<PieceItem *> pieceList;

    // 当前棋子
    PieceItem *currentPiece;

    // 当前浏览的棋谱行
    int currentRow;

    // 是否处于“编辑棋局”状态
    bool isEditing;

    // 是否黑白反转
    bool isInverted;

public:
    // 电脑执先手时为 true
    bool isAiPlayer[COLOR_COUNT];

private:
    // 是否有落子动画
    bool hasAnimation;

    // 动画持续时间
    int durationTime;

    // 游戏开始时间
    TimePoint gameStartTime;

    // 游戏结束时间
    TimePoint gameEndTime;

    // 游戏持续时间
    TimePoint gameDurationTime;

    // 游戏开始周期
    stopwatch::rdtscp_clock::time_point gameStartCycle;

    // 游戏结束周期
    stopwatch::rdtscp_clock::time_point gameEndCycle;

    // 游戏持续周期
    stopwatch::rdtscp_clock::duration gameDurationCycle;

    // 是否有落子音效
    bool hasSound;

    // 是否必败时认输
    bool giveUpIfMostLose_ {false};

    // 定时器ID
    int timeID;

    // 规则号
    int ruleIndex;

    // 规则限时（分钟）
    int timeLimit;

    // 规则限步数
    step_t stepsLimit;

    // 玩家剩余时间（秒）
    time_t remainingTime[COLOR_COUNT];

    // 用于主窗口状态栏显示的字符串
    QString message;

    // 棋谱字符串列表模型
    QStringListModel manualListModel;

    // 读取共享内存的定时器
    QTimer *readMemoryTimer;
};

#endif // GAMECONTROLLER_H
