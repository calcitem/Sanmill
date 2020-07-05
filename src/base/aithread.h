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
    explicit AiThread(int color, QObject *parent = nullptr);
    ~AiThread() override;

signals:
    void command(const QString &cmdline, bool update = true);

    void searchStarted();

    void searchFinished();

protected:
    void run() override;

public:
    void setAi(Position *p);
    void setAi(Position *p, Depth depth, int time);

    Server *getServer()
    {
        return server;
    }

    Client *getClient()
    {
        return client;
    }

    Depth getDepth()
    {
        return depth;
    }

    int getTimeLimit()
    {
        return timeLimit;
    }

    void analyze();

public slots:
    void act(); // Force move, not quit thread
    void resume();
    void stop();
    void emitCommand();

public:
    int playerId;

private:
    const char* strCommand {};
    QMutex mutex;

    // For ext in future
    QWaitCondition pauseCondition;

public:
    Position *position;

public: // TODO: Change to private
    AIAlgorithm ai;

private:
    Depth depth;
    int timeLimit;
    QTimer timer;

    Server *server;
    Client *client;
};

#endif // AITHREAD_H
