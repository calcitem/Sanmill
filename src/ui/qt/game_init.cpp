// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_init.cpp

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
#include <QMetaObject> // For possible queued connections

#include "boarditem.h"
#include "client.h"
#include "game.h"
#include "graphicsconst.h"
#include "option.h"
#include "server.h"
#include "search_engine.h"
#include "thread_pool.h"

#if defined(GABOR_MALOM_PERFECT_AI)
#include "perfect/perfect_adaptor.h"
#endif

using std::to_string;

Game::Game(GameScene &scene, QObject *parent)
    : QObject(parent)
    , scene(scene)
    , timeLimit(
          0 /* or fetch from options if needed: gameOptions.getMoveTime() */)
    , gameMoveList(256)
    , engineController(searchEngine)
{
    initComponents();

#ifdef QT_GUI_LIB
    connect(&searchEngine, &SearchEngine::searchCompleted, this,
            &Game::handleAiSearchCompleted, Qt::QueuedConnection);

    connect(&searchEngine, &SearchEngine::command, this, &Game::command,
            Qt::QueuedConnection);
#endif
}

Game::~Game()
{
    cleanupComponents();
}

void Game::initComponents()
{
    initSceneBackground();

    initAiThreads();

    initDatabaseDialog();
    initSettings();
    initGameTest();
    initMetaTypes();
    initAiCommandConnections();
    initNetworkComponents();
    initEndgameLearning();
}

void Game::cleanupComponents()
{
    // Stop the timer
    stopGameTimer();

    // Stop AI tasks and do any cleanup
    stopThreads();

    // Finalize everything else
    finishEndgameLearning();
    clearMoveList();
    cleanupSettings();
}

void Game::reinitComponents()
{
    // Reset the timer
    stopTimer();

    // Reset the game state
    clearGameState();

    // If auto-restart is disabled, we can stop the thread pool
    if (!gameOptions.getAutoRestart()) {
        // This stops all queued tasks.
        // Threads.stop_all();
    }

    // Reset UI and time
    resetUiComponents();
    reinitTimerAndEmitSignals();

    // Other updates
    updateMisc();
}

void Game::gameStart()
{
    // Start or restart the game
    // You can clear the move list if needed:
    // gameMoveList.clear();
    position.start();
    startTime = time(nullptr);

    // Ensure timer is active
    if (timeID == 0) {
        timeID = startTimer(100); // 100 ms interval
    }

    gameStartTime = now();
    gameStartCycle = stopwatch::rdtscp_clock::now();

    // Initialize player timer system
    isFirstMoveOfGame = true;
    stopPlayerTimer();

    // Reset remaining time for both players
    // For time limit 0 (no limit), start with 60 minutes (3600 seconds)
    // countdown
    playerRemainingTime[WHITE] = (playerTimeLimit[WHITE] == 0) ?
                                     3600 :
                                     playerTimeLimit[WHITE];
    playerRemainingTime[BLACK] = (playerTimeLimit[BLACK] == 0) ?
                                     3600 :
                                     playerTimeLimit[BLACK];

    // Update timer displays
    emitTimeChangedSignals();

#ifdef OPENING_BOOK
    // Example of reloading an opening book if desired
    if (openingBookDeque.empty() && !openingBookDequeBak.empty()) {
        openingBookDeque = openingBookDequeBak;
        openingBookDequeBak.clear();
    }
#endif
}

void Game::gameReset()
{
    // If needed, wait for or stop AI tasks
    // Threads.stop_all();

    reinitComponents();
    clearElapsedTimes();
    resetMoveListModel();
    refreshStatusBar(true);

    // Reset player timer system
    isFirstMoveOfGame = true;
    stopPlayerTimer();
    // For time limit 0 (no limit), start with 60 minutes (3600 seconds)
    // countdown
    playerRemainingTime[WHITE] = (playerTimeLimit[WHITE] == 0) ?
                                     3600 :
                                     playerTimeLimit[WHITE];
    playerRemainingTime[BLACK] = (playerTimeLimit[BLACK] == 0) ?
                                     3600 :
                                     playerTimeLimit[BLACK];

    updateGameState(true);

    searchEngine.searchAborted.store(false, std::memory_order_relaxed);
}

void Game::initSceneBackground()
{
    // The background has been added to the stylesheet of the view, not the
    // scene. The difference is that the background in the view does not change
    // with the view transformation, whereas the background in the scene does.
    // scene.setBackgroundBrush(QPixmap(":/image/resources/image/background.png"));
#ifdef QT_MOBILE_APP_UI
    scene.setBackgroundBrush(QColor(239, 239, 239));
#endif
}

void Game::initAiThreads()
{
    Threads.set(1);
}

void Game::initDatabaseDialog()
{
    databaseDialog = new DatabaseDialog();
}

void Game::initSettings()
{
    loadGameSettings();
    gameReset();
}

void Game::initGameTest()
{
    gameTest = new AiSharedMemoryDialog();
}

void Game::initMetaTypes()
{
    qRegisterMetaType<std::string>("std::string");
}

void Game::initAiCommandConnections()
{
#ifdef QT_GUI_LIB
    connect(this->gameTest, SIGNAL(command(const string &, bool)), this,
            SLOT(command(const string &, bool)));
#endif
}

void Game::initNetworkComponents()
{
#ifdef NET_FIGHT_SUPPORT
    // TODO(calcitem): WARNING: ThreadSanitizer: data race
    server = new Server(nullptr, 30001);
    uint16_t clientPort = (server->getPort() == 30001) ? 30002 : 30001;
    client = new Client(nullptr, clientPort);
    connect(getClient(), SIGNAL(command(const string &, bool)), this,
            SLOT(command(const string &, bool)));
#endif
}

void Game::initEndgameLearning()
{
#ifdef ENDGAME_LEARNING_FORCE
    if (gameOptions.isEndgameLearningEnabled()) {
        Thread::loadEndgameFileToHashMap();
    }
#endif
}

// Called when we need to start the game if we're still in "ready" phase
void Game::initGameIfReady()
{
    if (position.get_phase() == Phase::ready) {
        gameStart();
    }
}

void Game::stopThreads()
{
    Threads.stop_all();
}

void Game::resetPosition()
{
    position.reset();
    elapsedSeconds[WHITE] = elapsedSeconds[BLACK] = 0;
}

void Game::clearGameState()
{
    resetMoveListKeepFirst();
    resetPerfectAiEngine();
    resetPosition();
}
