// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// thread.cpp

#include <iomanip>
#include <sstream>
#include <iostream>
#include <string>
#include <utility>

#include "mills.h"
#include "option.h"
#include "thread.h"
#include "thread_pool.h"
#include "uci.h"
#include "tt.h"
#include "search_engine.h"

#if defined(GABOR_MALOM_PERFECT_AI)
#include "perfect/perfect_adaptor.h"
#endif

#ifdef FLUTTER_UI
#include "engine_main.h"
#endif

#ifdef OPENING_BOOK
#include "opening_book.h"
#endif // OPENING_BOOK

using std::cout;
using std::string;
