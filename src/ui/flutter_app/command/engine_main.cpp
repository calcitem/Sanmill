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

    char buffer[256] = {0};
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
