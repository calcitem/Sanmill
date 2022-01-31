// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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

/*
 * This class deals with the scene object QGraphicsScene
 * It is the only control module in MVC model of this program
 * It doesn't do any operation on the controls in the main window, only signals
 * the main window You could have overloaded QGraphicsScene to implement it and
 * saved the trouble of writing event filters But it doesn't look good to use
 * one scene class to do so many control module operations
 */

#ifndef GAME_H_INCLUDED
#define GAME_H_INCLUDED

#include <map>
#include <vector>

#include <QModelIndex>
#include <QPointF>
#include <QSettings>
#include <QStringListModel>
#include <QTextStream>
#include <QTime>

#include "client.h"
#include "gamescene.h"
#include "mills.h"
#include "pieceitem.h"
#include "position.h"
#include "server.h"
#include "stopwatch.h"
#include "test.h"
#include "thread.h"

using std::cout;
using std::endl;
using std::fixed;
using std::map;

enum class GameSound {
    none,
    blockMill,
    remove,
    select,
    draw,
    drag,
    banned,
    gameStart,
    resign,
    loss,
    mill,
    millRepeatedly,
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
    explicit Game(GameScene &scene, QObject *parent = nullptr);
    ~Game() override;

    //  Main window menu bar details
    static map<int, QStringList> getActions();

    [[nodiscard]] int getRuleIndex() const noexcept { return ruleIndex; }

    [[nodiscard]] int getTimeLimit() const noexcept { return timeLimit; }

    [[nodiscard]] int getStepsLimit() const noexcept { return stepsLimit; }

    [[nodiscard]] bool isAnimation() const noexcept { return hasAnimation; }

    void setDurationTime(int i) noexcept { durationTime = i; }

    [[nodiscard]] int getDurationTime() const { return durationTime; }

    QStringListModel *getMoveListModel() { return &moveListModel; }

    void setAiDepthTime(int time1, int time2);
    void getAiDepthTime(int &time1, int &time2) const;

    void humanResign();

    Position *getPosition() noexcept { return &position; }

    static char color_to_char(Color color);
    static std::string char_to_string(char ch);
    void appendGameOverReasonToMoveHistory();
    void setTips();

    [[nodiscard]] const std::vector<std::string> *move_hostory() const
    {
        return &moveHistory;
    }

    time_t get_elapsed_time(int us) const;
    [[nodiscard]] time_t start_timeb() const;
    void set_start_time(int time);
    void updateTime();

#ifdef NET_FIGHT_SUPPORT
    Server *server;
    Client *client;

    Server *getServer() { return server; }

    Client *getClient() { return client; }
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

    void setRule(int ruleNo,
                 int stepLimited = std::numeric_limits<uint16_t>::max(),
                 int timeLimited = 0);

    // The game begins
    void gameStart();

    // Game reset
    void gameReset();

    // Set edit state
    void setEditing(bool arg = true) noexcept;

    // Set white and black inversion state
    void setInvert(bool arg = true);

    // If Id is 1, let the computer take the lead; if Id is 2, let the computer
    // take the second place
    void setEngine(Color color, bool enabled = true);
    void setEngineWhite(bool enabled);
    void setEngineBlack(bool enabled);

    // Fix Window Size
    void setFixWindowSize(bool arg) noexcept;

    // Is there a falling animation
    void setAnimation(bool arg = true) noexcept;

    // Is there a drop sound effect
    void setSound(bool arg = true) const noexcept;

    // Play the sound
    static void playSound(GameSound soundType, Color c);

    // Skill Level
    void setSkillLevel(int val) const;

    // Move Time
    void setMoveTime(int val) const;

    // Algorithm
    void setAlphaBetaAlgorithm(bool enabled) const;
    void setPvsAlgorithm(bool enabled) const;
    void setMtdfAlgorithm(bool enabled) const;
    void setAlgorithm(int val) const;

    // Draw on human experience
    void setDrawOnHumanExperience(bool enabled) const;

    // Consider mobility of pieces
    void setConsiderMobility(bool enabled) const;

    // AI is Lazy
    void setAiIsLazy(bool enabled) const;

    // Do you admit defeat when you lose
    void setResignIfMostLose(bool enabled) const;

    // Auto start or not
    void setAutoRestart(bool enabled = false) const;

    // Is the start automatically changed to the first before the second
    void setAutoChangeFirstMove(bool enabled = false) const;

    // Is AI random
    void setShuffling(bool enabled) const;

    // Does AI record the game library
    void setLearnEndgame(bool enabled) const;

    // Does Perfect AI (See https://www.mad-weasel.de/morris.html)
    void setPerfectAi(bool enabled) const;

    // Does alpha beta search deepen iteratively
    void setIDS(bool enabled) const;

    //  DepthExtension
    void setDepthExtension(bool enabled) const;

    //  OpeningBook
    void setOpeningBook(bool enabled) const;

