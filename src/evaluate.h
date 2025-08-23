// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// evaluate.h

#ifndef EVALUATE_H_INCLUDED
#define EVALUATE_H_INCLUDED

#include <string>

#include "types.h"

class Position;

namespace Eval {

Value evaluate(Position &pos);
Value evaluate(Position &pos, Depth depth); // Overload with depth info for
                                            // hybrid evaluation

// NNUE evaluation
extern bool useNNUE;
extern std::string evalFile;
extern bool nnueInitialized;
extern int nnueMinDepth;
void init_nnue();

// Path normalization utility
std::string normalizePath(const std::string &path);

// NNUE file header checking utility
bool checkNNUEFileHeader(const std::string &filePath);

} // namespace Eval

#endif // #ifndef EVALUATE_H_INCLUDED
