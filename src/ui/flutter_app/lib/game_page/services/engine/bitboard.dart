// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// bitboard.dart

List<int> squareBB = List<int>.filled(32, 0);

int squareBb(int s) {
  if (!(8 <= s && s < 32)) {
    return 0;
  }
  return squareBB[s];
}

void initBitboards() {
  for (int s = 8; s < 32; ++s) {
    squareBB[s] = 1 << s;
  }
}
