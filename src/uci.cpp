// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

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

#if defined(ENABLE_BENCHMARK)
#include "benchmark.h"
#endif // ENABLE_BENCHMARK

#ifdef FLUTTER_UI
#include "base.h"
#include "command_channel.h"
#include "engine_main.h"
#endif

#include "engine_controller.h"
#include "engine_commands.h"

// #region debug commands (engine-parity instrumentation, off the hot path)
// These extra UCI verbs (valuevec / gomtdf / goab / mobdiff / evaldecomp) are
// only used when manually diagnosing search/eval divergences against another
// engine.  They never run during a normal game, so they add no overhead to the
// standard position/go/bestmove path used by the head-to-head harness.
#include "evaluate.h"
#include "position.h"
#include "search.h"
#include "movegen.h"
#include "tt.h"
#include <algorithm>
#include <cstdio>
#include <cstdlib>
// #endregion

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
#if defined(ENABLE_BENCHMARK)
        } else if (token == "benchmark" || token == "bench") {
            Benchmark::run_from_cli(is);
#endif // ENABLE_BENCHMARK
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
        // #region debug commands (engine-parity instrumentation)
        // `valuevec [childDepth] [move...]` searches every (optionally
        // filtered) legal root move at a fixed child depth and reports each
        // move's value from White's point of view.  When the environment
        // variable SANMILL_DEBUG_LOG is set, the per-move values are also
        // appended there as NDJSON so they can be diffed against another
        // engine; otherwise the values are printed to stdout only.  The
        // session/hypothesis tags come from SANMILL_DEBUG_SESSION /
        // SANMILL_DEBUG_HYPOTHESIS (defaulting to "debug"/"master").
        else if (token == "valuevec") {
            int childDepth = 7;
            string dtok;
            if (is >> dtok) {
                try {
                    childDepth = std::stoi(dtok);
                } catch (...) {
                }
            }
            std::vector<std::string> filter;
            {
                string ftok;
                while (is >> ftok)
                    filter.push_back(ftok);
            }
            const char *logPath = std::getenv("SANMILL_DEBUG_LOG");
            const char *sessEnv = std::getenv("SANMILL_DEBUG_SESSION");
            const char *hypEnv = std::getenv("SANMILL_DEBUG_HYPOTHESIS");
            const std::string session = sessEnv ? sessEnv : "debug";
            const std::string hypothesis = hypEnv ? hypEnv : "master";
            const std::string savedFen = pos->fen();
            FILE *flog = logPath ? std::fopen(logPath, "a") : nullptr;
            searchEngine.beginNewSearch(pos);
            Sanmill::Stack<Position> ssv;
            for (const auto &mm : MoveList<LEGAL>(*pos)) {
                const std::string mv = UCI::move(mm);
                if (!filter.empty() &&
                    std::find(filter.begin(), filter.end(), mv) ==
                        filter.end())
                    continue;
#ifdef TRANSPOSITION_TABLE_ENABLE
                TT.clear();
#endif
                pos->set(savedFen);
                const Color before = pos->side_to_move();
                pos->do_move(mm);
                const Color after = pos->side_to_move();
                Move bm = MOVE_NONE;
                const Value cv = Search::search(searchEngine, pos, ssv,
                                                childDepth, childDepth,
                                                -VALUE_INFINITE, VALUE_INFINITE,
                                                bm);
                const Value wv = (after != before) ? static_cast<Value>(-cv) :
                                                     cv;
                sync_cout << "valuevec " << mv << " depth=" << childDepth
                          << " white_value=" << static_cast<int>(wv)
                          << sync_endl;
                if (flog)
                    std::fprintf(flog,
                                 "{\"sessionId\":\"%s\",\"hypothesisId\":\"%s\","
                                 "\"location\":\"uci.cpp:valuevec\",\"message\":"
                                 "\"root_value\",\"data\":{\"uci\":\"%s\","
                                 "\"child_depth\":%d,\"white_value\":%d},"
                                 "\"timestamp\":0}\n",
                                 session.c_str(), hypothesis.c_str(),
                                 mv.c_str(), childDepth, static_cast<int>(wv));
            }
            pos->set(savedFen);
            if (flog)
                std::fclose(flog);
            sync_cout << "valuevec done depth=" << childDepth << sync_endl;
        }
        // `gomtdf [depth]` runs an explicit MTD(f) loop at a fixed depth,
        // mirroring the engine's per-move fake-clean TT handling, and logs
        // every (beta, g, bestmove) iteration so the convergence sequence can
        // be compared move-for-move with another engine.
        else if (token == "gomtdf") {
            int d = 15;
            string dtok;
            if (is >> dtok) {
                try {
                    d = std::stoi(dtok);
                } catch (...) {
                }
            }
            searchEngine.beginNewSearch(pos);
#ifdef TRANSPOSITION_TABLE_ENABLE
            TranspositionTable::clear();
#endif
            Sanmill::Stack<Position> ssg;
            Move bm = MOVE_NONE;
            Value g = VALUE_ZERO;
            Value lower = -VALUE_INFINITE;
            Value upper = VALUE_INFINITE;
            int it = 0;
            while (lower < upper) {
                const Value beta = (g == lower) ? static_cast<Value>(g + 1) : g;
                g = Search::search(searchEngine, pos, ssg, d, d,
                                   static_cast<Value>(beta - 1), beta, bm);
                sync_cout << "  mtdf-iter " << it++ << " beta="
                          << static_cast<int>(beta)
                          << " g=" << static_cast<int>(g)
                          << " best=" << UCI::move(bm) << sync_endl;
                if (g < beta) {
                    upper = g;
                } else {
                    lower = g;
                }
            }
            sync_cout << "gomtdf depth=" << d << " value="
                      << static_cast<int>(g) << " bestmove " << UCI::move(bm)
                      << sync_endl;
        }
        // `goab [depth]` runs a single plain alpha-beta search at a fixed
        // depth with a full window and a freshly cleared TT.
        else if (token == "goab") {
            int d = 15;
            string dtok;
            if (is >> dtok) {
                try {
                    d = std::stoi(dtok);
                } catch (...) {
                }
            }
            searchEngine.beginNewSearch(pos);
#ifdef TRANSPOSITION_TABLE_ENABLE
            TranspositionTable::clear();
#endif
            Sanmill::Stack<Position> ssab;
            Move bm = MOVE_NONE;
            const Value v = Search::search(searchEngine, pos, ssab, d, d,
                                           -VALUE_INFINITE, VALUE_INFINITE, bm);
            sync_cout << "goab depth=" << d << " value=" << static_cast<int>(v)
                      << " bestmove " << UCI::move(bm) << sync_endl;
        }
        // `mobdiff` compares the incrementally tracked mobility difference with
        // a full recalculation, to catch incremental-update drift.
        else if (token == "mobdiff") {
            const int incremental = pos->get_mobility_diff();
            const int recalc = pos->calculate_mobility_diff();
            sync_cout << "mobdiff incremental=" << incremental
                      << " recalc=" << recalc << sync_endl;
        }
        // `evaldecomp` prints the individual evaluation terms for the current
        // position so eval discrepancies can be localised.
        else if (token == "evaldecomp") {
            sync_cout << "evaldecomp phase="
                      << static_cast<int>(pos->get_phase())
                      << " mob=" << pos->get_mobility_diff()
                      << " onbW=" << pos->piece_on_board_count(WHITE)
                      << " onbB=" << pos->piece_on_board_count(BLACK)
                      << " inhW=" << pos->piece_in_hand_count(WHITE)
                      << " inhB=" << pos->piece_in_hand_count(BLACK)
                      << " rmW=" << pos->piece_to_remove_count(WHITE)
                      << " rmB=" << pos->piece_to_remove_count(BLACK)
                      << " stm=" << static_cast<int>(pos->side_to_move())
                      << " eval=" << static_cast<int>(Eval::evaluate(*pos))
                      << sync_endl;
        }
        // #endregion
        else if (token == "isready") {
            sync_cout << "readyok" << sync_endl;
#ifdef FLUTTER_UI
            println("readyok");
#endif
        } else
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
