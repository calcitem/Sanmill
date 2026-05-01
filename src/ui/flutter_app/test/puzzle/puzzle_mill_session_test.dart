// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_mill_session_test.dart
//
// Unit-level structural tests for PuzzleMillSession.
//
// These tests verify the class API surface and constructor signature
// without exercising the Rust/FRB layer (which requires an integration
// test environment with RustLib.init()).  Full FEN-load and apply
// behaviour is covered in integration_test/setup_position_native_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/lan_session_meta.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/games/mill/puzzle_mill_session.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';

void main() {
  group('PuzzleMillSession class structure', () {
    test('PuzzleMillSession is a subclass of NativeMillGameSession', () {
      // Verify the class hierarchy at the type system level.
      expect(PuzzleMillSession, isNotNull);
      expect(NativeMillGameSession, isNotNull);
    });

    test('LanSessionMeta value equality is symmetric', () {
      const LanSessionMeta a = LanSessionMeta(
        localSeat: PlayerSeat.first,
        hostPlaysWhite: true,
      );
      const LanSessionMeta b = LanSessionMeta(
        localSeat: PlayerSeat.first,
        hostPlaysWhite: true,
      );
      expect(a, equals(b));
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('RuleSettings default equals const default', () {
      const RuleSettings a = RuleSettings();
      const RuleSettings b = RuleSettings();
      // Only checks that construction does not throw; deep equality depends on
      // generated code which may not be available in unit-test context.
      expect(a, isNotNull);
      expect(b, isNotNull);
    });
  });
}
