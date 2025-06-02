// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game.h

#ifndef GAME_H_INCLUDED
#define GAME_H_INCLUDED

#include <atomic>
#include <functional>
#include <iostream>
#include <map>
#include <vector>
#include <memory> // For smart pointers

#include <QModelIndex>
#include <QParallelAnimationGroup>
#include <QPointF>
#include <QPropertyAnimation>
#include <QSettings>
#include <QStringListModel>
#include <QTextStream>
#include <QTime>
#include <QTimer>
#include <QObject> // Ensure QObject is included

#include "client.h"
#include "engine_controller.h"
#include "database.h"
#include "gamescene.h"
#include "mills.h"
#include "misc.h"
#include "pieceitem.h"
#include "position.h"
#include "server.h"
#include "search_engine.h"
#include "stopwatch.h"
#include "ai_shared_memory_dialog.h"
// #include "thread.h" // No longer needed

using std::cout;
using std::endl;
using std::fixed;
using std::map;
using std::vector;

extern std::atomic<int> g_activeAiTasks;

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

    // Main window menu bar details
    static map<int, QStringList> getRuleActions();

    int getRuleIndex() const noexcept { return ruleIndex; }

    int getTimeLimit() const noexcept { return timeLimit; }

    int getStepsLimit() const noexcept { return stepsLimit; }

    bool isAnimation() const noexcept { return hasAnimation; }

    void setDurationTime(int i) noexcept { durationTime = i; }

    int getDurationTime() const { return durationTime; }

    QStringListModel *getMoveListModel() { return &moveListModel; }

    void setAiTimeLimits(int time1, int time2);
    void getAiTimeLimits(int &time1, int &time2) const;

    // New player time limit methods
    void setPlayerTimeLimits(int whiteTime, int blackTime);
    void getPlayerTimeLimits(int &whiteTime, int &blackTime) const;

    // Move limit methods
    void setMoveLimit(int moves);
    int getMoveLimit() const;

    // Timer control methods
    void startPlayerTimer(Color player);
    void stopPlayerTimer();
    void handlePlayerTimeout(Color player);

    // Check if move is first move of the game
    bool isFirstMove() const;

    void resignHumanPlayer();

    Position *getPosition() noexcept { return &position; }

    static char colorToChar(Color color);
    static std::string charToString(char ch);
    void recordGameOverReason();
    void updateTips();

    const std::vector<std::string> *getMoveList() const
    {
        return &gameMoveList;
    }

    time_t getElapsedSeconds(int color) const;
    void updateElapsedTime();

#ifdef NET_FIGHT_SUPPORT
    Server *server;
    Client *client;

    Server *getServer() { return server; }

    Client *getClient() { return client; }
#endif

    // Get settings file path
    QString getSettingsFilePath() const;

    void applyRule(int ruleIndex, int stepLimited = -1,
                   int timeLimited = -1) const;

private:
    void initComponents();
    void cleanupComponents();
    void reinitComponents();

    void initSceneBackground();
    void initAiThreads();
    void initDatabaseDialog();
    void initSettings();
    void initGameTest();
    void initMetaTypes();
    void initAiCommandConnections();
    void initNetworkComponents();
    void initEndgameLearning();

    void stopGameTimer();
    void stopThreads();
    void finishEndgameLearning();
    void clearMoveList();
    void cleanupSettings();

    static void buildRuleEntries(std::map<int, QStringList> &actions);
    static std::pair<int, QStringList> buildRuleEntry(int index);

    void waitUntilAiSearchDone();
    void stopTimer();
    void clearGameState();
    void resetUiComponents();
    void reinitTimerAndEmitSignals();
    void refreshMoveList();
    void refreshStatusBar(bool reset = false);
    void refreshLcdDisplay();
    void updateMisc();

    void resetMoveListKeepFirst();
    void appendMoveRecord(const char *format, ...);
    void resetPerfectAiEngine();
    void resetPosition();

    bool isRuleIndexValid(int ruleNo);
    void setMoveAndTimeLimits(int stepLimited, int timeLimited);
    void clearElapsedTimes();
    void storeRuleSetting(int ruleNo);

    void resetMoveListModel();
    void syncMoveListToModel(); // TODO
    void processGameOutcome();
    void processWinLoss();
    void executeAutoRestart();
    void assignAiEngines();

    QString buildSaveFilePath() const;
    void outputPlayerType(QTextStream &textStream, const QString &color,
                          bool isAi) const;
    void outputGameStatistics(QTextStream &textStream) const;

    static void doPlaySound(const std::string &filename);

    bool isValidBoardClick(QPointF p, File &f, Rank &r);
    bool undoMovesIfReviewing();
    void initGameIfReady();
    bool applyBoardAction(File f, Rank r, QPointF p);
    void updateGameState(bool result);
    bool hasActiveAiTasks();

    void animatePieces(PieceItem *&deletedPiece);
    void processMarkedSquares();
    void handleRemovedPiece(PieceItem *piece, int key,
                            QParallelAnimationGroup *animationGroup,
                            PieceItem *&deletedPiece);
    void selectActiveAndRemovedPieces(PieceItem *deletedPiece);

    void submitAiSearch();

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

    // New signal to notify AI search completion
    void aiSearchCompleted();

