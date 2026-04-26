// SPDX-License-Identifier: GPL-3.0-or-later
// Phase 1 integration smoke-test: verifies that the Rust/FRB bridge loads
// correctly and that tgfHelloWorld() returns the expected prefix.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:sanmill/game_page/services/mill.dart' show ExtMove, PieceColor;
import 'package:sanmill/game_platform/board_geometry.dart';
import 'package:sanmill/game_platform/engine/legacy_tgf_kernel.dart';
import 'package:sanmill/game_platform/engine/native_topology.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_game_session.dart';
import 'package:sanmill/games/mill/mill_rules_port.dart';
import 'package:sanmill/src/rust/api/simple.dart';
import 'package:sanmill/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => RustLib.init());

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

  testWidgets('legacy kernel exposes C++ start position', (
    WidgetTester tester,
  ) async {
    const LegacyTgfKernel kernel = LegacyTgfKernel();

    final String startFen = kernel.reset();
    expect(startFen, contains(' w p p '));

    final List<String> actions = kernel.legalActions();
    expect(actions, hasLength(24));
    expect(actions, contains('d7'));

    expect(kernel.applyUci('d7'), isTrue);
    expect(kernel.fen(), contains(' b p p '));
  });

  testWidgets('Rust topology matches Mill board shape', (
    WidgetTester tester,
  ) async {
    const NativeTopologyFactory factory = NativeTopologyFactory();
    final BoardGeometry geometry = factory.millBoardGeometry();

    expect(geometry.points, hasLength(24));
    expect(geometry.edges, hasLength(40));
    expect(geometry.points.first.x, 0.1);
    expect(geometry.points.first.y, 0.1);
    expect(geometry.points.last.x, 0.3);
    expect(geometry.points.last.y, 0.5);
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

  testWidgets('MillGameSession legalActions comes from RulesPort', (
    WidgetTester tester,
  ) async {
    final MillGameSession session = MillGameSession();
    addTearDown(session.dispose);

    expect(session.legalActions, hasLength(24));
    expect(
      session.legalActions.map((GameAction a) => a.payload['move']),
      contains('d7'),
    );
  });

  testWidgets('ExtMove notation uses Rust topology mapping', (
    WidgetTester tester,
  ) async {
    expect(ExtMove.sqToNotation(8), 'd5');
    final ExtMove move = ExtMove('d7', side: PieceColor.white);
    expect(move.to, 24);
    expect(move.notation, 'd7');
  });

  testWidgets('FRB-backed MillRulesPort enumerates and applies moves', (
    WidgetTester tester,
  ) async {
    final MillRulesPort rules = MillRulesPort();
    expect(rules.legalActions, hasLength(24));
    expect(rules.snapshot.phase, 'placing');
    expect(rules.fen, contains(' w p p '));
    rules.setFen('********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1');
    expect(rules.fen, contains(' w p p '));
    expect(rules.reset(), isA<GameStateSnapshot>());
    expect(rules.legalActions, hasLength(24));

    final GameAction first = rules.legalActions.first;
    final GameStateSnapshot after = rules.apply(first);
    expect(after.lastAction, first);
    expect(after.activeSeat, isNot(PlayerSeat.first));
  });

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
    expect(nativeAndLegacyPerftMatch(depth: 1), isTrue);
    expect(nativeAndLegacyPerftMatch(depth: 2), isTrue);
    expect(nativeAndLegacyPendingRemovePerftMatch(depth: 1), isTrue);
    expect(nativeAndLegacyPendingRemovePerftMatch(depth: 2), isTrue);
    expect(nativeAndLegacyMovingPhasePerftMatch(depth: 1), isTrue);
    expect(nativeAndLegacyMovingPhasePerftMatch(depth: 2), isTrue);
  });
}
