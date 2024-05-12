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

#include <functional>
#include <map>
#include <vector>

#include <QParallelAnimationGroup>
#include <QModelIndex>
#include <QPointF>
#include <QSettings>
#include <QStringListModel>
#include <QTextStream>
#include <QTime>

#include "client.h"
#include "database.h"
#include "gamescene.h"
#include "mills.h"
#include "pieceitem.h"
#include "position.h"
#include "server.h"
#include "stopwatch.h"
#include "ai_shared_memory_dialog.h"
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

    using TransformFunc = std::function<void()>;

    //  Main window menu bar details
    static map<int, QStringList> getActions();

    int getRuleIndex() const noexcept { return ruleIndex; }

    int getTimeLimit() const noexcept { return timeLimit; }

    int getStepsLimit() const noexcept { return stepsLimit; }

    bool isAnimation() const noexcept { return hasAnimation; }

    void setDurationTime(int i) noexcept { durationTime = i; }

    int getDurationTime() const { return durationTime; }

    QStringListModel *getMoveListModel() { return &moveListModel; }

    void setAiDepthTime(int time1, int time2);
    void getAiDepthTime(int &time1, int &time2) const;

    void humanResign();

    Position *getPosition() noexcept { return &position; }

    static char colorToChar(Color color);
    static std::string charToString(char ch);
    void appendGameOverReasonToMoveList();
    void setTips();

    const std::vector<std::string> *getMoveList() const
    {
        return &gameMoveList;
    }

    time_t getElapsedTime(int color) const;
    void updateTime();

#ifdef NET_FIGHT_SUPPORT
    Server *server;
    Client *client;

    Server *getServer() { return server; }

    Client *getClient() { return client; }
#endif

private:
    void initializeComponents();
    void terminateComponents();
    void resetComponents();

    void initializeSceneBackground();
    void initializeAiThreads();
    void initializeDatabaseDialog();
    void initializeSettings();
    void initializeGameTest();
    void initializeMetaTypes();
    void initializeAiCommandConnections();
    void initializeNetworkComponents();
    void initializeEndgameLearning();

    void terminateTimer();
    void terminateThreads();
    void finalizeEndgameLearning();
    void clearMoveList();
    void destroySettings();

    static void createRuleEntries(std::map<int, QStringList> &actions);
    static std::pair<int, QStringList> createRuleEntry(int index);

    void waitForAiSearchCompletion();
    void resetTimer();
    void resetGameState();
    void resetUIElements();
    void resetAndUpdateTime();
    void updateMoveList();
    void updateStatusBar(bool reset = false);
    void updateLcdDisplay();
    void updateMiscellaneous();

    void resetMoveListReserveFirst();
    void appendRecordToMoveList(const char *format, ...);
    void resetPerfectAi();
    void resetPositionState();

    bool isValidRuleIndex(int ruleNo);
    void updateLimits(int stepLimited, int timeLimited);
    void resetElapsedSeconds();
    void saveRuleSetting(int ruleNo);

    void reinitMoveListModel();
    void updateMoveListModelFromMoveList(); // TODO
    void handleGameOutcome();
    void handleWinOrLoss();
    void performAutoRestartActions();
    void setEnginesForAiPlayers();

    QString createSavePath() const;
    void writePlayerType(QTextStream &textStream, const QString &color,
                         bool isAi) const;
    void writeGameStats(QTextStream &textStream) const;

    static void performSoundPlay(const std::string &filename);

    bool validateClick(QPointF p, Rank &r, File &f);
    bool undoRecentMovesOnReview();
    void initGameIfReady();
    bool performAction(Rank r, File f, QPointF p);
    void updateState(bool result);

    void animatePieceMovement(PieceItem *&deletedPiece);
    void handleMarkedLocations();
    void handleDeletedPiece(PieceItem *piece, int key,
                            QParallelAnimationGroup *animationGroup,
                            PieceItem *&deletedPiece);
    void updateLCDDisplays();
    void selectCurrentAndDeletedPieces(PieceItem *deletedPiece);