public slots:

    // Set rules

    void applyRule(int ruleNo, int stepLimited = 100, int timeLimited = 0);

    // The game begins
    void gameStart();

    // Game reset
    void gameReset();

    // Set edit state
    void setEditingModeEnabled(bool arg = true) noexcept;

    // Set white and black inversion state
    // void invertPieceColor(bool arg = true);

    // If Id is 1, let the computer take the lead; if Id is 2, let the computer
    // take the second place
    void setEngineControl(Color color, bool enabled = true);
    void setWhiteIsAiPlayer(bool enabled);
    void setBlackIsAiPlayer(bool enabled);

    // Fix Window Size
    void setFixWindowSize(bool arg) noexcept;

    // Is there a falling animation
    void setAnimation(bool arg = true) noexcept;

    // Set the piece animation
    QPropertyAnimation *buildPieceAnimation(PieceItem *piece,
                                            const QPointF &startPos,
                                            const QPointF &endPos,
                                            int duration);

    // Is there a drop sound effect
    void setSound(bool arg = true) const noexcept;

    // Play the sound
    void playGameSound(GameSound soundType);

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

    // Focus on blocking paths
    void setFocusOnBlockingPaths(bool enabled) const;

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

    // DepthExtension
    void setDepthExtension(bool enabled) const;

    // OpeningBook
    void setOpeningBook(bool enabled) const;

    // DeveloperMode
    void setDeveloperMode(bool enabled) const;

    // Function to toggle piece color
    void togglePieceColors();

    // Function to update piece color based on 'isInverted'
    void updatePieceColors();

    // Function to swap the color of a single piece
    void swapPieceColor(PieceItem *pieceItem);

    // Function to execute a board transformation
    void applyTransform(const TransformFunc &transform);

    // Function to update UI components
    void refreshUIComponents();

    // Function to synchronize the current scene based on move list
    void syncSceneWithRow(int row);

    // Transformation functions
    void flipBoardVertically();
    void flipBoardHorizontally();
    void rotateBoardClockwise();
    void rotateBoardCounterclockwise();

    // Implementation of the transformation functions
    void flipAndRotateBoard();
    void applyHorizontalFlip();
    void rotateBoardRight();
    void rotateBoardLeft();

    bool isAiSideToMove() const;

    void resetAiPlayers()
    {
        isAiPlayer[WHITE] = false;
        isAiPlayer[BLACK] = false;
    }

    // Removed AI thread management methods
    // void createAiThreads();
    // void startAiThreads() const;
    // void stopAndWaitAiThreads() const;
    // void pauseThreads() const;
    // void waitThreads() const;
    // void pauseAndWaitThreads() const;
    // void resumeAiThreads(Color c) const;
    // void deleteAiThreads() const;

    // Slot to handle AI search completion
    void handleAiSearchCompleted();

    // According to the signal and state of qgraphics scene, select, drop or
    // delete the sub objects
    bool handleBoardClick(QPointF point);

    // Admit defeat
    bool resignGame();

    // Command line execution of score
    bool command(const string &command, bool update = true);
    GameSound getSoundTypeForAction(Action action);
    void printGameStatistics();
    void updateGameStatistics();

    // Historical situation and situation change
    bool refreshBoardState(int row, bool forceUpdate = false);
    bool applyMoveListUntilRow(int row);

    // Update the game display. Only after each step can the situation be
    // refreshed
    bool refreshScene();

#ifdef NET_FIGHT_SUPPORT
    // The network configuration window is displayed
    void showNetworkWindow();
#endif

    // Show engine vs. window
    void displayTestWindow() const;

    // Show Perfect Database dialog
    void showDatabaseDialog() const;

    void saveGameScore();

    AiSharedMemoryDialog *getTest() const { return gameTest; }

    DatabaseDialog *getDatabaseDialog() const { return databaseDialog; }

protected:
    // bool eventFilter(QObject * watched, QEvent * event);

    // Timer
    void initTimeLimit();
    void stopActiveTimer();
    void handleTimerEvent(QTimerEvent *event);
    void emitTimeChangedSignals();

private:
    // Data model of object
    Position position;
    // Color sideToMove;

    SearchEngine searchEngine;
    EngineController engineController;

    // Testing
    AiSharedMemoryDialog *gameTest;

    // Perfect Database Dialog
    DatabaseDialog *databaseDialog {nullptr};

    // Removed AI thread pointers
    // Thread *aiThread[COLOR_NB];

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

    void loadGameSettings();

    bool fixWindowSizeEnabled() const { return fixWindowSize; }

    static bool soundEnabled() { return hasSound; }

    bool animationEnabled() const { return hasAnimation; }

    // True when the computer takes the lead
    bool isAiPlayer[COLOR_NB] {false};

    string getTips() { return tips; }

    unsigned int score[DRAW + 1] {0};
    unsigned int gamesPlayedCount {0};

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

    // New time limit variables
    int playerTimeLimit[COLOR_NB] {0, 0};     // White and Black time limits in
                                              // seconds (0 = no limit)
    int playerRemainingTime[COLOR_NB] {0, 0}; // Current remaining time for each
                                              // player
    QTimer *playerTimer {nullptr};            // Timer for player time limits
    Color currentTimerPlayer {WHITE}; // Which player's timer is currently
                                      // running
    bool isFirstMoveOfGame {true};    // Flag to track if it's the first move
    bool timerEnabled {false};        // Whether time limits are enabled

    // Move limit variables
    int moveLimit {100}; // Move limit for the game (default 100 moves)
};

#endif // GAME_H_INCLUDED
