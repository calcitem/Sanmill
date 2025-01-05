// game_state.cpp

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
#include "search.h"
#include "search_engine.h"
#include "thread_pool.h"

#if defined(GABOR_MALOM_PERFECT_AI)
#include "perfect/perfect_adaptor.h"
#endif

using std::to_string;

// Function to obtain actions, encapsulates the insertion logic into
// createRuleEntries
std::map<int, QStringList> Game::getActions()
{
    // Main window update menu bar
    // The reason why we don't use the mode of signal and slot is that
    // it's too late for the slot to be associated when the signal is sent
    std::map<int, QStringList> actions;
    createRuleEntries(actions);
    return actions;
}

// Helper function to populate the rule entries in the actions map
void Game::createRuleEntries(std::map<int, QStringList> &actions)
{
    for (int i = 0; i < N_RULES; ++i) {
        actions.insert(createRuleEntry(i));
    }
}

// Function to update game state, broken down into smaller, more focused
// functions
void Game::updateState(bool result)
{
    if (!result) {
        return;
    }

    updateMoveList();
    handleGameOutcome();
    updateStatusBar();
    updateMoveListModelFromMoveList();

    updateScene();
}

// Update move and position list
void Game::updateMoveList()
{
    // If we're in placing phase but the engine is still in "place" action, skip
    if (position.get_phase() == Phase::moving &&
        position.get_action() == Action::place) {
        return;
    }

    // If the last recorded move is the same as the current position record,
    // skip
    if (!gameMoveList.empty() && gameMoveList.back() == position.record) {
        return;
    }

    // Add the new move
    gameMoveList.emplace_back(position.record);

    // Update position key history
    if (strlen(position.record) > strlen("-(1,2)")) {
        posKeyHistory.push_back(position.key());
    } else {
        posKeyHistory.clear();
    }
}

// Update the list model that holds the moves
void Game::updateMoveListModelFromMoveList()
{
    currentRow = moveListModel.rowCount() - 1;
    int k = 0;
    for (const auto &moveString : *getMoveList()) {
        if (k++ <= currentRow)
            continue;
        moveListModel.insertRow(++currentRow);
        moveListModel.setData(moveListModel.index(currentRow),
                              moveString.c_str());
    }
}

// Handle game outcome and restart logic
void Game::handleGameOutcome()
{
    const Color winner = position.get_winner();
    if (winner != NOBODY) {
        handleWinOrLoss();
    } else {
        // Old code called: resumeAiThreads(position.sideToMove);
        // Now, if it's AI's turn, we can simply submit a new AI task.
        if (isAiPlayer[position.side_to_move()]) {
            // For example, we can submit an AI task:
            submitAiTask();
        }
    }
}

void Game::handleWinOrLoss()
{
    if (gameOptions.getAutoRestart()) {
        performAutoRestartActions();
    }
}

void Game::performAutoRestartActions()
{
#ifdef NNUE_GENERATE_TRAINING_DATA
    position.nnueWriteTrainingData();
#endif

    saveScore();
    gameReset();              // resets the board state
    gameStart();              // starts a new game
    setEnginesForAiPlayers(); // re-assign AI players
}

// Sets the engines for AI players
void Game::setEnginesForAiPlayers()
{
    // If white is an AI, call setEngine(WHITE, true)
    if (isAiPlayer[WHITE]) {
        setEngine(WHITE, true);
    }
    // If black is an AI, call setEngine(BLACK, true)
    if (isAiPlayer[BLACK]) {
        setEngine(BLACK, true);
    }
}
