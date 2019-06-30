#include <QDebug>
#include "aithread.h"

AiThread::AiThread(int id, QObject *parent) : QThread(parent), waiting_(false), aiDepth(2), aiTime(99)
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
#ifdef DEBUG
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

        ai_ab.alphaBetaPruning(aiDepth);
        const char *str = ai_ab.bestMove();
        qDebug() << "Computer:" << str << "\n";

        if (strcmp(str, "error!"))
            emit command(str);

#ifdef DEBUG
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
