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

Game::Game(GameScene &scene, QObject *parent)
    : QObject(parent)
    , scene(scene)
    , timeLimit(0 /* TODO: gameOptions.getMoveTime() */)
    , moveHistory(256)
{
    initializeComponents();
}

Game::~Game()
{
    terminateComponents();
}

void Game::initializeComponents()
{
    initializeSceneBackground();
    initializeAiThreads();
    initializeDatabaseDialog();
    initializeSettings();
    initializeGameTest();
    initializeMetaTypes();
    initializeAiCommandConnections();
    initializeNetworkComponents();
    initializeEndgameLearning();
}

void Game::terminateComponents()
{
    terminateTimer();
    terminateThreads();
    finalizeEndgameLearning();
    clearMoveHistory();
    destroySettings();
}

void Game::resetComponents()
{
    // Reset timer
    resetTimer();

    // Reset game state
    resetGameState();

    // Reset AI Players and Threads (if needed)
    if (!gameOptions.getAutoRestart()) {
        pauseThreads();
        // resetAiPlayers(); // Uncomment if needed
    }

    // Reset UI Elements
    resetUIElements();

    // Reset Time Limit and Update Time Display
    resetAndUpdateTime();

    // Miscellaneous Updates
    updateMiscellaneous();
}

void Game::gameStart()
{
    // moveHistory.clear();
    position.start();
    startTime = time(nullptr);

    // The timer handler is called every 100 milliseconds
    if (timeID == 0) {
        timeID = startTimer(100);
    }

    gameStartTime = now();
    gameStartCycle = stopwatch::rdtscp_clock::now();

#ifdef OPENING_BOOK
    if (openingBookDeque.empty() && !openingBookDequeBak.empty()) {
        openingBookDeque = openingBookDequeBak;
        openingBookDequeBak.clear();
    }
#endif
}

void Game::gameReset()
{
    waitForAiSearchCompletion();
    resetComponents();
    resetElapsedSeconds();
}

void Game::initializeSceneBackground()
{
    // The background has been added to the style sheet of view, but not to
    // scene The difference is that the background in view does not change with
    // the view transformation, and the background in scene changes with the
    // view transformation
    // scene.setBackgroundBrush(QPixmap(":/image/resources/image/background.png"));
#ifdef QT_MOBILE_APP_UI
    scene.setBackgroundBrush(QColor(239, 239, 239));
#endif /* QT_MOBILE_APP_UI */
}

void Game::initializeAiThreads()
{
    // resetAiPlayers();
    createAiThreads();
}

void Game::initializeDatabaseDialog()
{
    databaseDialog = new DatabaseDialog();
}

void Game::initializeSettings()
{
    loadSettings();
    gameReset();
}

void Game::initializeGameTest()
{
    gameTest = new AiSharedMemoryDialog();
}

void Game::initializeMetaTypes()
{
    qRegisterMetaType<std::string>("string");
}

void Game::initializeAiCommandConnections()
{
#ifdef QT_GUI_LIB
    // The command line of AI and controller
    connect(aiThread[WHITE], SIGNAL(command(const string &, bool)), this,
            SLOT(command(const string &, bool)));
    connect(aiThread[BLACK], SIGNAL(command(const string &, bool)), this,
            SLOT(command(const string &, bool)));
    connect(this->gameTest, SIGNAL(command(const string &, bool)), this,
            SLOT(command(const string &, bool)));
#endif // QT_GUI_LIB
}

void Game::initializeNetworkComponents()
{
#ifdef NET_FIGHT_SUPPORT
    // TODO(calcitem): WARNING: ThreadSanitizer: data race
    server = new Server(nullptr, 30001);

    uint16_t clientPort = server->getPort() == 30001 ? 30002 : 30001;
    client = new Client(nullptr, clientPort);
    connect(getClient(), SIGNAL(command(const string &, bool)), this,
            SLOT(command(const string &, bool)));
#endif
}

void Game::initializeEndgameLearning()
{
#ifdef ENDGAME_LEARNING_FORCE
    if (gameOptions.isEndgameLearningEnabled()) {
        Thread::loadEndgameFileToHashMap();
    }
#endif
}

void Game::initiateGameIfReady()
{
    if (position.get_phase() == Phase::ready) {
        gameStart();
    }
}

void Game::terminateThreads()
{
    pauseAndWaitThreads();
    deleteAiThreads();
}

void Game::resetPositionState()
{
    position.reset();
    elapsedSeconds[WHITE] = elapsedSeconds[BLACK] = 0;
    sideToMove = position.side_to_move();
}

void Game::resetGameState()
{
    resetMoveHistoryReserveFirst();
    resetPerfectAi();
    resetPositionState();
}
