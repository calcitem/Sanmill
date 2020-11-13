/*
  Fishmill, a UCI Mill Game playing engine derived from Stockfish
  Copyright (C) 2004-2008 Tord Romstad (Glaurung author)
  Copyright (C) 2008-2015 Marco Costalba, Joona Kiiski, Tord Romstad (Stockfish author)
  Copyright (C) 2015-2020 Marco Costalba, Joona Kiiski, Gary Linscott, Tord Romstad (Stockfish author)
  Copyright (C) 2020 Calcitem <calcitem@outlook.com>

  Fishmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Fishmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <cassert>
#include <iostream>
#include <sstream>
#include <string>

#include "evaluate.h"
#include "movegen.h"
#include "position.h"
#include "search.h"
#include "thread.h"
#include "tt.h"
#include "uci.h"

#ifdef FLUTTER_UI
#include "command_channel.h"
#include "base.h"
#endif

using namespace std;

extern vector<string> setup_bench(Position *, istream &);

namespace
{

// FEN string of the initial position, normal mill game
const char *StartFEN = "********/********/******** b p p 0 12 0 12 0 0 1";


// position() is called when engine receives the "position" UCI command.
// The function sets up the position described in the given FEN string ("fen")
// or the starting position ("startpos") and then makes the moves given in the
// following move list ("moves").

void position(Position *pos, istringstream &is)
{
    Move m;
    string token, fen;

    is >> token;

    if (token == "startpos") {
        fen = StartFEN;
        is >> token; // Consume "moves" token if any
    } else if (token == "fen")
        while (is >> token && token != "moves")
            fen += token + " ";
    else
        return;

    pos->set(fen, Threads.main());

    // Parse move list (if any)
    while (is >> token && (m = UCI::to_move(pos, token)) != MOVE_NONE) {
        pos->do_move(m);
    }
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


// go() is called when engine receives the "go" UCI command. The function sets
// the thinking time and other parameters from the input string, then starts
// the search.

void go(Position *pos)
{
#ifdef UCI_AUTO_RE_GO
    begin:
#endif
    Threads.start_thinking(pos);

    if (pos->get_phase() == PHASE_GAMEOVER)
    {
#ifdef UCI_AUTO_RESTART
        // TODO
        while (true) {
            if (Threads.main()->searching == true) {
                continue;
            }

            pos->set(StartFEN, Threads.main());
            Threads.main()->us = BLACK; // WAR
            break;
        }
#else
        return;
#endif
    }

#ifdef UCI_AUTO_RE_GO
    goto begin;
#endif
}


// bench() is called when engine receives the "bench" command. Firstly
// a list of UCI commands is setup according to bench parameters, then
// it is run one by one printing a summary at the end.

void bench(Position *pos, istream &args)
{
    string token;
    uint64_t num, cnt = 1;

    vector<string> list = setup_bench(pos, args);
    num = count_if(list.begin(), list.end(), [](string s) { return s.find("go ") == 0 || s.find("eval") == 0; });

    TimePoint elapsed = now();

    for (const auto &cmd : list) {
        istringstream is(cmd);
        is >> skipws >> token;

        if (token == "go" || token == "eval") {
            cerr << "\nPosition: " << cnt++ << '/' << num << endl;
            if (token == "go") {
                go(pos);
                Threads.main()->wait_for_search_finished();
            } else
                sync_cout << "\n" << Eval::trace(*pos) << sync_endl;
        } else if (token == "setoption")  setoption(is);
        else if (token == "position")   position(pos, is);
        else if (token == "ucinewgame") {
            Search::clear(); elapsed = now();
        } // Search::clear() may take some while
    }

    elapsed = now() - elapsed + 1; // Ensure positivity to avoid a 'divide by zero'

    dbg_print(); // Just before exiting

    cerr << "\n==========================="
        << "\nTotal time (ms) : " << elapsed
        << endl;
}

} // namespace


/// UCI::loop() waits for a command from stdin, parses it and calls the appropriate
/// function. Also intercepts EOF from stdin to ensure gracefully exiting if the
/// GUI dies unexpectedly. When called with some command line arguments, e.g. to
/// run 'bench', once the command is executed the function returns immediately.
/// In addition to the UCI ones, also some additional debug commands are supported.

void UCI::loop(int argc, char *argv[])
{
    Position *pos = new Position;
    string token, cmd;

    pos->set(StartFEN, Threads.main());

    for (int i = 1; i < argc; ++i)
        cmd += std::string(argv[i]) + " ";

    do {
#ifdef FLUTTER_UI
        static const int LINE_INPUT_MAX_CHAR = 256;
        char szLineStr[LINE_INPUT_MAX_CHAR];
        CommandChannel *channel = CommandChannel::getInstance();
        while (!channel->popupCommand(szLineStr)) Idle();
        cmd = szLineStr;
        LOGD("szLine = %s\n", szLineStr);
#else
        if (argc == 1 && !getline(cin, cmd)) // Block here waiting for input or EOF
            cmd = "quit";
#endif

        istringstream is(cmd);

        token.clear(); // Avoid a stale if getline() returns empty or blank line
        is >> skipws >> token;

        if (token == "quit"
            || token == "stop")
            Threads.stop = true;

        // The GUI sends 'ponderhit' to tell us the user has played the expected move.
        // So 'ponderhit' will be sent if we were told to ponder on the same move the
        // user has played. We should continue searching but switch from pondering to
        // normal search.
        else if (token == "ponderhit")
            Threads.main()->ponder = false; // Switch to normal search

        else if (token == "uci")
            sync_cout << "id name " << engine_info(true)
            << "\n" << Options
            << "\nuciok" << sync_endl;

        else if (token == "setoption")  setoption(is);
        else if (token == "go")         go(pos);
        else if (token == "position")   position(pos, is);
        else if (token == "ucinewgame") Search::clear();
        else if (token == "isready")    sync_cout << "readyok" << sync_endl;

        // Additional custom non-UCI commands, mainly for debugging.
        // Do not use these commands during a search!
        else if (token == "flip")     pos->flip();
        else if (token == "bench")    bench(pos, is);
        else if (token == "d")        sync_cout << *pos << sync_endl;
        else if (token == "eval")     sync_cout << Eval::trace(*pos) << sync_endl;
        else if (token == "compiler") sync_cout << compiler_info() << sync_endl;
        else
            sync_cout << "Unknown command: " << cmd << sync_endl;

    } while (token != "quit" && argc == 1); // Command line args are one-shot

    delete pos;
}


/// UCI::value() converts a Value to a string suitable for use with the UCI
/// protocol specification:
///
/// cp <x>    The score from the engine's point of view in stones.
/// mate <y>  Mate in y moves, not plies. If the engine is getting mated
///           use negative values for y.

string UCI::value(Value v)
{
    assert(-VALUE_INFINITE < v &&v < VALUE_INFINITE);

    stringstream ss;

    if (abs(v) < VALUE_MATE_IN_MAX_PLY)
        ss << "cp " << v / StoneValue;
    else
        ss << "mate " << (v > 0 ? VALUE_MATE - v + 1 : -VALUE_MATE - v) / 2;

    return ss.str();
}


/// UCI::square() converts a Square to a string in algebraic notation ((1,2), etc.)

std::string UCI::square(Square s)
{
    return std::string{ char('('), char('0' + file_of(s)), char(','), char('0' + rank_of(s)), char(')') };
}


/// UCI::move() converts a Move to a string in coordinate notation (g1f3, a7a8q).
/// The only special case is castling, where we print in the e1g1 notation in
/// normal chess mode, and in e1h1 notation in chess960 mode. Internally all
/// castling moves are always encoded as 'king captures rook'.

string UCI::move(Move m)
{
    string move;

    Square to = to_sq(m);

    if (m == MOVE_NONE)
        return "(none)";

    if (m == MOVE_NULL)
        return "0000";

    if (m < 0) {
        move = "-" + UCI::square(to);
    } else if (m & 0x7f00) {
        Square from = from_sq(m);
        move = UCI::square(from) + "->" + UCI::square(to);
    } else {
        move = UCI::square(to);
    }

    return move;
}


/// UCI::to_move() converts a string representing a move in coordinate notation
/// (g1f3, a7a8q) to the corresponding legal Move, if any.

Move UCI::to_move(Position *pos, string &str)
{
    if (str.length() == 5) // Junior could send promotion piece in uppercase
        str[4] = char(tolower(str[4]));

    for (const auto &m : MoveList<LEGAL>(*pos))
        if (str == UCI::move(m))
            return m;

    return MOVE_NONE;
}
