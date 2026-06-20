// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_constants.dart';
import 'package:sanmill/games/mill/native_mill_ai_turn_controller.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';

import '../../helpers/test_native_library.dart';

const GeneralSettings _deterministicAiSettings = GeneralSettings(
  moveTime: 0,
  shufflingEnabled: false,
);

const RuleSettings _boundedSelfPlayRules = RuleSettings(
  nMoveRule: 20,
  endgameNMoveRule: 20,
);

const List<String> _masterSkill1FullGame = <String>[
  'd6',
  'f4',
  'd2',
  'b4',
  'e4',
  'd5',
  'c4',
  'd3',
  'g4',
  'd7',
  'a4',
  'd1',
  'e5',
  'e3',
  'c3',
  'c5',
  'f6',
  'b6',
  'a4-a7',
  'b4-a4',
  'c4-b4',
  'c5-c4',
  'g4-g1',
  'd7-g7',
  'g1-g4',
  'g7-d7',
  'g4-g1',
  'd7-g7',
  'g1-g4',
  'g7-d7',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initRustLibForTests);
  tearDownAll(disposeRustLibForTests);

  group('Native Mill AI vs AI self-play FFI', () {
    test(
      'matches the master parity full move list through the Flutter AI path',
      () async {
        final NativeMillGameSession session = NativeMillGameSession(
          rules: _boundedSelfPlayRules,
          generalSettings: _deterministicAiSettings,
        );
        addTearDown(session.dispose);

        final List<String> moves = <String>[];
        final StreamSubscription<GameSessionEvent> subscription = session.events
            .listen((GameSessionEvent event) {
              if (event.type == MillEventTypes.moveApplied) {
                final Object? move = event.payload['move'];
                assert(move is String, 'moveApplied event must carry a move.');
                moves.add(move! as String);
              }
            });
        addTearDown(subscription.cancel);

        const NativeMillAiTurnController ai = NativeMillAiTurnController(
          generalSettings: _deterministicAiSettings,
          bothSidesAi: true,
        );

        for (int ply = 0; ply < 400 && !session.outcome.isTerminal; ply++) {
          final GameAction? applied = await ai.playIfAiTurn(session);
          await Future<void>.delayed(Duration.zero);
          expect(
            applied,
            isNotNull,
            reason:
                'AI self-play stalled before a terminal outcome at ply $ply.',
          );
        }

        expect(
          session.outcome.isTerminal,
          isTrue,
          reason: 'AI self-play must finish under the bounded N-move rule.',
        );
        expect(moves, _masterSkill1FullGame);
      },
      skip: nativeLibrarySkipReason() != null,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
