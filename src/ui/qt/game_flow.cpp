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

bool Game::applyPartialMoveList(int row)
{
    currentRow = row;
    const QStringList strList = moveListModel.stringList();
    debugPrintf("rows: %d current: %d\n", moveListModel.rowCount(), row);

    for (int i = 0; i <= row; i++) {
        debugPrintf("%s\n", strList.at(i).toStdString().c_str());
        position.command(strList.at(i).toStdString().c_str());
    }

    return true;
}

// Update the board state by applying moves up to a specific row in the list.
// Optionally force an update even if the current row matches the requested row.
bool Game::updateBoardState(int row, bool forceUpdate)
{
    // Skip updating if the currently viewed row matches the requested row,
    // unless forceUpdate is true.
    if (currentRow == row && !forceUpdate)
        return false;

    // Apply the moves from the move list up to the specified row.
    applyPartialMoveList(row);

    // Refresh the game scene to reflect the new board state.
    updateScene();

    return true;
}

bool Game::resign()
{
    const bool result = position.resign(position.sideToMove);

    if (!result) {
        return false;
    }

    // Insert the new record line into list model
    currentRow = moveListModel.rowCount() - 1;
    int k = 0;

    // Output command line
    for (const auto &i : *getMoveList()) {
        // Skip added because the standard list container has no index
        if (k++ <= currentRow) {
            continue;
        }
            
        moveListModel.insertRow(++currentRow);
        moveListModel.setData(moveListModel.index(currentRow), i.c_str());
    }

    if (position.get_winner() != NOBODY) {
        playSound(GameSound::resign);
    }

    return result;
}

GameSound Game::identifySoundType(Action action)
{
    switch (action) {
    case Action::select:
    case Action::place:
        return GameSound::drag;
    case Action::remove:
        return GameSound::remove;
    case Action::none:
        return GameSound::none;
    }

    return GameSound::none;
}

bool Game::command(const string &cmd, bool update /* = true */)
{
    Q_UNUSED(hasSound)

#ifdef QT_GUI_LIB
    // Prevents receiving instructions sent by threads that end late
    if (sender() == aiThread[WHITE] && !isAiPlayer[WHITE]) {
        return false;
    }        

    if (sender() == aiThread[BLACK] && !isAiPlayer[BLACK]) {
        return false;
    }
#endif // QT_GUI_LIB

    auto soundType = identifySoundType(position.get_action());

    if (position.get_phase() == Phase::ready) {
        gameStart();
    }

    debugPrintf("Computer: %s\n\n", cmd.c_str());

    // TODO: Distinguish these two cmds,
    // one starts with info and the other starts with (
    if (cmd[0] != 'i') {
        gameMoveList.emplace_back(cmd);
    }

#ifdef NNUE_GENERATE_TRAINING_DATA
    nnueTrainingDataBestMove = cmd;
#endif /* NNUE_GENERATE_TRAINING_DATA */

    // TODO: Distinguish these two cmds,
    // one starts with info and the other starts with (
    if (cmd[0] != 'i' && cmd.size() > strlen("-(1,2)")) {
        posKeyHistory.push_back(position.key());
    } else {
        posKeyHistory.clear();
    }

    if (!position.command(cmd.c_str())) {
        return false;
    }

    sideToMove = position.side_to_move();

    if (soundType == GameSound::drag &&
        position.get_action() == Action::remove) {
        soundType = GameSound::mill;
    }

    if (update) {
        playSound(soundType);
        //updateScene();
    }

    // Signal update status bar
    updateScene();
    message = QString::fromStdString(getTips());
    emit statusBarChanged(message);

    // For opening
    if (getMoveList()->size() <= 1) {
        moveListModel.removeRows(0, moveListModel.rowCount());
        moveListModel.insertRow(0);
        moveListModel.setData(moveListModel.index(0), position.get_record());
        currentRow = 0;
    } else {
        // For the current position
        currentRow = moveListModel.rowCount() - 1;
        // Skip the added rows. The iterator does not support the + operator and
        // can only skip one by one++
        auto i = getMoveList()->begin();
        for (int r = 0; i != getMoveList()->end(); ++i) {
            if (r++ > currentRow)
                break;
        }
        // Insert the new score line into list model
        while (i != getMoveList()->end()) {
            moveListModel.insertRow(++currentRow);
            moveListModel.setData(moveListModel.index(currentRow),
                                  (*i++).c_str());
        }
    }

    // Play win or lose sound
#ifndef DO_NOT_PLAY_WIN_SOUND
    const Color winner = position.get_winner();
    if (winner != NOBODY &&
        moveListModel.data(moveListModel.index(currentRow - 1))
            .toString()
            .contains("Time over.")) {
        playSound(GameSound::win);
    }
#endif

    // AI Settings
    // If it's not decided yet
    if (position.get_winner() == NOBODY) {
        resumeAiThreads(position.sideToMove);
    } else {
        // If it's decided
        pauseThreads();

        printStats();

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
        }

#ifdef MESSAGE_BOX_ENABLE
        message = QString::fromStdString(position.get_tips());
        QMessageBox::about(NULL, "Game Result", message);
#endif
    }

    if (cmd[0] != 'i') {
        gameTest->writeToMemory(QString::fromStdString(cmd));
    }

