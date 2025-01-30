// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_sec_val.h

#ifndef PERFECT_SEV_VAL_H_INCLUDED
#define PERFECT_SEV_VAL_H_INCLUDED

#include "perfect_common.h"

#include <map>
#include <string>

extern std::map<Id, sec_val> sec_vals;
extern std::map<sec_val, Id> inv_sec_vals;
extern sec_val virt_loss_val, virt_win_val;

std::string sec_val_to_sec_name(sec_val v);

void init_sec_vals();

#endif // PERFECT_SEV_VAL_H_INCLUDED
