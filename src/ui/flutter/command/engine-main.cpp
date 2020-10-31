#include <stdio.h>
#include <stdarg.h>

#include "base.h"
#include "command-channel.h"

void println(const char *str, ...) {

    va_list args;

    va_start(args, str);

    char buffer[256] = {0};
    vsprintf(buffer, str, args);

    va_end(args);

    CommandChannel *channel = CommandChannel::getInstance();

    while (!channel->pushResponse(buffer))
      Idle();
}

int engineMain(void)
{
    println("bye");
    return 0;
}
