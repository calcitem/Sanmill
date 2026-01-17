// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// command_queue.h

#ifndef COMMAND_QUEUE_H
#define COMMAND_QUEUE_H

#include <mutex>

class CommandQueue
{
    enum {
        MAX_COMMAND_COUNT = 128,
        COMMAND_LENGTH = 4096,
    };

    char commands[MAX_COMMAND_COUNT][COMMAND_LENGTH];
    int readIndex, writeIndex;

    std::mutex mutex;
    bool dropOldestOnFull;
    unsigned long droppedCount;

public:
    explicit CommandQueue(bool dropOldestOnFull = false);

    bool write(const char *command);
    bool read(char *dest);
    void clear();
    unsigned long getDroppedCount() const;
};

#endif /* COMMAND_QUEUE_H */
