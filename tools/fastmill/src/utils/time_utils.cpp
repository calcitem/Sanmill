// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// time_utils.cpp - Implementation of time utilities

#include "time_utils.h"
#include <iomanip>
#include <sstream>
#include <ctime>

namespace fastmill {

std::string TimeUtils::getCurrentTimestamp()
{
    auto now = std::chrono::system_clock::now();
    auto time_t = std::chrono::system_clock::to_time_t(now);

    std::stringstream ss;
    ss << std::put_time(std::localtime(&time_t), "%Y-%m-%d %H:%M:%S");
    return ss.str();
}

std::string TimeUtils::formatDuration(std::chrono::milliseconds duration)
{
    auto total_seconds =
        std::chrono::duration_cast<std::chrono::seconds>(duration).count();

    int hours = static_cast<int>(total_seconds / 3600);
    int minutes = static_cast<int>((total_seconds % 3600) / 60);
    int seconds = static_cast<int>(total_seconds % 60);

    std::stringstream ss;
    if (hours > 0) {
        ss << hours << "h " << minutes << "m " << seconds << "s";
    } else if (minutes > 0) {
        ss << minutes << "m " << seconds << "s";
    } else {
        ss << seconds << "s";
    }

    return ss.str();
}

std::chrono::milliseconds TimeUtils::secondsToMs(double seconds)
{
    return std::chrono::milliseconds(static_cast<long long>(seconds * 1000));
}

double TimeUtils::msToSeconds(std::chrono::milliseconds ms)
{
    return ms.count() / 1000.0;
}

} // namespace fastmill
