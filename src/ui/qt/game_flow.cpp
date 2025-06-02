// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_flow.cpp

#include <cinttypes>
#include <iomanip>
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

#include "game.h"
#include "option.h"
#include "search.h"
#include "search_engine.h"
#include "engine_controller.h"

using std::to_string;

bool Game::applyMoveListUntilRow(int row)
{
    currentRow = row;
    const QStringList strList = moveListModel.stringList();
    // Remove debug output that causes "rows: 1 current: 0" message at startup
    // debugPrintf("rows: %d current: %d\n", moveListModel.rowCount(), row);

    // posKeyHistory.clear();

    // Apply each command up to 'row' to the Position
    for (int i = 0; i <= row; i++) {
        debugPrintf("%s\n", strList.at(i).toStdString().c_str());
        position.command(strList.at(i).toStdString().c_str());
    }

    return true;
}

// Update the board state by applying moves up to a specific row in the list.
// Optionally force an update even if the current row matches the requested row.
bool Game::refreshBoardState(int row, bool forceUpdate)
{
    // If current row is the same as requested row and not forced, do nothing
    if (currentRow == row && !forceUpdate)
        return false;

    // Apply partial move list up to 'row'
    applyMoveListUntilRow(row);

    // Update the scene to reflect the new position
    refreshScene();

    return true;
}

bool Game::resignGame()
{
    const bool result = position.resign(position.sideToMove);
    if (!result) {
        return false;
    }

    currentRow = moveListModel.rowCount() - 1;
    int k = 0;

    // Insert any new move strings into the model
    for (const auto &i : *getMoveList()) {
        if (k++ <= currentRow) {
            continue;
        }
        moveListModel.insertRow(++currentRow);
        moveListModel.setData(moveListModel.index(currentRow), i.c_str());
    }

    // Play resign sound if a winner is determined
    if (position.get_winner() != NOBODY) {
        playGameSound(GameSound::resign);
    }

    return result;
}

GameSound Game::getSoundTypeForAction(Action action)
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

/**
 * @brief Processes the given command string, updates the Position,
 *        and triggers the AI move if needed. Replaces direct thread usage
 *        with calls to EngineController.
 */
