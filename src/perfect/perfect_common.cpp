// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_common.cpp

#include "perfect_common.h"
#include "perfect_errors.h"

#include <string>

std::string secValPath = ".";
std::string secValFileName = "";
FILE *f = nullptr;

int field2Offset;
int field1Size;
int field2Size;
int maxKsz;
sec_val secValMinValue;
std::string ruleVariantName;

void fail_with(std::string s)
{
    SET_ERROR_MESSAGE(PerfectErrors::PE_RUNTIME_ERROR,
                      ruleVariantName + ": " + s);
}
