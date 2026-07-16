// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/puzzle/models/rule_variant.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/src/rust/api/simple.dart' as tgf;

import '../helpers/test_native_library.dart';

final String? _nativeLibrarySkipReason = nativeLibrarySkipReason();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (_nativeLibrarySkipReason == null) {
      await initRustLibForTests();
    }
  });
  tearDownAll(disposeRustLibForTests);

  test(
    'all canonical presets and deterministic reachable states fit capacity',
    () async {
      final int capacity = tgf.nativeMillSearchActionCapacity();
      expect(capacity, 72);

      for (final MapEntry<String, RuleSettings> preset
          in RuleVariant.canonicalSettings.entries) {
        final NativeMillGameSession session = NativeMillGameSession(
          rules: preset.value,
        );
        int random = preset.key.hashCode & 0x7fffffff;
        try {
          for (int ply = 0; ply < 256; ply++) {
            final List<GameAction> legal = session.legalActions;
            expect(
              legal.length,
              lessThanOrEqualTo(capacity),
              reason: '${preset.key} exceeded capacity at reachable ply $ply',
            );
            if (legal.isEmpty) {
              break;
            }
            random = (random * 1103515245 + 12345) & 0x7fffffff;
            await session.apply(legal[random % legal.length]);
          }
        } finally {
          session.dispose();
        }
      }
    },
    skip: _nativeLibrarySkipReason,
  );
}
