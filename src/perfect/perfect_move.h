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

// pefect_move.h

#ifndef PERFECT_MOVE_H_INCLUDED
#define PERFECT_MOVE_H_INCLUDED

#include "perfect_player.h"
#include "perfect_rules.h"

class CMove
{
public:
    virtual std::vector<int> get_fields() = 0; // Returns the fields included in
                                               // the step
    virtual ~CMove() = default;

protected:
    std::string mezoToString[24] = {"a4", "a7", "d7", "g7", "g4", "g1",
                                    "d1", "a1", "b4", "b6", "d6", "f6",
                                    "f4", "f2", "d2", "b2", "c4", "c5",
                                    "d5", "e5", "e4", "e3", "d3", "c3"};
};

class SetPiece : public CMove
{
public:
    int to;
    SetPiece(int m)
        : to(m)
    { }
    std::vector<int> get_fields() override;
    std::string to_string();
};

class MovePiece : public CMove
{
public:
    int from, to;
    MovePiece(int m1, int m2)
        : from(m1)
        , to(m2)
    { }
    std::vector<int> get_fields() override;
    std::string to_string();
};

class RemovePiece : public CMove
{
public:
    int from;
    RemovePiece(int m)
        : from(m)
    { }
    std::vector<int> get_fields() override;
    std::string to_string();
};

#endif // PERFECT_MOVE_H_INCLUDED
