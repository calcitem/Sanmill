// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// engine_commands.cpp

#include "engine_commands.h"

#include "thread.h"
#include "search.h"
#include "thread_pool.h"
#include "position.h"
#include "uci.h"
#include "search_engine.h"

#include <string>
#include <cstring>
#include <cassert>

using std::string;

extern ThreadPool Threads;

namespace EngineCommands {

// FEN string of the initial position, normal mill game
const char *StartFEN9 = "********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0"
                        " 0 1";
const char *StartFEN10 = "********/********/******** w p p 0 10 0 10 0 0 0 0 0 "
                         "0 0 0 1";
const char *StartFEN11 = "********/********/******** w p p 0 11 0 11 0 0 0 0 0 "
                         "0 0 0 1";
const char *StartFEN12 = "********/********/******** w p p 0 12 0 12 0 0 0 0 0 "
                         "0 0 0 1";

char StartFEN[BUFSIZ];

/// Initializes the starting FEN based on pieceCount.
/// This function should be called once during the engine initialization.
void init_start_fen()
{
#ifdef _MSC_VER
    switch (rule.pieceCount) {
    case 9:
        strncpy_s(StartFEN, BUFSIZ, StartFEN9, BUFSIZ - 1);
        break;
    case 10:
        strncpy_s(StartFEN, BUFSIZ, StartFEN10, BUFSIZ - 1);
        break;
    case 11:
        strncpy_s(StartFEN, BUFSIZ, StartFEN11, BUFSIZ - 1);
        break;
    case 12:
        strncpy_s(StartFEN, BUFSIZ, StartFEN12, BUFSIZ - 1);
        break;
    default:
        assert(0); // Unsupported piece count
        break;
    }
#else
    switch (rule.pieceCount) {
    case 9:
        strncpy(StartFEN, StartFEN9, BUFSIZ - 1);
        break;
    case 10:
        strncpy(StartFEN, StartFEN10, BUFSIZ - 1);
        break;
    case 11:
        strncpy(StartFEN, StartFEN11, BUFSIZ - 1);
        break;
    case 12:
        strncpy(StartFEN, StartFEN12, BUFSIZ - 1);
        break;
    default:
        assert(0); // Unsupported piece count
        break;
    }
#endif

    StartFEN[BUFSIZ - 1] = '\0'; // Ensure null-termination
}

// go() is called when engine receives the "go" UCI command. The function sets
// the thinking time and other parameters from the input string, then starts
// the search.
void go(SearchEngine &searchEngine, Position *pos)
{
#ifdef UCI_AUTO_RE_GO
begin:
#endif

    searchEngine.beginNewSearch(pos);

    Threads.submit([&searchEngine]() { searchEngine.runSearch(); });

    if (pos->get_phase() == Phase::gameOver) {
#ifdef UCI_AUTO_RESTART
        // TODO(calcitem)
        Threads.stop_all();

        Threads.set(1);
        go(searchEngine, pos);
#else
        return;
#endif
    }

#ifdef UCI_AUTO_RE_GO
    goto begin;
#endif
}

// analyze() is called when engine receives the "analyze" UCI command.
// The function evaluates all legal moves for the current position and
// outputs an analysis report.
void analyze(SearchEngine &searchEngine, Position *pos)
{
    searchEngine.beginNewAnalyze(pos);

    Threads.submit([&searchEngine]() { searchEngine.runAnalyze(); });
}

// position() is called when engine receives the "position" UCI command.
// The function sets up the position described in the given FEN string ("fen")
// or the starting position ("startpos") and then makes the moves given in the
// following move list ("moves").
void position(Position *pos, std::istringstream &is)
{
    Move m;
    string token, fen;

    is >> token;

    if (token == "startpos") {
        init_start_fen(); // Initialize StartFEN
        fen = StartFEN;
        is >> token; // Consume "moves" token if any
    } else if (token == "fen") {
        while (is >> token && token != "moves") {
            fen += token + " ";
        }
    } else {
        return;
    }

    posKeyHistory.clear();

    pos->set(fen);

    // Parse move list (if any)
    while (is >> token && (UCI::to_move(pos, token)) != MOVE_NONE) {
        m = UCI::to_move(pos, token);
        pos->do_move(m);
        if (type_of(m) == MOVETYPE_MOVE) {
            posKeyHistory.push_back(pos->key());
        } else {
            posKeyHistory.clear();
        }
    }

    // TODO: Old：Threads.main()->us = pos->sideToMove;
}

} // namespace EngineCommands
