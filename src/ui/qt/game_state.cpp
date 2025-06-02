// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

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
// buildRuleEntries
std::map<int, QStringList> Game::getRuleActions()
{
    // Main window update menu bar
    // The reason why we don't use the mode of signal and slot is that
    // it's too late for the slot to be associated when the signal is sent
    std::map<int, QStringList> actions;
    buildRuleEntries(actions);
    return actions;
}

// Helper function to populate the rule entries in the actions map
void Game::buildRuleEntries(std::map<int, QStringList> &actions)
{
    for (int i = 0; i < N_RULES; ++i) {
        actions.insert(buildRuleEntry(i));
    }
}

// Function to update game state, broken down into smaller, more focused
// functions
void Game::updateGameState(bool result)
{
    if (!result) {
        return;
    }

    refreshMoveList();
    processGameOutcome();
    refreshStatusBar();
    syncMoveListToModel();

    refreshScene();

    // Handle timer logic for player moves
    if (timerEnabled) {
        Color currentPlayer = position.side_to_move();

        // Stop any existing timer
        stopPlayerTimer();

        // Start timer for the current player if game is not over
        if (position.get_winner() == NOBODY) {
            startPlayerTimer(currentPlayer);
        }

        // After attempting to start timer, if this was the very first move
        // (i.e., a move has been recorded) then mark first-move flag false.
        // We use the move list size to detect that at least one real move
        // exists. This avoids clearing the flag during the initial update
        // that happens right after gameStart()/gameReset().
        if (isFirstMoveOfGame && !gameMoveList.empty()) {
            isFirstMoveOfGame = false;
        }
    }
}

// Update move and position list
void Game::refreshMoveList()
{
    // If we're in placing phase but the engine is still in "place" action, skip
    if (position.get_phase() == Phase::moving &&
        position.get_action() == Action::place) {
        return;
    }

    // Simple duplicate check: if the last recorded move is the same as current
    // record, skip This is now the single point of truth for move list
    // management
    if (!gameMoveList.empty() && gameMoveList.back() == position.record) {
        return;
    }

    // Add the new move
    gameMoveList.emplace_back(position.record);

    // Update position key history
    // For standard notation: move moves have length 5
    if (strlen(position.record) == 5) {
        posKeyHistory.push_back(position.key());
    } else {
        posKeyHistory.clear();
    }
}

// Update the list model that holds the moves
void Game::syncMoveListToModel()
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
void Game::processGameOutcome()
{
    const Color winner = position.get_winner();
    if (winner != NOBODY) {
        processWinLoss();
    } else {
        // Old code called: resumeAiThreads(position.sideToMove);
        // Now, if it's AI's turn, we can simply submit a new AI task.
        if (isAiPlayer[position.side_to_move()]) {
            // For example, we can submit an AI task:
            submitAiSearch();
        }
    }
}

void Game::processWinLoss()
{
    if (gameOptions.getAutoRestart()) {
        executeAutoRestart();
    }
}

void Game::executeAutoRestart()
{
#ifdef NNUE_GENERATE_TRAINING_DATA
    position.nnueWriteTrainingData();
#endif

    saveGameScore();
    gameReset();       // resets the board state
    gameStart();       // starts a new game
    assignAiEngines(); // re-assign AI players
}

// Sets the engines for AI players
void Game::assignAiEngines()
{
    // If white is an AI, call setEngineControl(WHITE, true)
    if (isAiPlayer[WHITE]) {
        setEngineControl(WHITE, true);
    }
    // If black is an AI, call setEngineControl(BLACK, true)
    if (isAiPlayer[BLACK]) {
        setEngineControl(BLACK, true);
    }
}
