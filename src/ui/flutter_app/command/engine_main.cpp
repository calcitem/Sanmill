// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// engine_main.cpp

#include <iostream>
#include <stdarg.h>
#include <stdio.h>

#include "base.h"
#include "command_channel.h"

/// Stub for the legacy C++ engine entry-point that was defined in
/// src/main.cpp (removed in Phase 8.2).  The Flutter app now drives game
/// logic exclusively through the Rust/FRB NativeMillGameSession path;
/// this stub satisfies the linker while leaving the legacy MethodChannel
/// thread alive for backward-compatibility during the transition.
static int eng_main(int /*argc*/, char ** /*argv*/)
{
    return 0;
}

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
