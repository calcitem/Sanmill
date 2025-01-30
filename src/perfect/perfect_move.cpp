// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_move.cpp

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
