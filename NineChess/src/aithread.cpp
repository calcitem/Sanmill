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

void AiThread::run()
{
    // 测试用数据
    int iTemp = 0;

    while (true) {
        if(isInterruptionRequested())
            return;
        mutex.lock();
        if (waiting_)
            pauseCondition.wait(&mutex);
        mutex.unlock();

        // 测试用
        qDebug() << "thread running " << iTemp << "ms";
        msleep(250);
        iTemp+=250;
    }
}

void AiThread::setChess(NineChess &chess)
{
    mutex.lock();
    this->chess = chess;
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
    if(isFinished())
        return;

    mutex.lock();
    if (waiting_) {
        waiting_ = false;
        pauseCondition.wakeAll();
    }
    requestInterruption();
    mutex.unlock();
}
