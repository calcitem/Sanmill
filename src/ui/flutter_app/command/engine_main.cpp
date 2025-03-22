// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// engine_main.cpp

#include <iostream>
#include <stdarg.h>
#include <stdio.h>

#include "base.h"
#include "command_channel.h"

extern int eng_main(int argc, char *argv[]);

void println(const char *str, ...)
{
    va_list args;

    va_start(args, str);

    char buffer[4096] = {0};
    vsnprintf(buffer, sizeof(buffer), str, args);

    va_end(args);

    CommandChannel *channel = CommandChannel::getInstance();

    LOGD("println: %s\n", buffer);

    while (!channel->pushResponse(buffer)) {
        Idle();
    }
}

int engineMain(void)
{
    return eng_main(1, 0);
}
