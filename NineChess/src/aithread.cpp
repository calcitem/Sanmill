#include <QDebug>
#include "aithread.h"

AiThread::AiThread(QObject *parent) : QThread(parent),
    waiting_(false)
{
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
    this->chess = &chess;
    mutex.unlock();
}

void AiThread::run()
{
    // 测试用数据
    int iTemp = 0;

    forever{
        if (isInterruptionRequested())
            return;
        mutex.lock();
        if (waiting_)
            pauseCondition.wait(&mutex);
        mutex.unlock();

        ai_ab.setChess(*chess);
        ai_ab.alphaBetaPruning(5);
        const char * str = ai_ab.bestMove();
        qDebug() << str;
        if (strcmp(str, "error!"))
            emit command(str);

        // 测试用
        qDebug() << "thread running " << iTemp++ << "times";
    }
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
    if(isFinished())
        return;

    mutex.lock();
    requestInterruption();
    if (waiting_) {
        waiting_ = false;
        pauseCondition.wakeAll();
    }
    mutex.unlock();
}
