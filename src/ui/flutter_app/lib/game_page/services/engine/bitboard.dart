// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
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

// ignore_for_file: always_specify_types

List<int> squareBB = List.filled(32, 0);

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
