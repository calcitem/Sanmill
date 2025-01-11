// game_timer.cpp

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

void Game::stopActiveTimer()
{
    if (timeID != 0) {
        killTimer(timeID);
        timeID = 0;
    }
}

void Game::initTimeLimit()
{
    timeLimit = 0; // Replace this with actual logic if needed
    remainingTime[WHITE] = remainingTime[BLACK] = (timeLimit <= 0) ? 0 :
                                                                     timeLimit;
}

void Game::emitTimeChangedSignals()
{
    const QTime qtimeWhite =
        QTime(0, 0, 0, 0).addSecs(static_cast<int>(remainingTime[WHITE]));
    const QTime qtimeBlack =
        QTime(0, 0, 0, 0).addSecs(static_cast<int>(remainingTime[BLACK]));

    emit time1Changed(qtimeWhite.toString("hh:mm:ss"));
    emit time2Changed(qtimeBlack.toString("hh:mm:ss"));
}

void Game::stopTimer()
{
    stopActiveTimer();
}

void Game::reinitTimerAndEmitSignals()
{
    initTimeLimit();
    emitTimeChangedSignals();
}

void Game::updateElapsedTime()
{
    constexpr int timePoint = -1;
    time_t &ourSeconds = elapsedSeconds[position.side_to_move()];
    const time_t theirSeconds = elapsedSeconds[~position.side_to_move()];
    currentTime = time(nullptr);

    ourSeconds = (timePoint >= ourSeconds) ?
                     timePoint :
                     currentTime - startTime - theirSeconds;
}

void Game::handleTimerEvent(QTimerEvent *event)
{
    Q_UNUSED(event)
    updateElapsedTime();

    remainingTime[WHITE] = getElapsedSeconds(WHITE);
    remainingTime[BLACK] = getElapsedSeconds(BLACK);

    // If the rule requires a timer, time1 and time2 indicate a countdown
    if (timeLimit > 0) {
        // Player's remaining time
        remainingTime[WHITE] = timeLimit - remainingTime[WHITE];
        remainingTime[BLACK] = timeLimit - remainingTime[BLACK];
    }

    emitTimeChangedSignals();

    const Color winner = position.get_winner();
    if (winner != NOBODY && timeID != 0) {
        stopActiveTimer();
        refreshStatusBar();

#ifndef DO_NOT_PLAY_WIN_SOUND
        playGameSound(GameSound::win);
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

time_t Game::getElapsedSeconds(int color) const
{
    return elapsedSeconds[color];
}

void Game::clearElapsedTimes()
{
    elapsedSeconds[WHITE] = elapsedSeconds[BLACK] = 0;
}

void Game::stopGameTimer()
{
    stopActiveTimer();
}
