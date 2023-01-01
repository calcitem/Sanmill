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

#ifndef DEBUG_H_INCLUDED
#define DEBUG_H_INCLUDED

#include "config.h"

#include <cstdio>

#ifdef QT_GUI_LIB
#include <QDebug>
#endif

//#define QT_NO_DEBUG_OUTPUT

#define CSTYLE_DEBUG_OUTPUT

#ifdef CSTYLE_DEBUG_OUTPUT
#define debugPrintf printf
#else
#ifdef QT_GUI_LIB
#define debugPrintf qDebug
#endif
#endif /* CSTYLE_DEBUG_OUTPUT */

#endif /* DEBUG_H_INCLUDED */
