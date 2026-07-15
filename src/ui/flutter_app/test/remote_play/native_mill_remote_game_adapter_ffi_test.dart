// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_action_codec.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/games/mill/native_mill_remote_game_adapter.dart';
import 'package:sanmill/remote_play/remote_models.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_database.dart';
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

  for (final (String name, RuleSettings rules) in <(String, RuleSettings)>[
    (
      "Nine Men's Morris",
      const RuleSettings(nMoveRule: 20, endgameNMoveRule: 10),
    ),
    (
      "Twelve Men's Morris",
      const RuleSettings(
        piecesCount: 12,
        hasDiagonalLines: true,
        nMoveRule: 20,
        endgameNMoveRule: 10,
      ),
    ),
  ]) {
    test(
      '$name completes with identical native FEN on both peers',
      () async {
        final MockDB database = MockDB();
        DB.instance = database;
        database.ruleSettings = const RuleSettings();

        final NativeMillGameSession initial = NativeMillGameSession(
          rules: rules,
        );
        final String initialFen = initial.getFen();
        initial.dispose();

        final NativeMillGameSession hostSession = NativeMillGameSession();
        final NativeMillGameSession joinSession = NativeMillGameSession();
        final NativeMillRemoteGameAdapter host = NativeMillRemoteGameAdapter(
          session: hostSession,
          transportKind: RemoteTransportKind.lan,
          role: RemoteRole.host,
        );
        final NativeMillRemoteGameAdapter join = NativeMillRemoteGameAdapter(
          session: joinSession,
          transportKind: RemoteTransportKind.lan,
          role: RemoteRole.join,
        );
        addTearDown(hostSession.dispose);
        addTearDown(joinSession.dispose);

        final RemoteMatchConfig config = RemoteMatchConfig(
          sessionId: 'native-session-$name',
          roundId: 'native-round-$name',
          ruleSchemaVersion: 1,
          ruleSettings: rules.toJson(),
          initialFen: initialFen,
          hostPlaysFirst: true,
        );
        await host.configure(config);
        await join.configure(config);

        expect(hostSession.activeRuleSettings.piecesCount, rules.piecesCount);
        expect(
          hostSession.activeRuleSettings.hasDiagonalLines,
          rules.hasDiagonalLines,
        );
        expect(joinSession.activeRuleSettings.piecesCount, rules.piecesCount);
        expect(DB().ruleSettings.piecesCount, 9);
        expect(DB().ruleSettings.hasDiagonalLines, isFalse);

        int actions = 0;
        while (!hostSession.outcome.isTerminal && actions < 500) {
          final List<GameAction> legalActions = hostSession.legalActions;
          expect(legalActions, isNotEmpty);
          final int actionIndex =
              (actions * 7 + rules.piecesCount) % legalActions.length;
          final GameAction action = legalActions[actionIndex];
          final String notation = MillActionCodec.moveStringFrom(action)!;
          expect(await host.applyAction(notation), isTrue);
          expect(await join.applyAction(notation), isTrue);
          expect(join.fen, host.fen, reason: 'diverged after action $actions');
          actions++;
        }

        expect(actions, lessThan(500), reason: '$name did not terminate');
        expect(hostSession.outcome.isTerminal, isTrue);
        expect(joinSession.outcome.kind, hostSession.outcome.kind);
        expect(joinSession.outcome.winner, hostSession.outcome.winner);
        expect(join.fen, host.fen);
      },
      skip: _nativeLibrarySkipReason,
    );
  }
}
