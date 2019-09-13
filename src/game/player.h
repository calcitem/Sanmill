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

#ifndef PLAYER_H
#define PLAYER_H

#include "config.h"
#include "types.h"

class Player
{
public:
    explicit Player();
    virtual ~Player();

    const player_t getPlayer() const
    {
        return who;
    }

    int getId() const
    {
        return id;
    }

    inline static int toId(player_t who)
    {
        return int((int)who >> PLAYER_SHIFT);
    }

private:
    player_t who;
    int id;
};

#endif // PLAYER_H
