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

#ifndef EVALUATE_H
#define EVALUATE_H

#include "config.h"

#include "position.h"
#include "search.h"

class Evaluation
{
public:
    Evaluation() = delete;

    Evaluation &operator=(const Evaluation &) = delete;

    static value_t getValue(Game &tempGame, Position *Position, AIAlgorithm::Node *node);

    // 评估子力
#ifdef EVALUATE_ENABLE

#ifdef EVALUATE_MATERIAL
    static value_t evaluateMaterial(AIAlgorithm::Node *node)
    {
        return 0;
    }
#endif

#ifdef EVALUATE_SPACE
    static value_t evaluateSpace(AIAlgorithm::Node *node)
    {
        return 0;
    }
#endif

#ifdef EVALUATE_MOBILITY
    static value_t evaluateMobility(AIAlgorithm::Node *node)
    {
        return 0;
    }
#endif

#ifdef EVALUATE_TEMPO
    static value_t evaluateTempo(AIAlgorithm::Node *node)
    {
        return 0;
    }
#endif

#ifdef EVALUATE_THREAT
    static value_t evaluateThreat(AIAlgorithm::Node *node)
    {
        return 0;
    }
#endif

#ifdef EVALUATE_SHAPE
    static value_t evaluateShape(AIAlgorithm::Node *node)
    {
        return 0;
    }
#endif

#ifdef EVALUATE_MOTIF
    static value_t AIAlgorithm::evaluateMotif(AIAlgorithm::Node *node)
    {
        return 0;
    }
#endif
#endif /* EVALUATE_ENABLE */

private:
};

#endif /* EVALUATE_H */
