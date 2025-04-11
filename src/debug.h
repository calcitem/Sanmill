// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// debug.h

#ifndef DEBUG_H_INCLUDED
#define DEBUG_H_INCLUDED

#include "config.h"

#include <cstdio>

#ifdef QT_GUI_LIB
#include <QDebug>
#endif

// #define QT_NO_DEBUG_OUTPUT

#define CSTYLE_DEBUG_OUTPUT

#ifdef CSTYLE_DEBUG_OUTPUT
#define debugPrintf printf
#else
#ifdef QT_GUI_LIB
#define debugPrintf qDebug
#endif
#endif /* CSTYLE_DEBUG_OUTPUT */

#endif /* DEBUG_H_INCLUDED */
