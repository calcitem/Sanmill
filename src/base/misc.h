/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2015-2018 liuweilhy (NineChess author)
  Copyright (C) 2019 Calcitem <calcitem@outlook.com>

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef MISC_H
#define MISC_H

#include <cstdlib>
#include <chrono>

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
