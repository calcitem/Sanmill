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

#ifndef COMMAND_CHANNEL_H
#define COMMAND_CHANNEL_H

class CommandQueue;

class CommandChannel
{
    CommandChannel();

public:
    static CommandChannel *getInstance();
    static void release();

    virtual ~CommandChannel();

    bool pushCommand(const char *cmd);
    bool popupCommand(char *buffer);
    bool pushResponse(const char *resp);
    bool popupResponse(char *buffer);

private:
    static CommandChannel *instance;

    CommandQueue *commandQueue;
    CommandQueue *responseQueue;
};

#endif /* COMMAND_CHANNEL_H */
