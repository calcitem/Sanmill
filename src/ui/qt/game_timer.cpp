// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
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

void Game::terminateOrResetTimer()
{
    if (timeID != 0) {
        killTimer(timeID);
        timeID = 0;
    }
}

void Game::initializeTime()
{
    timeLimit = 0; // Replace this with actual logic if needed
    remainingTime[WHITE] = remainingTime[BLACK] = (timeLimit <= 0) ? 0 :
                                                                     timeLimit;
}

void Game::emitTimeSignals()
{
    const QTime qtimeWhite =
        QTime(0, 0, 0, 0).addSecs(static_cast<int>(remainingTime[WHITE]));
    const QTime qtimeBlack =
        QTime(0, 0, 0, 0).addSecs(static_cast<int>(remainingTime[BLACK]));

    emit time1Changed(qtimeWhite.toString("hh:mm:ss"));
    emit time2Changed(qtimeBlack.toString("hh:mm:ss"));
}

void Game::resetTimer()
{
    terminateOrResetTimer();
}

void Game::resetAndUpdateTime()
{
    initializeTime();
    emitTimeSignals();
}

void Game::updateTime()
{
    constexpr int timePoint = -1;
    time_t &ourSeconds = elapsedSeconds[sideToMove];
    const time_t theirSeconds = elapsedSeconds[~sideToMove];
    currentTime = time(nullptr);

    ourSeconds = (timePoint >= ourSeconds) ?
                     timePoint :
                     currentTime - startTime - theirSeconds;
}

void Game::timerEvent(QTimerEvent *event)
{
    Q_UNUSED(event)
    updateTime();

    remainingTime[WHITE] = getElapsedTime(WHITE);
    remainingTime[BLACK] = getElapsedTime(BLACK);

    // If the rule requires a timer, time1 and time2 indicate a countdown
    if (timeLimit > 0) {
        // Player's remaining time
        remainingTime[WHITE] = timeLimit - remainingTime[WHITE];
        remainingTime[BLACK] = timeLimit - remainingTime[BLACK];
    }

    emitTimeSignals();

    const Color winner = position.get_winner();
    if (winner != NOBODY && timeID != 0) {
        terminateOrResetTimer();
        updateStatusBar();

#ifndef DO_NOT_PLAY_WIN_SOUND
        playSound(GameSound::win);
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

time_t Game::getElapsedTime(int color) const
{
    return elapsedSeconds[color];
}

void Game::resetElapsedSeconds()
{
    elapsedSeconds[WHITE] = elapsedSeconds[BLACK] = 0;
}

void Game::terminateTimer()
{
    terminateOrResetTimer();
}
