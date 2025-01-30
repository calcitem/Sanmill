// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_symmetries_slow.h

#ifndef PERFECT_SYMMETRIES_SLOW_H_INCLUDED
#define PERFECT_SYMMETRIES_SLOW_H_INCLUDED

int id_transform(int a);
int rotate90(int a);
int rotate180(int a);
int rotate270(int a);
int mirror_vertical(int a);
int mirror_horizontal(int a);
int mirror_backslash(int a);
int mirror_slash(int a);
int swap(int a);
int swap_rotate90(int a);
int swap_rotate180(int a);
int swap_rotate270(int a);
int swap_mirror_vertical(int a);
int swap_mirror_horizontal(int a);
int swap_mirror_backslash(int a);
int swap_mirror_slash(int a);

#endif // PERFECT_SYMMETRIES_SLOW_H_INCLUDED
