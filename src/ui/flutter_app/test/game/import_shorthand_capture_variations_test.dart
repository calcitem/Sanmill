// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/import_export/import_helpers.dart';
import 'package:sanmill/game_page/services/import_export/pgn.dart';

void main() {
  group('Import pre-processing', () {
    test('Expands shorthand capture-only alternatives in variations', () {
      const String original = '1. f4-g4xe4 (xd1 21. e4-f4xd2) *';

      final String expanded = expandShorthandCaptureVariations(original);

      // The first move in the variation should be expanded to include the base
      // segment of the preceding combined move.
      expect(expanded, contains('(f4-g4xd1'));

      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(expanded);
      final PgnNode<PgnNodeData> root = game.moves;

      // Root should have mainline + at least one variation.
      expect(root.children.length, greaterThanOrEqualTo(2));
      expect(root.children[0].data?.san, 'f4-g4xe4');
      expect(root.children[1].data?.san, 'f4-g4xd1');
    });

    test('Restores base token for multiple sibling variations', () {
      const String original = '1. f4-g4xe4 (xd1) (xa1) *';

      final String expanded = expandShorthandCaptureVariations(original);
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(expanded);
      final PgnNode<PgnNodeData> root = game.moves;

      // Root should have mainline + 2 variations.
      expect(root.children.length, 3);
      expect(root.children[0].data?.san, 'f4-g4xe4');
      expect(root.children[1].data?.san, 'f4-g4xd1');
      expect(root.children[2].data?.san, 'f4-g4xa1');
    });

    test('Does not rewrite variations that start with a normal move', () {
      const String original = '1. f4-g4xe4 (a1 g7) *';

      final String expanded = expandShorthandCaptureVariations(original);
      expect(expanded, original);

      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(expanded);
      final PgnNode<PgnNodeData> root = game.moves;

      // Mainline move + one variation.
      expect(root.children.length, 2);
      expect(root.children[0].data?.san, 'f4-g4xe4');
      expect(root.children[1].data?.san, 'a1');
    });
  });
}

