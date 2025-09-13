// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// time_utils.h - Time utility functions for Fastmill

#pragma once

#include <chrono>
#include <string>

namespace fastmill {

class TimeUtils
{
public:
    // Get current timestamp as string
    static std::string getCurrentTimestamp();

    // Format duration as human readable string
    static std::string formatDuration(std::chrono::milliseconds duration);

    // Convert seconds to milliseconds
    static std::chrono::milliseconds secondsToMs(double seconds);

    // Convert milliseconds to seconds
    static double msToSeconds(std::chrono::milliseconds ms);
};

} // namespace fastmill
