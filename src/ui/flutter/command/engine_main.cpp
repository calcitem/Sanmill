/*
  FlutterMill, a mill game playing frontend derived from ChessRoad
  Copyright (C) 2019 He Zhaoyun (ChessRoad author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

  FlutterMill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  FlutterMill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <stdio.h>
#include <stdarg.h>

#include "base.h"
#include "command_channel.h"

void println(const char *str, ...) {

    va_list args;

    va_start(args, str);

    char buffer[256] = {0};
    vsprintf(buffer, str, args);

    va_end(args);

    CommandChannel *channel = CommandChannel::getInstance();

    while (!channel->pushResponse(buffer)) {
        Idle();
    }
}

int engineMain(void)
{
    println("bye");
    return 0;
}
