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

#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <string>
#include <unistd.h>

#include "mill_engine.h"

#include "../command/command_channel.h"
#include "../command/engine_main.h"
#include "../command/engine_state.h"

// Mill Engine
MillEngine *engine = nullptr;

extern "C" {

EngineState state = EngineState::STATE_READY;
pthread_t thread_id = 0;

void *engineThread(void *arg)
{
    printf("Engine Think Thread enter.\n");

    engineMain();

    printf("Engine Think Thread exit.\n");

    return 0;
}

int MillEngine::startup()
{
    if (thread_id) {
        shutdown();
        pthread_join(thread_id, NULL);
    }

    CommandChannel::getInstance();

    usleep(10);

    pthread_create(&thread_id, NULL, &engineThread, NULL);

    send("uci");

    return 0;
}

int MillEngine::send(const char *command)
{
    if (command[0] == 'g' && command[1] == 'o')
        state = EngineState::STATE_THINKING;

    CommandChannel *channel = CommandChannel::getInstance();

    bool success = channel->pushCommand(command);
    if (success)
        printf(">>> %s\n", command);

    return success ? 0 : -1;
}

std::string MillEngine::read()
{
    char line[4096] = {0};

    CommandChannel *channel = CommandChannel::getInstance();
    bool got_response = channel->popupResponse(line);

    if (!got_response)
        return "";

    printf("<<< %s\n", line);

    if (strstr(line, "readyok") || strstr(line, "uciok") ||
        strstr(line, "bestmove") || strstr(line, "nobestmove")) {
        state = EngineState::STATE_READY;
    }

    return line; // TODO
}

int MillEngine::shutdown()
{
    send("quit");

    pthread_join(thread_id, NULL);

    thread_id = 0;

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
