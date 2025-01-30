// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// mill_engine.h

#include <string>

class MillEngine
{
public:
    int startup();

    int send(const char *arguments);

    std::string read();

    int shutdown();

    bool isReady();

    bool isThinking();
};
