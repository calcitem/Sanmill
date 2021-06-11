/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http:// www.gnu.org/licenses/>.
*/

/* 
 * This class deals with the scene object QGraphicsScene
 * It is the only control module in MVC model of this program
 * It doesn't do any operation on the controls in the main window, only signals the main window
 * You could have overloaded QGraphicsScene to implement it and saved the trouble of writing event filters
 * But it doesn't look good to use one scene class to do so many control module operations
 */

#ifndef GAMECONTROLLER_H
#define GAMECONTROLLER_H

#include <map>
#include <vector>

#include <QTime>
#include <QPointF>
#include <QTextStream>
#include <QStringListModel>
#include <QModelIndex>
#include <QSettings> 

#include "position.h"
#include "gamescene.h"
#include "pieceitem.h"
#include "thread.h"
#include "server.h"
#include "client.h"
#include "stopwatch.h"
#include "mills.h"
#include "test.h"

using namespace std;

enum class GameSound
{
    none,
    blockMill,
    remove,
    select,
    draw,
    drog,
    banned,
    gameStart,
    resign,
    loss,
    mill,
    millRepeatly,
    move,
    newGame,
    nextMill,
    obvious,
    repeatThreeDraw,
    side,
    star,
    suffocated,
    vantage,
    very,
    warning,
    win,
    winAndLossesAreObvious
};

class Game : public QObject
{
    Q_OBJECT

public:
    explicit Game(
        GameScene &scene,
        QObject *parent = nullptr
    );
    ~Game() override;

    //  Main window menu bar details
    const map<int, QStringList> getActions();

    int getRuleIndex() noexcept
    {
        return ruleIndex;
    }

    int getTimeLimit() noexcept
    {
        return timeLimit;
    }

    int getStepsLimit() noexcept
    {
        return stepsLimit;
    }

    bool isAnimation() noexcept
    {
        return hasAnimation;
    }

    void setDurationTime(int i) noexcept
    {
        durationTime = i;
    }

    int getDurationTime()
    {
        return durationTime;
    }

    QStringListModel *getManualListModel()
    {
        return &manualListModel;
    }

    void setAiDepthTime(int time1, int time2);
    void getAiDepthTime(int &time1, int &time2);

    void humanResign();

    Position *getPosition() noexcept
    {
        return &position;
    }

    char color_to_char(Color color);
    std::string char_to_string(char ch);
    void appendGameOverReasonToMoveHistory();
    void setTips();

    inline const std::vector<std::string> *move_hostory() const
    {
        return &moveHistory;
    }

    time_t get_elapsed_time(int us);
    time_t start_timeb() const;
    void set_start_time(int stimeb);
    void updateTime();

#ifdef NET_FIGHT_SUPPORT
    Server *server;
    Client *client;

    Server *getServer()
    {
        return server;
    }

    Client *getClient()
    {
        return client;
    }
#endif

signals:

    // Signal of total disk number change
    void nGamesPlayedChanged(const QString &score);

    // Player 1 (first hand) signal to change the number of winning sets
    void score1Changed(const QString &score);

    // Signal for player 2 (backhand) to change the number of winning sets
    void score2Changed(const QString &score);

    // The signal of the change of draw number
    void scoreDrawChanged(const QString &score);

    // Signal of player 1 (first hand) winning rate change
    void winningRate1Changed(const QString &score);

    // Signal of player 2 (backhand) winning rate change
    void winningRate2Changed(const QString &score);

    // Signal of change of draw rate
    void winningRateDrawChanged(const QString &score);

    // Player 1 (first hand) time changed signal
    void time1Changed(const QString &time);

    // Player 2 (backhand) time changed signal
    void time2Changed(const QString &time);

    // A signal that tells the main window to update the status bar
    void statusBarChanged(const QString &message);

public slots:

    // Set rules
    void setRule(int ruleNo, int stepLimited = std::numeric_limits<uint16_t>::max(), int timeLimited = 0);

    // The game begins
    void gameStart();

    // Game reset
    void gameReset();

    // Set edit chess state
    void setEditing(bool arg = true) noexcept;

    // Set white and black inversion state
    void setInvert(bool arg = true);

    // If Id is 1, let the computer take the lead; if Id is 2, let the computer take the second place
    void setEngine(Color color, bool enabled = true);
    void setEngineWhite(bool enabled);
    void setEngineBlack(bool enabled);
    
    // Fix Window Size 
    void setFixWindowSize(bool arg) noexcept;

    // Is there a falling animation
    void setAnimation(bool arg = true) noexcept;

    // Is there a drop sound effect
    void setSound(bool arg = true) noexcept;

    // Play the sound
    static void playSound(GameSound soundType, Color c);

    // Skill Level
    void setSkillLevel(int val);

    // Move Time
    void setMoveTime(int val);

    // Draw on human experience
    void setDrawOnHumanExperience(bool enabled);

    // AI is Lazy
    void setAiIsLazy(bool enabled);

    // Do you admit defeat when you lose
    void setResignIfMostLose(bool enabled);

    // Auto start or not
    void setAutoRestart(bool enabled = false);

    // Is the start automatically changed to the first before the second
    void setAutoChangeFirstMove(bool enabled = false);

    // Is AI random
    void setShuffling(bool enabled);

    // Does AI record the game library
    void setLearnEndgame(bool enabled);

    // Does Perfect AI (See https://www.mad-weasel.de/morris.html)
    void setPerfectAi(bool enabled);

    // Does alpha beta search deepen iteratively
    void setIDS(bool enabled);

    //  DepthExtension
    void setDepthExtension(bool enabled);