bool Game::command(const std::string &command, bool update /*= true*/)
{
    Q_UNUSED(hasSound)

    char moveStr[64] = {0};
    int bestvalue = 0;
    std::string cmd = command;

    // Identify sound type before we mutate the Position
    auto soundType = getSoundTypeForAction(position.get_action());

    // If engine is in 'ready' phase, start the game
    if (position.get_phase() == Phase::ready) {
        gameStart();
    }

    // Remove "aimovetype" substring if present (legacy logic)
    size_t aimovetype_pos = cmd.find("aimovetype");
    if (aimovetype_pos != std::string::npos) {
        size_t bestmove_pos = cmd.find("bestmove", aimovetype_pos);
        if (bestmove_pos != std::string::npos) {
            cmd.erase(aimovetype_pos, bestmove_pos - aimovetype_pos);
        } else {
            cmd.erase(aimovetype_pos);
        }
    }

#ifdef _MSC_VER
    sscanf_s(cmd.c_str(), "info score %d bestmove %63s", &bestvalue, moveStr,
             (unsigned)_countof(moveStr));
#else
    sscanf(cmd.c_str(), "info score %d bestmove %63s", &bestvalue, moveStr);
#endif

    // If we didn't find a bestmove token, store the entire cmd into moveStr
    if (strlen(moveStr) == 0 && !cmd.empty()) {
#ifdef _MSC_VER
        strncpy_s(moveStr, sizeof(moveStr), cmd.c_str(), _TRUNCATE);
#else
        strncpy(moveStr, cmd.c_str(), sizeof(moveStr) - 1);
        moveStr[sizeof(moveStr) - 1] = '\0';
#endif
    }

    debugPrintf("Computer: %s\n\n", cmd.c_str());

    // Move list management is now handled centrally by refreshMoveList()
    // Remove direct gameMoveList manipulation from here to avoid duplicates

#ifdef NNUE_GENERATE_TRAINING_DATA
    nnueTrainingDataBestMove = cmd;
#endif /* NNUE_GENERATE_TRAINING_DATA */

    // TODO: It means that the 50 rule is only calculated at the beginning of
    // the moving phase, and it is not sure whether it complies with the rules.
    // For standard notation: move moves have length 5
    if (strlen(moveStr) == 5) {
        posKeyHistory.push_back(position.key());
    } else {
        posKeyHistory.clear();
    }

    // Send the command to the Position
    if (!position.command(cmd.c_str())) {
        return false;
    }

    // If we selected a piece and next action is remove, it might be a mill
    if (soundType == GameSound::drag &&
        position.get_action() == Action::remove) {
        soundType = GameSound::mill;
    }

    if (update) {
        playGameSound(soundType);
        // Optionally call refreshScene() here if needed
        // refreshScene();
    }

    refreshStatusBar();

    // The move list handling: either create or append to the model
    if (getMoveList()->size() <= 1) {
        // Clear old moves and add the first record
        moveListModel.removeRows(0, moveListModel.rowCount());
        moveListModel.insertRow(0);
        moveListModel.setData(moveListModel.index(0), position.get_record());
        currentRow = 0;
    } else {
        // Insert new lines for further moves
        currentRow = moveListModel.rowCount() - 1;
        auto i = getMoveList()->begin();
        auto endIter = getMoveList()->end();
        for (int r = 0; i != endIter; ++i) {
            if (r++ > currentRow)
                break;
        }
        while (i != endIter) {
            moveListModel.insertRow(++currentRow);
            moveListModel.setData(moveListModel.index(currentRow),
                                  (*i++).c_str());
        }
    }

#ifndef DO_NOT_PLAY_WIN_SOUND
    // If there's a winner and the previous line ends with "Time over."
    const Color winner = position.get_winner();
    if (winner != NOBODY &&
        moveListModel.data(moveListModel.index(currentRow - 1))
            .toString()
            .contains("Time over.")) {
        playGameSound(GameSound::win);
    }
#endif

    // If no winner yet, and it's AI's turn, we use EngineController
    if (position.get_winner() == NOBODY) {
        // Remove the direct engine call here - this should be handled by
        // updateGameState -> processGameOutcome -> submitAiSearch The old code:
        // engineController.handleCommand("go", &position); This was causing the
        // AI to not work properly because it bypassed the correct signal flow

        // The correct flow is: command() calls updateGameState() which calls
        // processGameOutcome() which calls submitAiSearch() if it's AI's turn
    } else {
        // If the game is finished, print stats, handle auto-restart, etc.
        printGameStatistics();
        refreshLcdDisplay();

        if (gameOptions.getAutoRestart()) {
#ifdef NNUE_GENERATE_TRAINING_DATA
            position.nnueWriteTrainingData();
#endif
            saveGameScore();
            gameReset();
            gameStart();

            if (isAiPlayer[WHITE]) {
                setEngineControl(WHITE, true);
            }
            if (isAiPlayer[BLACK]) {
                setEngineControl(BLACK, true);
            }
        }

#ifdef MESSAGE_BOX_ENABLE
        message = QString::fromStdString(position.get_tips());
        QMessageBox::about(NULL, "Game Result", message);
#endif
    }

    // Write the command into the AI test memory if needed
    gameTest->writeToMemory(QString::fromStdString(cmd));

#ifdef NET_FIGHT_SUPPORT
    // For network play, broadcast the move
    getServer()->setAction(QString::fromStdString(cmd));
#endif

#ifdef ANALYZE_POSITION
    // If we want to analyze the position,
    // we can send an "analyze" command or directly call SearchEngine::analyze.
    // For example:
    if (!gameOptions.getUsePerfectDatabase()) {
        if (isAiPlayer[WHITE]) {
            // Minimal usage:
            searchEngine.analyze(WHITE);
        } else if (isAiPlayer[BLACK]) {
            searchEngine.analyze(BLACK);
        }
    }
#endif

    updateGameStatistics();

    // Call updateGameState to trigger AI moves if needed
    updateGameState(true);

#ifdef NNUE_GENERATE_TRAINING_DATA
    position.nnueGenerateTrainingFen();
#endif

    return true;
}

/**
 * @brief Prints some debug info about the game duration, and any other stats.
 */
void Game::printGameStatistics()
{
    gameEndTime = now();
    gameDurationTime = gameEndTime - gameStartTime;
    gameEndCycle = stopwatch::rdtscp_clock::now();

    debugPrintf("Game Duration Time: %" PRId64 "ms\n",
                static_cast<int64_t>(gameDurationTime));

#ifdef TIME_STAT
    // No direct thread usage, so we skip the old stats that relied on
    // per-thread data
    debugPrintf("Sort Time: <No direct threads to measure>\n");
#endif

#ifdef CYCLE_STAT
    debugPrintf("Sort Cycle: <No direct threads to measure>\n");
#endif

#ifdef TRANSPOSITION_TABLE_DEBUG
    debugPrintf("Transposition Table Debug counters are no longer maintained "
                "per thread.\n");
#endif
}

/**
 * @brief Updates and prints the current scoreboard.
 */
void Game::updateGameStatistics()
{
    int total = score[WHITE] + score[BLACK] + score[DRAW];
    float blackWinRate, whiteWinRate, drawRate;

    if (total == 0) {
        blackWinRate = 0;
        whiteWinRate = 0;
        drawRate = 0;
    } else {
        blackWinRate = static_cast<float>(score[WHITE]) * 100 / total;
        whiteWinRate = static_cast<float>(score[BLACK]) * 100 / total;
        drawRate = static_cast<float>(score[DRAW]) * 100 / total;
    }

    const auto flags = std::cout.flags();
    std::cout << "Score: " << score[WHITE] << " : " << score[BLACK] << " : "
              << score[DRAW] << "\ttotal: " << total << std::endl;
    std::cout << std::fixed << std::setprecision(2) << blackWinRate
              << "% : " << whiteWinRate << "% : " << drawRate << "%"
              << std::endl;
    std::cout.flags(flags);
}
