// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
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
