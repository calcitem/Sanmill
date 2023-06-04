// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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

#ifndef PERFECT_H_INCLUDED
#define PERFECT_H_INCLUDED

#include "position.h"
#include "types.h"

// Perfect AI
int perfect_init();
int perfect_exit();
int perfect_reset();
Square from_perfect_sq(uint32_t sq);
unsigned to_perfect_sq(Square sq);

Move perfect_search(Position *pos);

#endif // PERFECT_H_INCLUDED
