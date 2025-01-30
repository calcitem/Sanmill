// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// command_queue.cpp

#include <cstring>

#include "config.h"
#include "base.h"
#include "command_queue.h"

CommandQueue::CommandQueue()
{
    for (int i = 0; i < MAX_COMMAND_COUNT; i++) {
        commands[i][0] = '\0';
    }

    writeIndex = 0;
    readIndex = -1;
}

bool CommandQueue::write(const char *command)
{
    std::unique_lock<std::mutex> lk(mutex);

    if (strlen(commands[writeIndex]) != 0) {
        return false;
    }

#ifdef _MSC_VER
    strncpy_s(commands[writeIndex], COMMAND_LENGTH, command, COMMAND_LENGTH);
#else
    strncpy(commands[writeIndex], command, COMMAND_LENGTH);
#endif

    if (readIndex == -1) {
        readIndex = writeIndex;
    }

    if (++writeIndex == MAX_COMMAND_COUNT) {
        writeIndex = 0;
    }

    return true;
}

bool CommandQueue::read(char *dest)
{
    std::unique_lock<std::mutex> lk(mutex);

    if (readIndex == -1) {
        return false;
    }

#ifdef _MSC_VER
    // See uci.cpp LINE_INPUT_MAX_CHAR
    strncpy_s(dest, 4096, (char const *)commands[readIndex], 4096);
    strncpy_s(commands[readIndex], 4096, "", COMMAND_LENGTH);
#else
    // See uci.cpp LINE_INPUT_MAX_CHAR
    strncpy(dest, commands[readIndex], 4096);
    strncpy(commands[readIndex], "", COMMAND_LENGTH);
#endif

    if (++readIndex == MAX_COMMAND_COUNT) {
        readIndex = 0;
    }

    if (readIndex == writeIndex) {
        readIndex = -1;
    }

    return true;
}