    //  DeveloperMode
    void setDeveloperMode(bool enabled) const;

    // Flip up and down
    void flip();

    // Left and right mirror images
    void mirror();

    // The view must be rotated 90 degree clockwise
    void turnRight();

    // View rotated 90 degree counterclockwise
    void turnLeft();

    [[nodiscard]] bool isAIsTurn() const;

    void threadsSetAi(Position *p) const
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

    void startAiThreads() const
    {
        if (isAiPlayer[WHITE]) {
            aiThread[WHITE]->start_searching();
        }

        if (isAiPlayer[BLACK]) {
            aiThread[BLACK]->start_searching();
        }
    }

    void stopAndWaitAiThreads() const
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

    void pauseThreads() const
    {
        aiThread[WHITE]->pause();
        aiThread[BLACK]->pause();
    }

    void waitThreads() const
    {
        aiThread[WHITE]->wait_for_search_finished();
        aiThread[BLACK]->wait_for_search_finished();
    }

    void pauseAndWaitThreads() const
    {
        pauseThreads();
        waitThreads();
    }

    void resumeAiThreads(Color c) const
    {
        if (isAiPlayer[c]) {
            aiThread[c]->start_searching();
        }
    }

    void deleteAiThreads() const
    {
        delete aiThread[WHITE];
        delete aiThread[BLACK];
    }

    // According to the signal and state of qgraphics scene, select, drop or
    // delete the sub objects
    bool actionPiece(QPointF p);

    // Admit defeat
    bool resign();

    // Command line execution of score
    bool command(const string &cmd, bool update = true);

    // Historical situation and situation change
    bool phaseChange(int row, bool forceUpdate = false);

    // Update the game display. Only after each step can the situation be
    // refreshed
    bool updateScene();
    bool updateScene(Position &p);

#ifdef NET_FIGHT_SUPPORT
    // The network configuration window is displayed
    void showNetworkWindow();
#endif

    // Show engine vs. window
    void showTestWindow() const;

    void saveScore();

    [[nodiscard]] Test *getTest() const { return gameTest; }

protected:
    // bool eventFilter(QObject * watched, QEvent * event);

    // Timer
    void timerEvent(QTimerEvent *event) override;

private:
    // Data model of object
    Position position;
    Color sideToMove;

    // Testing
    Test *gameTest;

    // 2 AI threads
    Thread *aiThread[COLOR_NB];

    // The scene class of game
    GameScene &scene;

    // All the pieces
    vector<PieceItem *> pieceList;

    // Current pieces
    PieceItem *currentPiece {nullptr};

    // Current browsing score line
    int currentRow {-1};

    // Is it in "Edit game" state
    bool isEditing {false};

    // Reverse white and black
    bool isInverted {false};

public:
    const QString SETTINGS_FILE = "settings.ini";
    QSettings *settings {nullptr};

    void loadSettings();

    [[nodiscard]] bool fixWindowSizeEnabled() const { return fixWindowSize; }

    static bool soundEnabled() { return hasSound; }

    [[nodiscard]] bool animationEnabled() const { return hasAnimation; }

    // True when the computer takes the lead
    bool isAiPlayer[COLOR_NB];

    string getTips() { return tips; }

private:
    // Fix Windows Size
    bool fixWindowSize;

    // Is there a falling animation
    bool hasAnimation {true};

    // Animation duration
    int durationTime {500};

    // Game start time
    TimePoint gameStartTime {0};

    // Game end time
    TimePoint gameEndTime {0};

    // Game duration
    TimePoint gameDurationTime {0};

    // Game start cycle
    stopwatch::rdtscp_clock::time_point gameStartCycle;

    // Game end cycle
    stopwatch::rdtscp_clock::time_point gameEndCycle;

    // Game duration
    stopwatch::rdtscp_clock::duration gameDurationCycle {0};

    // Time dependent
    time_t startTime;
    time_t currentTime;
    time_t elapsedSeconds[COLOR_NB];

    // Is there a drop sound effect
    inline static bool hasSound {true};

    // Do you admit defeat when you lose
    bool resignIfMostLose_ {false};

    // Do you want to exchange first before second
    bool isAutoChangeFirstMove {false};

    // Is ai the first
    bool isAiFirstMove {false};

    // Timer ID
    int timeID {0};

    // Rule number
    int ruleIndex {-1};

    // Rule time limit (seconds)
    int timeLimit;

    // Rule step limit
    int stepsLimit {100};

    // Player's remaining time (seconds)
    time_t remainingTime[COLOR_NB];

    // String used to display the status bar of the main window
    QString message;

    // String list model of score
    QStringListModel moveListModel;

    // Hint
    string tips;

    std::vector<std::string> moveHistory;
};

inline time_t Game::start_timeb() const
{
    return startTime;
}

inline void Game::set_start_time(int time)
{
    startTime = time;
}

#endif // GAME_H_INCLUDED
