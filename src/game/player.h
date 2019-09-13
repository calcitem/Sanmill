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

#include <string>

#include "config.h"
#include "types.h"

class Player
{
public:
    explicit Player();
    virtual ~Player();

    player_t getPlayer() const
    {
        return who;
    }

    int getId() const
    {
        return id;
    }

    inline static int toId(player_t who)
    {
        return int(static_cast<int>(who) >> PLAYER_SHIFT);
    }

    inline static player_t idToPlayer(int id)
    {
        return player_t(id << PLAYER_SHIFT);
    }

    inline static char idToCh(int id)
    {
        return static_cast<char>('0' + id);
    }

    inline static std::string chToStr(char ch)
    {
        if (ch == '1') {
            return "1";
        } else {
            return "2";
        }
    }

    inline static player_t getOpponent(player_t player)
    {
        return player == PLAYER_1 ? PLAYER_2 : PLAYER_1;
    }

    inline static int getOpponentById(int id)
    {
        return id == 1 ? 2 : 1;
    }

private:
    player_t who;
    int id;
};

#endif // PLAYER_H
