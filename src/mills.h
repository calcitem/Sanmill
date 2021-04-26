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

#ifndef MILL_H_INCLUDED
#define MILL_H_INCLUDED

#include "types.h"
#include "config.h"

extern const char *loseReasonNoWayStr;
extern const char *loseReasonTimeOverStr;
extern const char *drawReasonThreefoldRepetitionStr;
extern const char *drawReasonRule50Str;
extern const char *loseReasonBoardIsFullStr;
extern const char *drawReasonBoardIsFullStr;
extern const char *loseReasonlessThanThreeStr;
extern const char *loseReasonResignStr;

namespace Mills
{

void adjacent_squares_init() noexcept;
void mill_table_init();
void move_priority_list_shuffle();
Depth get_search_depth(const Position *pos);

}

#endif // #ifndef MILL_H_INCLUDED
