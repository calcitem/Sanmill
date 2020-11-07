//
//  command-queue.h
//  Runner
//

#ifndef COMMAND_QUEUE_H
#define COMMAND_QUEUE_H

class CommandQueue
{
    enum
    {
        MAX_COMMAND_COUNT = 128,
        COMMAND_LENGTH = 2048,
    };

    char commands[MAX_COMMAND_COUNT][COMMAND_LENGTH];
    int readIndex, writeIndex;

public:
    CommandQueue();

    bool write(const char *command);
    bool read(char *dest);
};

#endif /* COMMAND_QUEUE_H */
