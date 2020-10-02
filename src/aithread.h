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

#include <condition_variable>
#include <mutex>
#include <QThread>
#include <QTimer>
#include "position.h"
#include "search.h"
#include "server.h"
#include "client.h"
#include "test.h"
#include "position.h"

class AiThread : public QThread
{
    Q_OBJECT

private:
    std::mutex mutex;
    std::condition_variable cv;
    bool exit = false, searching = true; // Set before starting std::thread

    string strCommand;

public:
    explicit AiThread(QObject *parent = nullptr);
    explicit AiThread(int color, QObject *parent = nullptr);
    ~AiThread() override;
    int search();

signals:
    void command(const string &cmdline, bool update = true);

    void searchStarted();
    void searchFinished();

public slots:
    void act(); // Force move, not quit thread
    void resume();
    void stop();
    void emitCommand();

public:
    void setAi(Position *p);
    void setAi(Position *p, int time);
    void run() override;

    Server *getServer()
    {
        return server;
    }

    Client *getClient()
    {
        return client;
    }

    int getTimeLimit()
    {
        return timeLimit;
    }

    void analyze(Color c);

    // bool requiredQuit {false}; // TODO

    void setPosition(Position *p);
    string nextMove();
    Depth adjustDepth();

    void quit()
    {
        loggerDebug("Timeout\n");
        //requiredQuit = true;  // TODO
#ifdef HOSTORY_HEURISTIC
        movePicker->clearHistoryScore();
#endif
    }

#ifdef TIME_STAT
    TimePoint sortTime{ 0 };
#endif
#ifdef CYCLE_STAT
    stopwatch::rdtscp_clock::time_point sortCycle;
    stopwatch::timer::duration sortCycle { 0 };
    stopwatch::timer::period sortCycle;
#endif

#ifdef ENDGAME_LEARNING
    bool findEndgameHash(key_t key, Endgame &endgame);
    static int recordEndgameHash(key_t key, const Endgame &endgame);
    void clearEndgameHashMap();
    static void recordEndgameHashMapToFile();
    static void loadEndgameFileToHashMap();
#endif // ENDGAME_LEARNING

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef TRANSPOSITION_TABLE_DEBUG
    size_t tteCount{ 0 };
    size_t ttHitCount{ 0 };
    size_t ttMissCount{ 0 };
    size_t ttInsertNewCount{ 0 };
    size_t ttAddrHitCount{ 0 };
    size_t ttReplaceCozDepthCount{ 0 };
    size_t ttReplaceCozHashCount{ 0 };
#endif
#endif

public:
    Position *rootPos { nullptr };

    Depth originDepth { 0 };
    Depth adjustedDepth { 0 };

    Move bestMove { MOVE_NONE };
    Value bestvalue { VALUE_ZERO };
    Value lastvalue { VALUE_ZERO };

    int us;

private:
    int timeLimit;
    QTimer timer;

    Server *server;
    Client *client;
};

#endif // AITHREAD_H
