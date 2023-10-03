// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

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
