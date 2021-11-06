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

#ifndef GRAPHICSCONST
#define GRAPHICSCONST

#include "config.h"

#ifdef QT_MOBILE_APP_UI
constexpr short BOARD_SIZE = 500;
#else
constexpr short BOARD_SIZE = 550;
#endif /* QT_MOBILE_APP_UI */

constexpr short BOARD_MINISIZE = 150; // Minimum width and height, i.e. 1 / 4 Size
constexpr short PIECE_SIZE = 56;
constexpr short LINE_INTERVAL = 72;
constexpr short LINE_WEIGHT = 3;

#endif // GRAPHICSCONST
