#ifndef EVALUATE_H
#define EVALUATE_H

#include "config.h"

#include "millgame.h"
#include "search.h"

class Evaluation
{
public:
    Evaluation() = delete;

    Evaluation &operator=(const Evaluation &) = delete;

    static value_t getValue(MillGame &gameTemp, GameContext *gameContext, MillGameAi_ab::Node *node);

    // ÆÀ¹À×ÓÁ¦
#ifdef EVALUATE_ENABLE

#ifdef EVALUATE_MATERIAL
    static value_t evaluateMaterial(MillGameAi_ab::Node *node)
    {
        return 0;
    }
#endif

#ifdef EVALUATE_SPACE
    static value_t evaluateSpace(MillGameAi_ab::Node *node)
    {
        return 0;
    }
#endif

#ifdef EVALUATE_MOBILITY
    static value_t evaluateMobility(MillGameAi_ab::Node *node)
    {
        return 0;
    }
#endif

#ifdef EVALUATE_TEMPO
    static value_t evaluateTempo(MillGameAi_ab::Node *node)
    {
        return 0;
    }
#endif

#ifdef EVALUATE_THREAT
    static value_t evaluateThreat(MillGameAi_ab::Node *node)
    {
        return 0;
    }
#endif

#ifdef EVALUATE_SHAPE
    static value_t evaluateShape(MillGameAi_ab::Node *node)
    {
        return 0;
    }
#endif

#ifdef EVALUATE_MOTIF
    static value_t MillGameAi_ab::evaluateMotif(MillGameAi_ab::Node *node)
    {
        return 0;
    }
#endif
#endif /* EVALUATE_ENABLE */

private:
};

#endif /* EVALUATE_H */
