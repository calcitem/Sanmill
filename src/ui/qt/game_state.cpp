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

std::map<int, QStringList> Game::getActions()
{
    // Main window update menu bar
    // The reason why we don't use the mode of signal and slot is that
    // it's too late for the slot to be associated when the signal is sent
    std::map<int, QStringList> actions;

    // The key of map stores int index value, and value stores rule name and
    // rule prompt
    for (int i = 0; i < N_RULES; ++i) {
        actions.insert(createRuleEntry(i));
    }

    return actions;
}

void Game::updateState(bool result)
{
    if (!result)
        return;

    moveHistory.emplace_back(position.record);
    if (strlen(position.record) > strlen("-(1,2)")) {
        posKeyHistory.push_back(position.key());
    } else {
        posKeyHistory.clear();
    }

    // Signal update status bar
    updateScene();
    message = QString::fromStdString(getTips());
    emit statusBarChanged(message);

    // Insert the new score line into list model
    currentRow = moveListModel.rowCount() - 1;
    int k = 0;

    // Output command line
    for (const auto &i : *move_history()) {
        // Skip added because the standard list container has no subscripts
        if (k++ <= currentRow)
            continue;
        moveListModel.insertRow(++currentRow);
        moveListModel.setData(moveListModel.index(currentRow), i.c_str());
    }

    // Play win or lose sound
#ifndef DO_NOT_PLAY_WIN_SOUND
    const Color winner = position.get_winner();
    if (winner != NOBODY &&
        moveListModel.data(moveListModel.index(currentRow - 1))
            .toString()
            .contains("Time over."))
        playSound(GameSound::win, winner);
#endif

    // AI settings
    // If it's not decided yet
    if (position.get_winner() == NOBODY) {
        resumeAiThreads(position.sideToMove);
    } else {
        // If it's decided
        if (gameOptions.getAutoRestart()) {
#ifdef NNUE_GENERATE_TRAINING_DATA
            position.nnueWriteTrainingData();
#endif /* NNUE_GENERATE_TRAINING_DATA */

            saveScore();

            gameReset();
            gameStart();

            if (isAiPlayer[WHITE]) {
                setEngine(WHITE, true);
            }
            if (isAiPlayer[BLACK]) {
                setEngine(BLACK, true);
            }
        } else {
            pauseThreads();
        }
    }

    sideToMove = position.side_to_move();
    updateScene();
}