    //  OpeningBook
    void setOpeningBook(bool enabled);

    //  DeveloperMode
    void setDeveloperMode(bool enabled);

    // Flip up and down
    void flip();

    // Left and right mirror images
    void mirror();

    // The view must be rotated 90 ° clockwise
    void turnRight();

    // View rotated 90 degree counterclockwise
    void turnLeft();

    bool isAIsTurn();

    void threadsSetAi(Position *p)
    {
        aiThread[WHITE]->setAi(p);
        aiThread[BLACK]->setAi(p);
    }

    void resetAiPlayers()
    {
        isAiPlayer[WHITE] = false;
        isAiPlayer[BLACK] = false;
    }

    void createAiThreads()
    {
        aiThread[WHITE] = new Thread(0);
        aiThread[WHITE]->us = WHITE;

        aiThread[BLACK] = new Thread(0);
        aiThread[BLACK]->us = BLACK;
    }

    void startAiThreads()
    {
        if (isAiPlayer[WHITE]) {
            aiThread[WHITE]->start_searching();
        }

        if (isAiPlayer[BLACK]) {
            aiThread[BLACK]->start_searching();
        }
    }

    void stopAndWaitAiThreads()
    {
        if (isAiPlayer[WHITE]) {
            aiThread[WHITE]->pause();
            aiThread[WHITE]->wait_for_search_finished();
        }
        if (isAiPlayer[BLACK]) {
            aiThread[BLACK]->pause();
            aiThread[BLACK]->wait_for_search_finished();
        }
    }

    void pauseThreads()
    {
        aiThread[WHITE]->pause();
        aiThread[BLACK]->pause();
    }

    void waitThreads()
    {
        aiThread[WHITE]->wait_for_search_finished();
        aiThread[BLACK]->wait_for_search_finished();
    }

    void pauseAndWaitThreads()
    {
        pauseThreads();
        waitThreads();
    }

    void resumeAiThreads(Color c)
    {
        if (isAiPlayer[c]) {
            aiThread[c]->start_searching();
        }
    }

    void deleteAiThreads()
    {
        delete aiThread[WHITE];
        delete aiThread[BLACK];
    }

    // According to the signal and state of qgraphics scene, select, drop or delete the sub objects
    bool actionPiece(QPointF p);

    // Admit defeat
    bool resign();

    // Command line execution of chess score
    bool command(const string &cmd, bool update = true);

    // Historical situation and situation change
    bool phaseChange(int row, bool forceUpdate = false);

    // Update the chess game display. Only after each step can the situation be refreshed
    bool updateScence();
    bool updateScence(Position &p);

#ifdef NET_FIGHT_SUPPORT
    // The network configuration window is displayed
    void showNetworkWindow();
#endif

    // Show engine vs. window
    void showTestWindow();

    void saveScore();

    Test *getTest()
    {
        return gameTest;
    }

protected:
    // bool eventFilter(QObject * watched, QEvent * event);

    // Timer
    void timerEvent(QTimerEvent *event) override;

private:

    // Data model of chess object
    Position position;
    Color sideToMove;

    // Testing
    Test *gameTest;

private:

    // 2 AI threads
    Thread *aiThread[COLOR_NB];

    // The scene class of chess game
    GameScene &scene;

    // All the pieces
    vector<PieceItem *> pieceList;

    // Current chess pieces
    PieceItem *currentPiece;

    // Current browsing chess score line
    int currentRow;

    // Is it in "Edit chess game" state
    bool isEditing;

    // Reverse white and black
    bool isInverted;

public:
    const QString SETTINGS_FILE = "settings.ini";
    QSettings *settings {nullptr};

    void loadSettings();

    bool fixWindowSizeEnabled()
    {
        return fixWindowSize;
    }

    bool soundEnabled()
    {
        return hasSound;
    }

    bool animationEnabled()
    {
        return hasAnimation;
    }

    // True when the computer takes the lead
    bool isAiPlayer[COLOR_NB];

    string getTips()
    {
        return tips;
    }

private:

    // Fix Windows Size
    bool fixWindowSize;

    // Is there a falling animation
    bool hasAnimation;

    // Animation duration
    int durationTime;

    // Game start time
    TimePoint gameStartTime;

    // Game end time
    TimePoint gameEndTime;

    // Game duration
    TimePoint gameDurationTime;

    // Game start cycle
    stopwatch::rdtscp_clock::time_point gameStartCycle;

    // Game end cycle
    stopwatch::rdtscp_clock::time_point gameEndCycle;

    // Game duration
    stopwatch::rdtscp_clock::duration gameDurationCycle;

    // Time dependent
    time_t startTime;
    time_t currentTime;
    time_t elapsedSeconds[COLOR_NB];

    // Is there a drop sound effect
    inline static bool hasSound {true};

    // Do you admit defeat when you lose
    bool resignIfMostLose_ {false};

    // Do you want to exchange first before second
    bool isAutoChangeFirstMove { false };

    // Is ai the first
    bool isAiFirstMove { false };

    // Timer ID
    int timeID;

    // Rule number
    int ruleIndex;

    // Rule time limit (seconds)
    int timeLimit;

    // Rule step limit
    int stepsLimit;

    // Player's remaining time (seconds)
    time_t remainingTime[COLOR_NB];

    // String used to display the status bar of the main window
    QString message;

    // String list model of chess score
    QStringListModel manualListModel;

    // Hint
    string tips;

    std::vector <std::string> moveHistory;
};

inline time_t Game::start_timeb() const
{
    return startTime;
}

inline void Game::set_start_time(int stimeb)
{
    startTime = stimeb;
}

#endif // GAMECONTROLLER_H
