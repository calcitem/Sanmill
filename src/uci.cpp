// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// uci.cpp

#include <iostream>
#include <sstream>
#include <vector>

#include "thread.h"
#include "thread_pool.h"
#include "uci.h"
#include "misc.h"
#include "engine_controller.h"
#include "search_engine.h"
#include "self_play.h"

#ifdef FLUTTER_UI
#include "base.h"
#include "command_channel.h"
#endif

#include "engine_controller.h"
#include "engine_commands.h"

using std::cin;
using std::istream;
using std::istringstream;
using std::skipws;
using std::string;
using std::stringstream;
using std::vector;

extern vector<string> setup_bench(Position *, istream &);

namespace {

void initialize_engine(Position *pos)
{
    // Delegate initialization to EngineCommands
    EngineCommands::init_start_fen();
    pos->set(EngineCommands::StartFEN);
}

// setoption() is called when engine receives the "setoption" UCI command. The
// function updates the UCI option ("name") to the given value ("value").

void setoption(istringstream &is)
{
    string token, name, value;

    is >> token; // Consume "name" token

    // Read option name (can contain spaces)
    while (is >> token && token != "value")
        name += (name.empty() ? "" : " ") + token;

    // Read option value (can contain spaces)
    while (is >> token)
        value += (value.empty() ? "" : " ") + token;

    if (Options.count(name))
        Options[name] = value;
    else
        sync_cout << "No such option: " << name << sync_endl;
}

} // namespace

/// UCI::loop() waits for a command from stdin, parses it and calls the
/// appropriate function. Also intercepts EOF from stdin to ensure gracefully
/// exiting if the GUI dies unexpectedly. When called with some command line
/// arguments, e.g. to run 'bench', once the command is executed the function
/// returns immediately. In addition to the UCI ones, also some additional debug
/// commands are supported.

void UCI::loop(int argc, char *argv[])
{
    const auto pos = new Position;
    string token, cmd;

    SearchEngine searchEngine;
    EngineController engineController(searchEngine);

    initialize_engine(pos);

    for (int i = 1; i < argc; ++i)
        cmd += std::string(argv[i]) + " ";

    do {
#ifdef FLUTTER_UI
        static const int LINE_INPUT_MAX_CHAR = 4096;
        char line[LINE_INPUT_MAX_CHAR];
        CommandChannel *channel = CommandChannel::getInstance();
        while (!channel->popupCommand(line))
            Idle();
        cmd = line;
        LOGD("[uci] input: %s\n", line);
#else
        if (argc == 1 && !getline(cin, cmd)) // Block here waiting for input or
                                             //  EOF
            cmd = "quit";
#endif

        istringstream is(cmd);

        token.clear(); // Avoid a stale if getline() returns empty or blank line
        is >> skipws >> token;

        if (token == "quit" || token == "stop") {
            searchEngine.searchAborted.store(true, std::memory_order_relaxed);
            // Threads.stop_all(); // Stop all tasks
        }

        // The GUI sends 'ponderhit' to tell us the user has played the expected
        // move. So 'ponderhit' will be sent if we were told to ponder on the
        // same move the user has played. We should continue searching but
        // switch from pondering to normal search.
        else if (token == "ponderhit") {
            Threads.submit([]() {
                // Add logic to handle "ponderhit" if needed
            });
        }

        else if (token == "uci")
            sync_cout << "id name " << engine_info(true) << "\n"
                      << Options << "\nuciok" << sync_endl;

        else if (token == "setoption")
            setoption(is);

        else if (token == "go" || token == "position" ||
                 token == "ucinewgame" || token == "d" || token == "compiler" ||
                 token == "analyze") {
            // Pass the entire command to EngineController
            engineController.handleCommand(cmd, pos);
        }
#ifdef SELF_PLAY
        else if (token == "selfplay") {
            // 1) Decide how many games you want
            int numberOfGames = 1;

            // 2) For each game, do self-play
            for (int i = 0; i < numberOfGames; i++) {
                playOneGame();
            }

            // 3) Print aggregated stats
            //    Make sure you #include "SelfPlayStats.h" to access g_stats.
            sync_cout << "Self-play completed. " << g_stats.totalGames
                      << " games." << sync_endl;
            sync_cout << "White wins: " << g_stats.whiteWins
                      << ", Black wins: " << g_stats.blackWins
                      << ", Draws: " << g_stats.draws << sync_endl;

            // Calculate win rates etc.
            // You can do your ratio or percentage here:
            double whiteRate = 0.0, blackRate = 0.0, drawRate = 0.0;
            if (g_stats.totalGames > 0) {
                whiteRate = 100.0 * g_stats.whiteWins / g_stats.totalGames;
                blackRate = 100.0 * g_stats.blackWins / g_stats.totalGames;
                drawRate = 100.0 * g_stats.draws / g_stats.totalGames;
            }
            sync_cout << "WhiteWinRate: " << whiteRate << "%, "
                      << "BlackWinRate: " << blackRate << "%, "
                      << "DrawRate: " << drawRate << "%" << sync_endl;

            // 4) Optionally exit or continue. If you want "quit":
            // token = "quit";
        }
#endif // SELF_PLAY
        else if (token == "isready")
            sync_cout << "readyok" << sync_endl;
        else
            sync_cout << "Unknown command: " << cmd << sync_endl;
    } while (token != "quit" && argc == 1); // Command line args are one-shot

    // Before exiting this function (as searchEngine is about to be destructed),
    // ensure that all tasks in the thread pool have completed. This prevents
    // crashes that could occur if tasks are still running when searchEngine and
    // its internal mutexes are destroyed.
    Threads.stop_all();

    delete pos;
}

