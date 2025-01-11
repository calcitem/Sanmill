// uci.cpp

#include <iostream>
#include <sstream>
#include <vector>

#include "thread.h"
#include "thread_pool.h"
#include "uci.h"
#include "misc.h"
#include "search_engine.h"

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
                                             // EOF
            cmd = "quit";
#endif

        istringstream is(cmd);

        token.clear(); // Avoid a stale if getline() returns empty or blank line
        is >> skipws >> token;

        if (token == "quit" || token == "stop") {
            SearchEngine::getInstance().searchAborted.store(
                true, std::memory_order_relaxed);
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
                 token == "ucinewgame" || token == "d" || token == "compiler") {
            // Pass the entire command to EngineController
            EngineController().getInstance().handleCommand(cmd, pos);
        }

        else if (token == "isready")
            sync_cout << "readyok" << sync_endl;
        else
            sync_cout << "Unknown command: " << cmd << sync_endl;
    } while (token != "quit" && argc == 1); // Command line args are one-shot

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

/// UCI::square() converts a Square to a string in algebraic notation ((1,2),
/// etc.)

std::string UCI::square(Square s)
{
    return std::string {'(', static_cast<char>('0' + file_of(s)), ',',
                        static_cast<char>('0' + rank_of(s)), ')'};
}

/// UCI::move() converts a Move to a string in algebraic notation ((1,2), etc.).

string UCI::move(Move m)
{
    string move;

    const Square to = to_sq(m);

    if (m == MOVE_NONE)
        return "(none)";

    if (m == MOVE_NULL)
        return "0000";

    if (m < 0) {
        move = "-" + square(to);
    } else if (m & 0x7f00) {
        const Square from = from_sq(m);
        move = square(from) + "->" + square(to);
    } else {
        move = square(to);
    }

    return move;
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
