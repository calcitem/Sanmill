// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_extra.cpp

#ifdef OPENING_BOOK
#include <deque>
#endif

#include <string>

#include "game.h"

#if defined(GABOR_MALOM_PERFECT_AI)
#include "perfect/perfect_adaptor.h"
#endif

using std::to_string;

#ifdef OPENING_BOOK
extern deque<int> openingBookDeque;
extern deque<int> openingBookDequeBak;
#endif

#ifdef NNUE_GENERATE_TRAINING_DATA
extern int nnueTrainingDataIndex;
#endif /* NNUE_GENERATE_TRAINING_DATA */

#ifdef NNUE_GENERATE_TRAINING_DATA
extern string nnueTrainingDataBestMove;
#endif /* NNUE_GENERATE_TRAINING_DATA */

#ifdef NNUE_GENERATE_TRAINING_DATA
extern string nnueTrainingDataGameResult;
#endif /* NNUE_GENERATE_TRAINING_DATA */
