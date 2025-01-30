// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_ai.cpp

#include <QThread>
#include <QTimer>
#include "game.h"
#include "option.h"
#include "thread_pool.h"

#if defined(GABOR_MALOM_PERFECT_AI)
#include "perfect/perfect_adaptor.h"
#endif

#include "engine_controller.h"
#include "engine_commands.h"

// This increments when an AI task is submitted, and decrements when the task
// finishes.
std::atomic<int> g_activeAiTasks {0};

bool Game::isAiSideToMove() const
{
    // Same logic: check if the current side to move is an AI
    return isAiPlayer[position.side_to_move()];
}

void Game::resetPerfectAiEngine()
{
#if defined(GABOR_MALOM_PERFECT_AI)
    // If Perfect Database is enabled, reset it
    if (gameOptions.getUsePerfectDatabase()) {
        perfect_reset();
    }
#endif
}

/**
 * @brief Waits for AI tasks to finish. Originally, we might have spun on
 * ThreadPool. Now it’s optional, as EngineController itself starts threads
 * internally.
 */
void Game::waitUntilAiSearchDone()
{
    // If needed, you can still spin or sleep while checking g_activeAiTasks.
    // For demonstration, just show a debug message.
    debugPrintf("Waiting for AI tasks to finish...\n");

    while (g_activeAiTasks.load(std::memory_order_relaxed) > 0) {
        debugPrintf(".");
        QThread::msleep(100);
    }
    debugPrintf("\nAI tasks have finished.\n");
}

/**
 * @brief Submits an AI task. Instead of calling Threads.submit() directly,
 *        build and send commands to EngineController, which will handle search
 * threads internally.
 */
void Game::submitAiSearch()
{
    // Increment the global counter of active AI tasks.
    g_activeAiTasks.fetch_add(1, std::memory_order_relaxed);

    Color side = position.side_to_move();
    QString sideName = (side == WHITE ? "White" : "Black");
    QString thinkingMessage = QString("%1 is thinking...").arg(sideName);
    emit statusBarChanged(thinkingMessage);

    std::ostringstream ss;
    ss << "position fen " << position.fen();
    if (!gameMoveList.empty()) {
        ss << " moves";
        for (auto &mv : gameMoveList) {
            ss << " " << mv;
        }
    }
    std::string posCmd = ss.str();

    // Call EngineController to set the position.
    engineController.handleCommand(posCmd, &position);

    // Start the search with "go".
    // EngineController::go() will internally manage threading in SearchEngine.
    engineController.handleCommand("go", &position);

    // Decrement the counter in the future when the search completes.
    // Usually you'd do this in a callback or slot that listens for completion.
    // For demonstration, here's a simple approach that schedules a tiny
    // follow-up check: (In a real app, you'd tie this to searchCompleted or
    // similar.)
    QTimer::singleShot(500, [this]() {
        // In real usage, check if search actually ended, or rely on signals
        // from EngineController. For now, just decrement to simulate finishing:
        g_activeAiTasks.fetch_sub(1, std::memory_order_relaxed);

        // Emit a signal that AI search completed:
        emit aiSearchCompleted();
    });
}

/**
 * @brief Triggered when an AI search is completed. Here you might update UI,
 *        check if there's a winner, or start another move if still AI's turn.
 */
void Game::handleAiSearchCompleted()
{
    debugPrintf("handleAiSearchCompleted: An AI search has completed.\n");

    emit statusBarChanged("AI finished.");

    // Update status/UI:
    refreshStatusBar();
    // applyMoveListUntilRow(currentRow);
    refreshScene();

    if (g_activeAiTasks.load(std::memory_order_relaxed) == 0) {
        debugPrintf("No active AI tasks remain.\n");
    }
}
