/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2015-2018 liuweilhy (NineChess author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

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

    static value_t getValue(Position *Position, Node *node);

    // 评估子力
#ifdef EVALUATE_ENABLE

#ifdef EVALUATE_MATERIAL
    static value_t evaluateMaterial(Node *node)
    {
        return 0;
    }
#endif

#ifdef EVALUATE_SPACE
    static value_t evaluateSpace(Node *node)
    {
        return 0;
    }
#endif

#ifdef EVALUATE_MOBILITY
    static value_t evaluateMobility(Node *node)
    {
        return 0;
    }
#endif

#ifdef EVALUATE_TEMPO
    static value_t evaluateTempo(Node *node)
    {
        return 0;
    }
#endif

#ifdef EVALUATE_THREAT
    static value_t evaluateThreat(Node *node)
    {
        return 0;
    }
#endif

#ifdef EVALUATE_SHAPE
    static value_t evaluateShape(Node *node)
    {
        return 0;
    }
#endif

#ifdef EVALUATE_MOTIF
    static value_t AIAlgorithm::evaluateMotif(Node *node)
    {
        return 0;
    }
#endif
#endif /* EVALUATE_ENABLE */

private:
};

#endif /* EVALUATE_H */
