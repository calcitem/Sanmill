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
{
    initializeComponents();

#ifdef QT_GUI_LIB
    connect(&SearchEngine::getInstance(), &SearchEngine::searchCompleted, this,
            &Game::onAiSearchCompleted, Qt::QueuedConnection);

    connect(&SearchEngine::getInstance(), &SearchEngine::command, this,
            &Game::command, Qt::QueuedConnection);
#endif
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
    // Stop the timer
    terminateTimer();

    // Stop AI tasks and do any cleanup
    terminateThreads();

    // Finalize everything else
    finalizeEndgameLearning();
    clearMoveList();
    destroySettings();
}

void Game::resetComponents()
{
    // Reset the timer
    resetTimer();

    // Reset the game state
    resetGameState();

    // If auto-restart is disabled, we can stop the thread pool
    if (!gameOptions.getAutoRestart()) {
        // This stops all queued tasks.
        // Threads.stop_all();
    }

    // Reset UI and time
    resetUIElements();
    resetAndUpdateTime();

    // Other updates
    updateMiscellaneous();
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

    resetComponents();
    resetElapsedSeconds();
    reinitMoveListModel();
    updateStatusBar(true);
    updateState(true);
}

void Game::initializeSceneBackground()
{
    // The background has been added to the stylesheet of the view, not the
    // scene. The difference is that the background in the view does not change
    // with the view transformation, whereas the background in the scene does.
    // scene.setBackgroundBrush(QPixmap(":/image/resources/image/background.png"));
#ifdef QT_MOBILE_APP_UI
    scene.setBackgroundBrush(QColor(239, 239, 239));
#endif
}

void Game::initializeAiThreads()
{
    Threads.set(1);
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
    connect(this->gameTest, SIGNAL(command(const string &, bool)), this,
            SLOT(command(const string &, bool)));
#endif
}

void Game::initializeNetworkComponents()
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

void Game::initializeEndgameLearning()
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

void Game::terminateThreads()
{
    Threads.stop_all();
}

void Game::resetPositionState()
{
    position.reset();
    elapsedSeconds[WHITE] = elapsedSeconds[BLACK] = 0;
}

void Game::resetGameState()
{
    resetMoveListReserveFirst();
    resetPerfectAi();
    resetPositionState();
}
