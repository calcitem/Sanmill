// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// self_play.cpp

#include "self_play.h"
#include "position.h"
#include "search.h"
#include "search_engine.h"
#include "engine_commands.h"
#include "thread_pool.h"
#include <iostream>
#include <thread>
#include <chrono>

// Example of a global or static variable to track game number:
static int g_gameNumber = 0;

static SearchEngine searchEngine;

// Global stats structure
SelfPlayStats g_stats = {0, 0, 0, 0};

int playOneGame()
{
    // Result codes: 0 = draw, 1 = white win, 2 = black win
    int result = 0;

    // 1) Initialize the position for a new game
    EngineCommands::init_start_fen();
    Position pos;
    pos.set(EngineCommands::StartFEN);
    posKeyHistory.clear();

    // 2) Loop until the engine reports Phase::gameOver
    while (pos.get_phase() != Phase::gameOver) {
        uint64_t localId = searchEngine.beginNewSearch(&pos);
        std::cout << "Local ID: " << localId << std::endl;
        Threads.submit([]() { searchEngine.runSearch(); });

        // Wait for either best move or game over or abort
        {
            std::unique_lock<std::mutex> lock(searchEngine.bestMoveMutex);
            searchEngine.bestMoveCV.wait(lock, [&pos] {
                return searchEngine.bestMoveReady ||
                       (pos.get_phase() == Phase::gameOver) ||
                       searchEngine.searchAborted.load(
                           std::memory_order_relaxed);
            });

            // If the game ended, break out
            if (pos.get_phase() == Phase::gameOver)
                break;

            // If we are aborted, break out
            if (searchEngine.searchAborted.load(std::memory_order_relaxed))
                break;

            // Otherwise, we have a ready move
            if (searchEngine.bestMoveReady) {
                Move best = searchEngine.bestMove;
                searchEngine.bestMoveReady = false;
                lock.unlock(); // release before do_move

                if (best == MOVE_NONE || best == MOVE_NULL) {
                    // no move => break or set game over
                    break;
                }

                pos.do_move(best);
            }
        }

        // Check if the move ended the game
        if (pos.get_phase() == Phase::gameOver) {
            break;
        }
    }

    // 4) Once Phase::gameOver is reached, record the final result
    g_gameNumber++;
    g_stats.totalGames++;
    Color winner = pos.get_winner(); // e.g. WHITE, BLACK, DRAW, ...
    if (winner == WHITE)
        result = 1;
    else if (winner == BLACK)
        result = 2;
    else
        result = 0; // treat everything else as draw

    // Update statistics
    switch (result) {
    case 1:
        g_stats.whiteWins++;
        break;
    case 2:
        g_stats.blackWins++;
        break;
    default:
        g_stats.draws++;
        break;
    }

    return result;
}
