// SPDX-License-Identifier: AGPL-3.0-or-later
// Phase 1 integration smoke-test: verifies that the Rust/FRB bridge loads
// correctly and that tgfHelloWorld() returns the expected prefix.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:sanmill/game_page/services/mill.dart' show ExtMove, PieceColor;
import 'package:sanmill/game_platform/board_geometry.dart';
import 'package:sanmill/game_platform/engine/native_topology.dart';
import 'package:sanmill/game_platform/engine/tgf_kernel.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/game_platform/game_session_handle.dart';
import 'package:sanmill/game_platform/rules_port.dart';
import 'package:sanmill/games/mill/mill_game_module.dart';
import 'package:sanmill/games/mill/mill_variant_options_mapper.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/games/mill/native_mill_rules_port.dart';
import 'package:sanmill/games/othello/othello_game_session.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/src/rust/api/kernel.dart' as tgf_kernel_api;
import 'package:sanmill/src/rust/api/simple.dart';

import 'init_test_environment.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initTestEnvironment);

  testWidgets('tgfHelloWorld returns TGF greeting', (
    WidgetTester tester,
  ) async {
    final String greeting = tgfHelloWorld();
    expect(greeting, startsWith('hello from TGF'));
  });

  testWidgets('tgfVersion returns non-empty version', (
    WidgetTester tester,
  ) async {
    final String version = tgfVersion();
    expect(version, isNotEmpty);
  });

  // Phase 8.1: 'legacy kernel exposes C++ start position' test removed.
  // The LegacyTgfKernel / LegacyKernel path is being retired.  Full bridge
  // cleanup (removing LegacyPosition from legacy_engine_bridge.cpp and the
  // corresponding build.rs entries) is tracked in Phase 8.2.

  testWidgets('Rust topology matches Mill board shape', (
    WidgetTester tester,
  ) async {
    const NativeTopologyFactory factory = NativeTopologyFactory();
    final BoardGeometry geometry = factory.millBoardGeometry();

    expect(geometry.points, hasLength(24));
    expect(geometry.edges, hasLength(32));
    expect(geometry.points.first.x, closeTo(0.1, 1e-6));
    expect(geometry.points.first.y, closeTo(0.1, 1e-6));
    expect(geometry.points.last.x, closeTo(0.3, 1e-6));
    expect(geometry.points.last.y, closeTo(0.5, 1e-6));
  });

  testWidgets('Rust-native Mill rules scaffold matches opening count', (
    WidgetTester tester,
  ) async {
    expect(nativeMillInitialLegalCount(), 24);
    expect(nativeMillApplyFirstPlaceSideToMove(), 1);
    expect(nativeMillMillSequenceRemoveCount(), 2);
    expect(nativeMillMovingMillRemoveCount(), 3);
    expect(nativeMillRemovalBelowThreeWinner(), 0);

    final MillVariantOptions defaults = nativeMillDefaultVariantOptions();
    expect(defaults.pieceCount, 9);
    expect(defaults.flyPieceCount, 3);
    expect(defaults.piecesAtLeastCount, 3);
    expect(defaults.mayFly, isTrue);
    expect(defaults.hasDiagonalLines, isFalse);
    expect(nativeMillInitialLegalCountForVariant(variant: defaults), 24);

    final MillVariantOptions mapped = const RuleSettings()
        .toTgfMillVariantOptions();
    expect(mapped, defaults);
    expect(nativeMillSearchDepthOneBestToNode(), inInclusiveRange(0, 23));
    expect(nativeMillPvsDepthOneBestToNode(), inInclusiveRange(0, 23));
    expect(
      nativeMillRandomBestToNode(seed: BigInt.from(1234)),
      nativeMillRandomBestToNode(seed: BigInt.from(1234)),
    );
    expect(
      nativeMillMctsBestToNode(seed: BigInt.from(2026), iterationsPerMove: 2),
      inInclusiveRange(0, 23),
    );
    expect(nativeMillSearchZeroTimeLimitAborts(), isTrue);
  });

  testWidgets('Rust-native Othello APIs are available', (
    WidgetTester tester,
  ) async {
    expect(nativeOthelloInitialLegalCount(), 4);
    expect(nativeOthelloSearchDepthOneBestToNode(), inInclusiveRange(0, 63));
  });

  testWidgets(
    'NativeMillGameSession legalActions comes from native Rust port',
    (WidgetTester tester) async {
      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);

      expect(session.legalActions, hasLength(24));
      expect(
        session.legalActions.map((GameAction a) => a.payload['move']),
        contains('d7'),
      );
    },
  );

  testWidgets('ExtMove notation uses Rust topology mapping', (
    WidgetTester tester,
  ) async {
    expect(ExtMove.sqToNotation(8), 'd5');
    final ExtMove move = ExtMove('d7', side: PieceColor.white);
    expect(move.to, 24);
    expect(move.notation, 'd7');
  });

  testWidgets(
    'NativeMillRulesPort enumerates, applies, and resets (replaces legacy MillRulesPort)',
    (WidgetTester tester) async {
      final NativeMillRulesPort rules = NativeMillRulesPort();
      addTearDown(rules.dispose);
      expect(rules.legalActions, hasLength(24));
      expect(rules.snapshot.phase, 'placing');

      final GameAction first = rules.legalActions.first;
      final GameStateSnapshot after = rules.apply(first);
      expect(after.lastAction, first);
      expect(after.activeSeat, isNot(PlayerSeat.first));
      expect(rules.legalActions, hasLength(23));
    },
  );

  testWidgets('NativeMillRulesPort uses typed Rust Mill rules directly', (
    WidgetTester tester,
  ) async {
    final NativeMillRulesPort rules = NativeMillRulesPort();
    addTearDown(rules.dispose);

    expect(rules.snapshot.phase, 'placing');
    expect(rules.legalActions, hasLength(24));
    expect(
      rules.legalActions.map((GameAction a) => a.payload['move']),
      contains('d7'),
    );

    final GameAction first = rules.legalActions.first;
    final GameStateSnapshot after = rules.apply(first);
    expect(after.lastAction, first);
    expect(after.activeSeat, isNot(PlayerSeat.first));
    expect(rules.legalActions, hasLength(23));

    final GameStateSnapshot undone = rules.undo();
    expect(undone.activeSeat, PlayerSeat.first);
    expect(rules.legalActions, hasLength(24));
  });

  testWidgets(
    'NativeMillGameSession applies, undoes, redoes, and emits events',
    (WidgetTester tester) async {
      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);

      final List<GameSessionEvent> events = <GameSessionEvent>[];
      final StreamSubscription<GameSessionEvent> sub = session.events.listen(
        events.add,
      );
      addTearDown(sub.cancel);

      expect(session.state.value.phase, 'placing');
      expect(session.legalActions, hasLength(24));

      final GameAction first = session.legalActions.first;
      await session.apply(first);
      expect(session.state.value.activeSeat, isNot(PlayerSeat.first));
      expect(
        events.map((GameSessionEvent e) => e.type),
        contains('millStateChanged'),
      );

      await session.undo();
      expect(session.state.value.activeSeat, PlayerSeat.first);
      expect(session.legalActions, hasLength(24));

      await session.redo();
      expect(session.state.value.activeSeat, isNot(PlayerSeat.first));
    },
  );

  testWidgets(
    'MillGameModule startSession respects useNativeMillSession; exposes native factory',
    (WidgetTester tester) async {
      final MillGameModule module = MillGameModule();

      final GameSessionHandle started = module.startSession();
      addTearDown(started.dispose);
      // startSession() always returns NativeMillGameSession now.
      expect(started, isA<NativeMillGameSession>());

      final NativeMillGameSession nativeSession =
          module.startNativeSession() as NativeMillGameSession;
      expect(nativeSession, isA<NativeMillGameSession>());
      expect(nativeSession.legalActions, hasLength(24));
      nativeSession.dispose();

      final RulesPort nativeRules = module.nativeRulesPort();
      expect(nativeRules, isA<NativeMillRulesPort>());
      expect(nativeRules.legalActions, hasLength(24));
      (nativeRules as NativeMillRulesPort).dispose();
    },
  );

  testWidgets('Rust-native search emits event stream', (
    WidgetTester tester,
  ) async {
    final List<EngineEvent> events = await nativeMillSearchEvents(
      depth: 1,
    ).take(4).toList();

    expect(events.map((EngineEvent e) => e.kind), <String>[
      'ready',
      'info',
      'bestMove',
      'stopped',
    ]);
    expect(events[2].toNode, inInclusiveRange(0, 23));
    expect(nativeMillSearchStop(), isFalse);
  });

  testWidgets('Typed FRB kernel API exposes a Mill session', (
    WidgetTester tester,
  ) async {
    final TgfKernel kernel = TgfKernel.create('mill');
    addTearDown(kernel.dispose);

    expect(kernel.gameId, 'mill');
    expect(kernel.rawLegalActions(), hasLength(24));
    expect(kernel.isTerminal, isFalse);
    expect(kernel.undoDepth, 0);

    final tgf_kernel_api.TgfAction firstAction = kernel.rawLegalActions().first;
    final GameStateSnapshot after = kernel.applyTypedAction(firstAction);
    expect(after.activeSeat, isNot(PlayerSeat.first));
    expect(kernel.undoDepth, 1);

    final GameStateSnapshot undone = kernel.undoTyped();
    expect(undone.activeSeat, PlayerSeat.first);
    expect(kernel.redoDepth, 1);
  });

  testWidgets('OthelloGameSession runs entirely on the typed Rust kernel', (
    WidgetTester tester,
  ) async {
    final OthelloGameSession session = OthelloGameSession();
    addTearDown(session.dispose);

    expect(session.legalActions, hasLength(4));
    final GameAction first = session.legalActions.first;
    await session.apply(first);
    expect(session.outcome.isTerminal, isFalse);

    await session.undo();
    expect(session.legalActions, hasLength(4));
  });
}
