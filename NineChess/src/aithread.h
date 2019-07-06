#ifndef AITHREAD_H
#define AITHREAD_H

#include <QThread>
#include <QMutex>
#include <QWaitCondition>
#include <QTimer>
#include "ninechess.h"
#include "ninechessai_ab.h"

class AiThread : public QThread
{
    Q_OBJECT

public:
    explicit AiThread(int id, QObject *parent = nullptr);
    ~AiThread();

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
    void setAi(const NineChess &chess);
    void setAi(const NineChess &chess, int depth, int time);

    // 深度和限时
    void getDepthTime(int &depth, int &time)
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

private:
    // 玩家ID
    int id;

    // 互斥锁
    QMutex mutex;

    // 线程等待标识，这里没用到，留着以后扩展用
    bool waiting_;

    // 等待条件，这里没用到，留着以后扩展用
    QWaitCondition pauseCondition;

    // 主线程棋对象的引用
    const NineChess *chess_;

    // Alpha-Beta剪枝算法类
    NineChessAi_ab ai_ab;

    // AI的层数
    int aiDepth;

    // AI的限时
    int aiTime;

    // 定时器
    QTimer timer;
};

#endif // AITHREAD_H
