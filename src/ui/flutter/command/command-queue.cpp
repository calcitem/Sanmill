//
//  command-queue.cpp
//  Runner
//

#include <string.h>
#include "command-queue.h"

CommandQueue::CommandQueue()
{
    for (int i = 0; i < MAX_COMMAND_COUNT; i++) {
        strcpy(commands[i], "");
    }

    writeIndex = 0;
    readIndex = -1;
}

bool CommandQueue::write(const char *command)
{
    if (strlen(commands[writeIndex]) != 0) {
        return false;
    }

    strcpy(commands[writeIndex], command);

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
    if (readIndex == -1) {
        return false;
    }

    strcpy(dest, commands[readIndex]);
    strcpy(commands[readIndex], "");

    if (++readIndex == MAX_COMMAND_COUNT) {
        readIndex = 0;
    }

    if (readIndex == writeIndex) {
        readIndex = -1;
    }

    return true;
}