#ifdef NET_FIGHT_SUPPORT
    // Network: put the method in the server's send list
    getServer()->setAction(QString::fromStdString(cmd));
#endif

#ifdef ANALYZE_POSITION
    if (!gameOptions.getUsePerfectDatabase()) {
        if (isAiPlayer[WHITE]) {
            aiThread[WHITE]->analyze(WHITE);
        } else if (isAiPlayer[BLACK]) {
            aiThread[BLACK]->analyze(BLACK);
        }
    }
#endif // ANALYZE_POSITION

    updateStatistics();

#ifdef NNUE_GENERATE_TRAINING_DATA
    position.nnueGenerateTrainingFen();
#endif /* NNUE_GENERATE_TRAINING_DATA */

    return true;
}

void Game::printStats()
{
    gameEndTime = now();
    gameDurationTime = gameEndTime - gameStartTime;

    gameEndCycle = stopwatch::rdtscp_clock::now();

    debugPrintf("Game Duration Time: %lldms\n", gameDurationTime);

#ifdef TIME_STAT
    debugPrintf("Sort Time: %I64d + %I64d = %I64dms\n",
                aiThread[WHITE]->sortTime, aiThread[BLACK]->sortTime,
                (aiThread[WHITE]->sortTime + aiThread[BLACK]->sortTime));
    aiThread[WHITE]->sortTime = aiThread[BLACK]->sortTime = 0;
#endif // TIME_STAT

#ifdef CYCLE_STAT
    debugPrintf("Sort Cycle: %ld + %ld = %ld\n", aiThread[WHITE]->sortCycle,
                aiThread[BLACK]->sortCycle,
                (aiThread[WHITE]->sortCycle + aiThread[BLACK]->sortCycle));
    aiThread[WHITE]->sortCycle = aiThread[BLACK]->sortCycle = 0;
#endif // CYCLE_STAT

#if 0
            gameDurationCycle = gameEndCycle - gameStartCycle;
            debugPrintf("Game Start Cycle: %u\n", gameStartCycle);
            debugPrintf("Game End Cycle: %u\n", gameEndCycle);
            debugPrintf("Game Duration Cycle: %u\n", gameDurationCycle);
#endif

#ifdef TRANSPOSITION_TABLE_DEBUG
    size_t hashProbeCount_1 = aiThread[WHITE]->ttHitCount +
                              aiThread[WHITE]->ttMissCount;
    size_t hashProbeCount_2 = aiThread[BLACK]->ttHitCount +
                              aiThread[BLACK]->ttMissCount;

    debugPrintf("[key 1] probe: %llu, hit: %llu, miss: %llu, hit rate: "
                "%llu%%\n",
                hashProbeCount_1, aiThread[WHITE]->ttHitCount,
                aiThread[WHITE]->ttMissCount,
                aiThread[WHITE]->ttHitCount * 100 / hashProbeCount_1);

    debugPrintf("[key 2] probe: %llu, hit: %llu, miss: %llu, hit rate: "
                "%llu%%\n",
                hashProbeCount_2, aiThread[BLACK]->ttHitCount,
                aiThread[BLACK]->ttMissCount,
                aiThread[BLACK]->ttHitCount * 100 / hashProbeCount_2);

    debugPrintf("[key +] probe: %llu, hit: %llu, miss: %llu, hit rate: "
                "%llu%%\n",
                hashProbeCount_1 + hashProbeCount_2,
                aiThread[WHITE]->ttHitCount + aiThread[BLACK]->ttHitCount,
                aiThread[WHITE]->ttMissCount + aiThread[BLACK]->ttMissCount,
                (aiThread[WHITE]->ttHitCount + aiThread[BLACK]->ttHitCount) *
                    100 / (hashProbeCount_1 + hashProbeCount_2));
#endif // TRANSPOSITION_TABLE_DEBUG
}

void Game::updateStatistics()
{
    int total = position.score[WHITE] + position.score[BLACK] +
                position.score_draw;
    float blackWinRate, whiteWinRate, drawRate;

    if (total == 0) {
        blackWinRate = 0;
        whiteWinRate = 0;
        drawRate = 0;
    } else {
        blackWinRate = static_cast<float>(position.score[WHITE]) * 100 / total;
        whiteWinRate = static_cast<float>(position.score[BLACK]) * 100 / total;
        drawRate = static_cast<float>(position.score_draw) * 100 / total;
    }

    const auto flags = cout.flags();
    cout << "Score: " << position.score[WHITE] << " : " << position.score[BLACK]
         << " : " << position.score_draw << "\ttotal: " << total << std::endl;
    cout << std::fixed << std::setprecision(2) << blackWinRate
         << "% : " << whiteWinRate << "% : " << drawRate << "%" << std::endl;
    cout.flags(flags);
}
