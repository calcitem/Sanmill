/*****************************************************************************
 * Copyright (C) 2018-2019 MillGame authors
 *
 * Authors: liuweilhy <liuweilhy@163.com>
 *          Calcitem <calcitem@outlook.com>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifndef MISC_H
#define MISC_H

using TimePoint = std::chrono::milliseconds::rep; // A value in milliseconds

static_assert(sizeof(TimePoint) == sizeof(int64_t), "TimePoint should be 64 bits");

inline TimePoint now()
{
    return std::chrono::duration_cast<std::chrono::milliseconds>
        (std::chrono::steady_clock::now().time_since_epoch()).count();
}

inline uint64_t rand64()
{
    return static_cast<uint64_t>(rand()) ^
        (static_cast<uint64_t>(rand()) << 15) ^
        (static_cast<uint64_t>(rand()) << 30) ^
        (static_cast<uint64_t>(rand()) << 45) ^
        (static_cast<uint64_t>(rand()) << 60);
}

inline uint64_t rand56()
{
    return rand64() << 8;
}

#endif /* MISC_H */
