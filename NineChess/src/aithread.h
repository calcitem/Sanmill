#ifndef AITHREAD_H
#define AITHREAD_H

#include <QThread>
#include <QMutex>
#include <QWaitCondition>
#include "ninechess.h"

class AiThread : public QThread
{
    Q_OBJECT
public:
    explicit AiThread(QObject *parent = nullptr);
    ~AiThread();

signals:
    // 招法信号
    void command(QString cmdline);

protected:
    void run() override;

public slots:
    void setChess(NineChess &);
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

    // 棋类
    NineChess chess;
};

#endif // AITHREAD_H
