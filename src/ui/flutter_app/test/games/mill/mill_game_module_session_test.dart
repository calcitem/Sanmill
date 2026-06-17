// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/game_platform/game_session_handle.dart';
import 'package:sanmill/games/mill/mill_game_module.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';

import '../../helpers/mocks/mock_database.dart';

void main() {
  group('MillGameModule session selection', () {
    late MockDB mockDb;

    setUp(() {
      mockDb = MockDB();
      DB.instance = mockDb;
    });

    tearDown(() {
      DB.instance = null;
    });

    test(
      'startSession uses injected native factory when dogfood flag is on',
      () {
        RuleSettings? forwardedRules;
        final _RecordingSession nativeSession = _RecordingSession();
        final MillGameModule module = MillGameModule(
          nativeSessionFactory:
              ({
                required RuleSettings ruleSettings,
                GeneralSettings? generalSettings,
              }) {
                forwardedRules = ruleSettings;
                return nativeSession;
              },
        );
        mockDb.generalSettings = const GeneralSettings();
        mockDb.ruleSettings = const RuleSettings(piecesCount: 12);

        final GameSessionHandle session = module.startSession();

        expect(session, same(nativeSession));
        expect(forwardedRules, same(mockDb.ruleSettings));
      },
    );

    test('startNativeSession forwards explicit rule settings', () {
      RuleSettings? forwardedRules;
      final _RecordingSession nativeSession = _RecordingSession();
      final MillGameModule module = MillGameModule(
        nativeSessionFactory:
            ({
              required RuleSettings ruleSettings,
              GeneralSettings? generalSettings,
            }) {
              forwardedRules = ruleSettings;
              return nativeSession;
            },
      );
      const RuleSettings rules = RuleSettings(piecesCount: 12);

      final GameSessionHandle session = module.startNativeSession(
        ruleSettings: rules,
      );

      expect(session, same(nativeSession));
      expect(forwardedRules, same(rules));
    });

    testWidgets('buildExportData opts out of flat generic Mill export', (
      WidgetTester tester,
    ) async {
      final MillGameModule module = MillGameModule();
      final _RecordingSession session = _RecordingSession();
      addTearDown(session.dispose);

      await tester.pumpWidget(
        Builder(
          builder: (BuildContext context) {
            expect(
              module.buildExportData(context, session: session),
              isNull,
              reason:
                  'Mill must fall back to the dedicated PGN exporter so tag '
                  'pairs, move numbers, variations, annotations, and setup '
                  'FEN are not replaced by a flat move-token list.',
            );
            return const SizedBox.shrink();
          },
        ),
      );
    });
  });
}

class _RecordingSession implements GameSessionHandle {
  _RecordingSession()
    : _state = ValueNotifier<GameStateSnapshot>(
        const GameStateSnapshot(
          gameId: GameId.mill,
          activeSeat: PlayerSeat.first,
          outcome: GameOutcome.ongoing(),
        ),
      );

  final ValueNotifier<GameStateSnapshot> _state;

  @override
  Stream<GameSessionEvent> get events => const Stream<GameSessionEvent>.empty();

  @override
  List<GameAction> get legalActions => const <GameAction>[];

  @override
  GameOutcome get outcome => _state.value.outcome;

  @override
  ValueListenable<GameStateSnapshot> get state => _state;

  @override
  Future<void> apply(GameAction action) async {}

  @override
  Future<void> redo() async {}

  @override
  Future<void> undo() async {}

  @override
  void dispose() => _state.dispose();
}
