#include "tt.h"

#ifdef TRANSPOSITION_TABLE_ENABLE
static constexpr int TRANSPOSITION_TABLE_SIZE = 0x2000000; // 8-128M:102s, 4-64M:93s 2-32M:91s 1-16M: 冲突
HashMap<hash_t, MillGameAi_ab::HashValue> transpositionTable(TRANSPOSITION_TABLE_SIZE);
#endif // TRANSPOSITION_TABLE_ENABLE
