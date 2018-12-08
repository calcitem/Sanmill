#include <QDebug>
#include "aithread.h"

AiThread::AiThread(int id, QObject *parent) : QThread(parent),
    waiting_(false)
{
    this->id = id;
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
    // 设一个标识，1号线程只管玩家1，2号线程只管玩家2
    int i = 0;

    while (!isInterruptionRequested()) {
        mutex.lock();
        if (chess->whosTurn() == NineChess::PLAYER1)
            i = 1;
        else if (chess->whosTurn() == NineChess::PLAYER2)
            i = 2;
        else
            i = 0;

        if (i != id || waiting_) {
            pauseCondition.wait(&mutex);
            mutex.unlock();
            continue;
        }
        else {
            ai_ab.setChess(*chess);
            mutex.unlock();
        }

        ai_ab.alphaBetaPruning(6);
        const char * str = ai_ab.bestMove();
        qDebug() << str;
        if (strcmp(str, "error!"))
            emit command(str);
        qDebug() << "Thread" << id << " run " << ++iTemp << "times";

        // 执行完毕后继续判断
        if (!isInterruptionRequested()) {
            mutex.lock();
            pauseCondition.wait(&mutex);
            mutex.unlock();
        }
    }
    qDebug() << "Thread" << id << " quit.";
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

    if(!isInterruptionRequested())
        requestInterruption();
    mutex.lock();
    waiting_ = false;
    pauseCondition.wakeAll();
    mutex.unlock();
}
