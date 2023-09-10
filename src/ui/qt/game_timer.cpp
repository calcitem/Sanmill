// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#include <iomanip>
#include <map>
#include <string>

#include <QAbstractButton>
#include <QApplication>
#include <QDir>
#include <QFileInfo>
#include <QGraphicsSceneMouseEvent>
#include <QGraphicsView>
#include <QKeyEvent>
#include <QMessageBox>
#include <QParallelAnimationGroup>
#include <QPropertyAnimation>
#include <QSoundEffect>
#include <QThread>
#include <QTimer>

#include "boarditem.h"
#include "client.h"
#include "game.h"
#include "graphicsconst.h"
#include "option.h"
#include "server.h"

#if defined(GABOR_MALOM_PERFECT_AI)
#include "perfect/perfect_adaptor.h"
#endif

using std::to_string;

void Game::resetTimer()
{
    if (timeID != 0) {
        killTimer(timeID);
    }

    timeID = 0;
}

void Game::resetAndUpdateTime()
{
    timeLimit = 0;
    // gameOptions.getMoveTime();

    if (timeLimit <= 0) {
        remainingTime[WHITE] = remainingTime[BLACK] = 0;
    } else {
        remainingTime[WHITE] = remainingTime[BLACK] = timeLimit;
    }

    // Signal the main window to update the LCD display
    const QTime qtime = QTime(0, 0, 0, 0)
                            .addSecs(static_cast<int>(remainingTime[WHITE]));
    emit time1Changed(qtime.toString("hh:mm:ss"));
    emit time2Changed(qtime.toString("hh:mm:ss"));
}

void Game::updateTime()
{
    constexpr int timePoint = -1;
    time_t *ourSeconds = &elapsedSeconds[sideToMove];
    const time_t theirSeconds = elapsedSeconds[~sideToMove];

    currentTime = time(nullptr);

    if (timePoint >= *ourSeconds) {
        *ourSeconds = timePoint;
        startTime = currentTime -
                    (elapsedSeconds[WHITE] + elapsedSeconds[BLACK]);
    } else {
        *ourSeconds = currentTime - startTime - theirSeconds;
    }
}

void Game::timerEvent(QTimerEvent *event)
{
    Q_UNUSED(event)
    static QTime qt1, qt2;

    // Player's time spent
    updateTime();
    remainingTime[WHITE] = get_elapsed_time(WHITE);
    remainingTime[BLACK] = get_elapsed_time(BLACK);

    // If the rule requires a timer, time1 and time2 indicate a countdown
    if (timeLimit > 0) {
        // Player's remaining time
        remainingTime[WHITE] = timeLimit - remainingTime[WHITE];
        remainingTime[BLACK] = timeLimit - remainingTime[BLACK];
    }

    qt1 = QTime(0, 0, 0, 0).addSecs(static_cast<int>(remainingTime[WHITE]));
    qt2 = QTime(0, 0, 0, 0).addSecs(static_cast<int>(remainingTime[BLACK]));

    emit time1Changed(qt1.toString("hh:mm:ss"));
    emit time2Changed(qt2.toString("hh:mm:ss"));

    // If it's divided
    const Color winner = position.get_winner();
    if (winner != NOBODY) {
        // Stop the clock
        killTimer(timeID);

        // Timer ID is 0
        timeID = 0;

        // Signal update status bar
        updateScene();
        message = QString::fromStdString(getTips());
        emit statusBarChanged(message);

#ifndef DO_NOT_PLAY_WIN_SOUND
        playSound(GameSound::win, winner);
#endif
    }

    // For debugging
#if 0
    int ti = time.elapsed();
    static QTime t;
    if (ti < 0) {
        // Prevent the time error caused by 24:00,
        // plus the total number of seconds in a day
        ti += 86400;
    }
    if (timeWho == 1) {
        time1 = ti - time2;
        // A temporary variable used to display the time.
        // The extra 50 ms is used to eliminate the beat caused
        // by the timer error
        t = QTime(0, 0, 0, 50).addMSecs(time1);
        emit time1Changed(t.toString("hh:mm:ss"));
    } else if (timeWho == 2) {
        time2 = ti - time1;
        // A temporary variable used to display the time.
        // The extra 50 ms is used to eliminate the beat
        // caused by the timer error
        t = QTime(0, 0, 0, 50).addMSecs(time2);
        emit time2Changed(t.toString("hh:mm:ss"));
    }
#endif
}

time_t Game::get_elapsed_time(int us) const
{
    return elapsedSeconds[us];
}

void Game::resetElapsedSeconds()
{
    elapsedSeconds[WHITE] = elapsedSeconds[BLACK] = 0;
}

void Game::terminateTimer()
{
    if (timeID != 0) {
        killTimer(timeID);
    }
}
