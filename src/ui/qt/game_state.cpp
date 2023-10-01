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
    if (!result)
        return;

    updateMoveList();
    updateStatusBar();
    updateMoveListModelFromMoveList();
    handleGameOutcome();
    sideToMove = position.side_to_move();
    updateScene();
}

// Update move and position list
void Game::updateMoveList()
{
    gameMoveList.emplace_back(position.record);
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
    for (const auto &i : *getMoveList()) {
        if (k++ <= currentRow)
            continue;
        moveListModel.insertRow(++currentRow);
        moveListModel.setData(moveListModel.index(currentRow), i.c_str());
    }
}

// Handle game outcome and restart logic
void Game::handleGameOutcome()
{
    const Color winner = position.get_winner();
    if (winner != NOBODY) {
        handleWinOrLoss();
    } else {
        resumeAiThreads(position.sideToMove);
    }
}

// Specific handler for win or lose
void Game::handleWinOrLoss()
{
    if (gameOptions.getAutoRestart()) {
        performAutoRestartActions();
    } else {
        pauseThreads();
    }
}

// Actions to perform if auto-restart is enabled
void Game::performAutoRestartActions()
{
#ifdef NNUE_GENERATE_TRAINING_DATA
    position.nnueWriteTrainingData();
#endif /* NNUE_GENERATE_TRAINING_DATA */

    saveScore();
    gameReset();
    gameStart();
    setEnginesForAiPlayers();
}

// Sets the engines for AI players
void Game::setEnginesForAiPlayers()
{
    if (isAiPlayer[WHITE]) {
        setEngine(WHITE, true);
    }
    if (isAiPlayer[BLACK]) {
        setEngine(BLACK, true);
    }
}
