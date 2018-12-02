#ifndef AITHREAD_H
#define AITHREAD_H

#include <QThread>
#include <QMutex>
#include <QWaitCondition>
#include "ninechess.h"
#include "ninechessai_ab.h"

class AiThread : public QThread
{
    Q_OBJECT

public:
    explicit AiThread(QObject *parent = nullptr);
    ~AiThread();

signals:
    // 招法信号
    void command(const QString &cmdline, bool update = true);

protected:
    void run() override;

public slots:
    void setAi(const NineChess &);
    void pause();
    void resume();
    void stop();

private:
    // 互斥锁
    QMutex mutex;
    // 线程等待标识，这里没用到，留着以后扩展用
    bool waiting_;
    // 等待条件，这里没用到，留着以后扩展用
    QWaitCondition pauseCondition;

    // 主线程棋对象的引用
    const NineChess *chess;
    // Alpha-Beta剪枝算法类
    NineChessAi_ab ai_ab;
};

#endif // AITHREAD_H