/// UCI::value() converts a Value to a string suitable for use with the UCI
/// protocol specification:
///
/// cp <x>    The score from the engine's point of view in pieces.
/// mate <y>  Mate in y moves, not plies. If the engine is getting mated
///           use negative values for y.

string UCI::value(Value v)
{
    assert(-VALUE_INFINITE < v && v < VALUE_INFINITE);

    stringstream ss;

    if (abs(v) < VALUE_MATE_IN_MAX_PLY)
        ss << "cp " << v / PieceValue;
    else
        ss << "mate " << (v > 0 ? VALUE_MATE - v + 1 : -VALUE_MATE - v) / 2;

    return ss.str();
}

/// UCI::square() converts a Square to a string in standard notation (e.g.,
/// "a1", "d5")

std::string UCI::square(Square s)
{
    static const char *squareToStandard[SQUARE_EXT_NB] = {
        // 0-7: unused
        "", "", "", "", "", "", "", "",
        // 8-15: inner ring
        "d5", "e5", "e4", "e3", "d3", "c3", "c4", "c5",
        // 16-23: middle ring
        "d6", "f6", "f4", "f2", "d2", "b2", "b4", "b6",
        // 24-31: outer ring
        "d7", "g7", "g4", "g1", "d1", "a1", "a4", "a7",
        // 32-39: unused
        "", "", "", "", "", "", "", ""};

    return squareToStandard[s];
}

/// UCI::move() converts a Move to a string in standard notation (a1-a4, etc.).

string UCI::move(Move m)
{
    if (m == MOVE_NONE)
        return "none";

    if (m == MOVE_NULL)
        return "0000";

    const Square to = to_sq(m);
    const string toStr = square(to);

    if (m < 0) {
        // Remove move
        return "x" + toStr;
    } else if (m & 0x7f00) {
        // Regular move
        const Square from = from_sq(m);
        const string fromStr = square(from);
        return fromStr + "-" + toStr;
    } else {
        // Place move
        return toStr;
    }
}

/// UCI::to_move() converts a string representing a move in coordinate notation
/// to the corresponding legal Move, if any.

Move UCI::to_move(Position *pos, const string &str)
{
    for (const auto &m : MoveList<LEGAL>(*pos))
        if (str == move(m))
            return m;

    return MOVE_NONE;
}
