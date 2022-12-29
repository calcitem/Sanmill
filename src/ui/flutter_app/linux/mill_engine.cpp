// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#include <iostream>
#include <stdio.h>
#include <string.h>
#include <string>
#include <thread>
#include <unistd.h>

#include "mill_engine.h"

#include "../command/command_channel.h"
#include "../command/engine_main.h"
#include "../command/engine_state.h"

// Mill Engine
MillEngine *engine = nullptr;

extern "C" {

EngineState state = EngineState::STATE_READY;
std::thread thread;

void engineThread()
{
    std::cout << "Engine Think Thread enter." << std::endl;

    engineMain();

    std::cout << "Engine Think Thread exit." << std::endl;
}

int MillEngine::startup()
{
    if (thread.joinable()) {
        shutdown();
        if (thread.joinable()) {
            thread.join();
        }
    }

    CommandChannel::getInstance();

    std::this_thread::sleep_for(std::chrono::milliseconds(10));

    thread = std::thread(engineThread);

    send("uci");

    return 0;
}

int MillEngine::send(const char *command)
{
    if (command[0] == 'g' && command[1] == 'o')
        state = EngineState::STATE_THINKING;

    CommandChannel *channel = CommandChannel::getInstance();

    bool success = channel->pushCommand(command);
    if (success) {
        std::cout << ">>> " << command << std::endl;
    }

    return success ? 0 : -1;
}

std::string MillEngine::read()
{
    char line[4096] = {0};

    CommandChannel *channel = CommandChannel::getInstance();
    bool got_response = channel->popupResponse(line);

    if (!got_response)
        return "";

    std::cout << "<<< " << line << std::endl;

    if (strstr(line, "readyok") || strstr(line, "uciok") ||
        strstr(line, "bestmove") || strstr(line, "nobestmove")) {
        state = EngineState::STATE_READY;
    }

    return line; // TODO
}

int MillEngine::shutdown()
{
    send("quit");

    if (thread.joinable()) {
        thread.join();
    }

    return 0;
}

bool MillEngine::isReady()
{
    return state == EngineState::STATE_READY;
}

bool MillEngine::isThinking()
{
    return state == EngineState::STATE_THINKING;
}
}
