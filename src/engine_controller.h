// engine_controller.h

#ifndef ENGINE_CONTROLLER_H_INCLUDED
#define ENGINE_CONTROLLER_H_INCLUDED

#include <string>

class Position;

/// EngineController is responsible for handling commands from UciServer (or
/// UCI::loop).
class EngineController
{
public:
    EngineController();
    ~EngineController();

    /// The main entry to handle a command.
    /// We pass in the raw command string and a Position pointer
    /// so we can call existing logic (like go(pos), position(pos, is)).
    void handleCommand(const std::string &cmd, Position *pos);

    /// Returns the singleton instance of EngineController
    static EngineController &getInstance();

private:
    // Singleton instance
    static EngineController instance;

    // If needed, we could store references to Options, or keep an internal
    // Position.
};

#endif // ENGINE_CONTROLLER_H_INCLUDED