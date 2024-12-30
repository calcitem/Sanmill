// engine_controller.cpp

#include "engine_controller.h"

#include <sstream>
#include <string>

#include "uci.h"
#include "thread.h"
#include "search.h"
#include "misc.h"
#include "engine_commands.h" // Include for EngineCommands

// Initialize the singleton instance
EngineController EngineController::instance;

EngineController::EngineController()
{
    // Constructor
}

EngineController::~EngineController()
{
    // Destructor
}

EngineController &EngineController::getInstance()
{
    return instance;
}

void EngineController::handleCommand(const std::string &cmd, Position *pos)
{
    std::istringstream is(cmd);
    std::string token;
    is >> token;

    if (token == "go") {
        EngineCommands::go(pos); // Call the EngineCommands::go function
    } else if (token == "position") {
        EngineCommands::position(pos, is); // Call the EngineCommands::position
                                           // function
    } else if (token == "ucinewgame") {
        Search::clear(); // Clear the search state for a new game
        // Additional custom non-UCI commands, mainly for debugging.
        // Do not use these commands during a search!
    } else if (token == "d") {
        // Output the current position state
        sync_cout << *pos << sync_endl;
    } else if (token == "compiler") {
        // Output compiler information
        sync_cout << compiler_info() << sync_endl;
    } else {
        // Handle additional custom commands if necessary
        // For example:
        // else if (token == "customcommand") { ... }
        // Currently, unknown commands are handled in UCI::loop, so you might
        // not need to do anything here.
        sync_cout << "Unknown command in EngineController: " << cmd
                  << sync_endl;
    }
}
