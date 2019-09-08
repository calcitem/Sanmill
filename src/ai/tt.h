#ifndef TT_H
#define TT_H

#include "config.h"
#include "types.h"
#include "millgame.h"
#include "search.h"
#include "hashmap.h"

using namespace CTSL;

#ifdef TRANSPOSITION_TABLE_ENABLE
extern HashMap<hash_t, MillGameAi_ab::HashValue> transpositionTable;
#endif /* TRANSPOSITION_TABLE_ENABLE */

#endif /* TT_H */

