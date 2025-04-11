// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_move.h

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
