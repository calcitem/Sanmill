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

    using value_t = MillGameAi_ab::value_t;

    static value_t getValue(MillGame &chessTemp, MillGame::ChessContext *chessContext, MillGameAi_ab::Node *node);

    // ÆÀ¹À×ÓÁ¦
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
    static value_t MillGameAi_ab::evaluateMotif(Node *node)
    {
        return 0;
    }
#endif
#endif /* EVALUATE_ENABLE */

private:
};

#endif /* EVALUATE_H */
