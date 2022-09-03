// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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

#ifndef STOPWATCH_H_INCLUDED
#define STOPWATCH_H_INCLUDED

#include <algorithm>
#include <array>
#include <cstdint>
#ifdef _WIN32
#include <intrin.h>
#endif

namespace stopwatch {
// An implementation of the 'TrivialClock' concept using the rdtscp instruction.
struct rdtscp_clock
{
    using rep = std::uint64_t;
    using period = std::ratio<1>;
    using duration = std::chrono::duration<rep, period>;
    using time_point = std::chrono::time_point<rdtscp_clock, duration>;

    static time_point now() noexcept
    {
#if defined(__x86_64__) || defined(__amd64__)
#ifdef _WIN32
        unsigned int ui;
        return time_point(
            duration((static_cast<std::uint64_t>(__rdtscp(&ui)))));
#else
        std::uint32_t hi, lo;
        __asm__ __volatile__("rdtscp" : "=d"(hi), "=a"(lo));
        return time_point(
            duration((static_cast<std::uint64_t>(hi) << 32) | lo));
#endif // WIN32

#else
        constexpr unsigned int ui = 0;
        return time_point(duration(static_cast<std::uint64_t>(ui)));
#endif
    }
};

// A timer using the specified clock.
template <class Clock = std::chrono::system_clock>
struct timer
{
    using time_point = typename Clock::time_point;
    using duration = typename Clock::duration;

    explicit timer(const duration duration) noexcept
        : expiry(Clock::now() + duration)
    { }

    explicit timer(const time_point expiry) noexcept
        : expiry(expiry)
    { }

    bool done(time_point now = Clock::now()) const noexcept
    {
        return now >= expiry;
    }

    duration remaining(time_point now = Clock::now()) const noexcept
    {
        return expiry - now;
    }

    const time_point expiry;
};

template <class Clock = std::chrono::system_clock>
constexpr timer<Clock> make_timer(typename Clock::duration duration)
{
    return timer<Clock>(duration);
}

// Times how long it takes a function to execute using the specified clock.
template <class Clock = rdtscp_clock, class Func>
typename Clock::duration time(Func &&function)
{
    const auto start = Clock::now();
    function();
    return Clock::now() - start;
}

// Samples the given function N times using the specified clock.
template <std::size_t N, class Clock = rdtscp_clock, class Func>
std::array<typename Clock::duration, N> sample(Func &&function)
{
    std::array<typename Clock::duration, N> samples;

    for (std::size_t i = 0u; i < N; ++i) {
        samples[i] = time<Clock>(function);
    }

    std::sort(samples.begin(), samples.end());
    return samples;
}
} /* namespace stopwatch */

#endif // STOPWATCH_H_INCLUDED