signals:

    // Signal of total played games number change
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

    // A signal that tells the main window to update the advantage bar
    void advantageChanged(qreal value);

public slots:

    // Set rules

    void setRule(int ruleNo, int stepLimited = 100, int timeLimited = 0);

    // The game begins
    void gameStart();

    // Game reset
    void gameReset();

    // Set edit state
    void setEditing(bool arg = true) noexcept;

    // Set white and black inversion state
    // void invertPieceColor(bool arg = true);

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
    void playSound(GameSound soundType);

    // Skill Level
    void setSkillLevel(int val) const;

    // Move Time
    void setMoveTime(int val) const;

    // Algorithm
    void setAlphaBetaAlgorithm(bool enabled) const;
    void setPvsAlgorithm(bool enabled) const;
    void setMtdfAlgorithm(bool enabled) const;
    void setMctsAlgorithm(bool enabled) const;
    void setRandomAlgorithm(bool enabled) const;
    void setAlgorithm(int val) const;

    // Perfect Database
    void setUsePerfectDatabase(bool arg) noexcept;
    void setPerfectDatabasePath(string val) const;

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

    // Use Perfect Database
    void setUsePerfectDatabase(bool enabled) const;

    // Does alpha beta search deepen iteratively
    void setIDS(bool enabled) const;

    //  DepthExtension
    void setDepthExtension(bool enabled) const;

    //  OpeningBook
    void setOpeningBook(bool enabled) const;

    //  DeveloperMode
    void setDeveloperMode(bool enabled) const;

    // Function to toggle piece color
    void togglePieceColor();

    // Function to update piece color based on 'isInverted'
    void updatePieceColor();

    // Function to swap the color of a single piece
    void swapColor(PieceItem *pieceItem);

    // Function to execute a board transformation
    void executeTransform(const TransformFunc &transform);

    // Function to update UI components
    void updateUIComponents();

    // Function to synchronize the current scene based on move list
    void syncScene(int row);

    // Transformation functions
    void flipVertically();
    void flipHorizontally();
    void rotateClockwise();
    void RotateCounterclockwise();

    // Implementation of the transformation functions
    void mirrorAndRotate();
    void applyMirror();
    void rotateRight();
    void rotateLeft();

    bool isAiToMove() const;

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
    bool handleClick(QPointF point);

    // Admit defeat
    bool resign();

    // Command line execution of score
    bool command(const string &command, bool update = true);
    GameSound identifySoundType(Action action);
    void printStats();
    void updateStatistics();

    // Historical situation and situation change
    bool updateBoardState(int row, bool forceUpdate = false);
    bool applyPartialMoveList(int row);

    // Update the game display. Only after each step can the situation be
    // refreshed
    bool updateScene();

#ifdef NET_FIGHT_SUPPORT
    // The network configuration window is displayed
    void showNetworkWindow();
#endif

    // Show engine vs. window
    void showTestWindow() const;

    // Show Perfect Database dialog
    void showDatabaseDialog() const;

    void saveScore();

    AiSharedMemoryDialog *getTest() const { return gameTest; }

    DatabaseDialog *getDatabaseDialog() const { return databaseDialog; }

protected:
    // bool eventFilter(QObject * watched, QEvent * event);

    // Timer
    void initializeTime();
    void terminateOrResetTimer();
    void timerEvent(QTimerEvent *event) override;
    void emitTimeSignals();

private:
    // Data model of object
    Position position;
    Color sideToMove;

    // Testing
    AiSharedMemoryDialog *gameTest;

    // Perfect Database Dialog
    DatabaseDialog *databaseDialog {nullptr};

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

    bool fixWindowSizeEnabled() const { return fixWindowSize; }

    static bool soundEnabled() { return hasSound; }

    bool animationEnabled() const { return hasAnimation; }

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

    // String list model
    QStringListModel moveListModel;

    // Hint
    string tips;

    std::vector<std::string> gameMoveList;
};

#endif // GAME_H_INCLUDED
