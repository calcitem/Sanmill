// engine_commands.h

#ifndef ENGINE_COMMANDS_H_INCLUDED
#define ENGINE_COMMANDS_H_INCLUDED

#include <string>
#include <sstream>

class Position;
class SearchEngine;

namespace EngineCommands {

/// Handles the "go" UCI command to start the search.
void go(SearchEngine &searchEngine, Position *pos);

/// Handles the "position" UCI command to set up the board position.
void position(Position *pos, std::istringstream &is);

/// Initializes the starting FEN based on piece count.
void init_start_fen();

/// The starting FEN string after initialization.
extern char StartFEN[BUFSIZ];

} // namespace EngineCommands

#endif // ENGINE_COMMANDS_H_INCLUDED
