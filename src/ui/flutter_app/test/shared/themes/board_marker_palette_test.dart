// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/themes/board_marker_palette.dart';

void main() {
  test('uses black neutral markers on a light board', () {
    final BoardMarkerPalette palette = BoardMarkerPalette.fromBackground(
      Colors.white,
    );

    expect(palette.contrast, Colors.black);
    expect(palette.bestMove, isNot(palette.completedMove));
    expect(palette.threat, isNot(palette.secondaryMove));
  });

  test('uses white neutral markers on a dark board', () {
    final BoardMarkerPalette palette = BoardMarkerPalette.fromBackground(
      Colors.black,
    );

    expect(palette.contrast, Colors.white);
    expect(palette, BoardMarkerPalette.fromBackground(const Color(0xFF101010)));
  });
}
