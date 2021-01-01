/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

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

#ifndef SEARCH_H_INCLUDED
#define SEARCH_H_INCLUDED

#include <vector>

#include "stack.h"
#include "tt.h"
#include "endgame.h"
#include "movepick.h"
#include "types.h"

#ifdef CYCLE_STAT
#include "stopwatch.h"
#endif

using namespace std;

namespace Search
{

void init();
void clear();

} // namespace Search


#include "tt.h"

#ifdef THREEFOLD_REPETITION
extern vector<Key> posKeyHistory;
#endif

#endif // #ifndef SEARCH_H_INCLUDED
