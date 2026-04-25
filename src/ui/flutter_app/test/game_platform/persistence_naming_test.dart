// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/persistence/game_persistence_naming.dart';

void main() {
  group('scopePrefixFor', () {
    test('returns null for a missing game id', () {
      expect(scopePrefixFor(null), isNull);
    });

    test('returns the canonical "game.<id>." prefix', () {
      expect(scopePrefixFor(GameId.mill), 'game.mill.');
      expect(scopePrefixFor(GameId.demoProbe), 'game.demo_probe.');
    });
  });

  group('scopePrefixFromCategory', () {
    test('app category is independent of the game id', () {
      expect(
        scopePrefixFromCategory(PersistenceScopeCategory.app, null),
        'app.',
      );
      expect(
        scopePrefixFromCategory(PersistenceScopeCategory.app, GameId.mill),
        'app.',
      );
    });

    test('game category requires a game id', () {
      expect(
        scopePrefixFromCategory(PersistenceScopeCategory.game, null),
        isNull,
      );
      expect(
        scopePrefixFromCategory(PersistenceScopeCategory.game, GameId.mill),
        'game.mill.',
      );
    });
  });

  group('scoped settings catalog', () {
    test('app and game categories do not overlap', () {
      final Set<String> overlap = kAppScopedSettings.intersection(
        kGameScopedSettings,
      );
      expect(overlap, isEmpty);
    });
  });
}
