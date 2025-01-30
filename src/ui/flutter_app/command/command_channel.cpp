// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// command_channel.cpp

#include <stdlib.h>

#include "command_channel.h"
#include "command_queue.h"

CommandChannel *CommandChannel::instance = nullptr;

CommandChannel::CommandChannel()
{
    commandQueue = new CommandQueue();
    responseQueue = new CommandQueue();
}

CommandChannel *CommandChannel::getInstance()
{
    if (instance == nullptr) {
        instance = new CommandChannel();
    }

    return instance;
}

void CommandChannel::release()
{
    if (instance != nullptr) {
        delete instance;
        instance = nullptr;
    }
}

CommandChannel::~CommandChannel()
{
    if (commandQueue != nullptr) {
        delete commandQueue;
        commandQueue = nullptr;
    }

    if (responseQueue != nullptr) {
        delete responseQueue;
        responseQueue = nullptr;
    }
}

bool CommandChannel::pushCommand(const char *cmd)
{
    return commandQueue->write(cmd);
}

bool CommandChannel::popupCommand(char *buffer)
{
    return commandQueue->read(buffer);
}

bool CommandChannel::pushResponse(const char *resp)
{
    return responseQueue->write(resp);
}

bool CommandChannel::popupResponse(char *buffer)
{
    return responseQueue->read(buffer);
}
