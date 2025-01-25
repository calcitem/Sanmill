// Malom, a Nine Men's Morris (and variants) player and solver program.
// Copyright(C) 2007-2016  Gabor E. Gevay, Gabor Danner
// Copyright (C) 2023-2025 The Sanmill developers (see AUTHORS file)
//
// See our webpage (and the paper linked from there):
// http://compalg.inf.elte.hu/~ggevay/mills/index.php
//
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

// pefect_move.cpp

#include "perfect_move.h"
#include "perfect_api.h"
#include "perfect_player.h"
#include "perfect_rules.h"

std::vector<int> SetPiece::get_fields()
{
    return {to};
}

std::string SetPiece::to_string()
{
    return mezoToString[to];
}

std::vector<int> MovePiece::get_fields()
{
    return {from, to};
}

std::string MovePiece::to_string()
{
    return mezoToString[from] + "-" + mezoToString[to];
}

std::vector<int> RemovePiece::get_fields()
{
    return {from};
}
std::string RemovePiece::to_string()
{
    return "x" + mezoToString[from];
}
