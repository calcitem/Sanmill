// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:math' show pi;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';
import 'package:sanmill/game_page/services/animation/headless_animation_manager.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/services/painters/animations/piece_effect_animation.dart';
import 'package:sanmill/game_page/services/painters/painters.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_action_codec.dart';
import 'package:sanmill/games/mill/mill_board_coordinate_maps.dart';
import 'package:sanmill/games/mill/native_mill_snapshot_board_view.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/themes/app_theme.dart';

import '../../../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DB.instance = MockDB();
    AppTheme.boardPadding = 28.0;
  });

  group('PiecePainter', () {
    test('maps native remove actions to capturable board points', () {
      final Set<int> indices =
          PiecePainter.capturableGridIndicesFromLegalActions(<GameAction>[
            GameAction(
              type: MillActionTypes.remove,
              payload: <String, Object?>{'toNode': _nodeFor('a7')},
            ),
            GameAction(
              type: MillActionTypes.remove,
              payload: <String, Object?>{'toNode': _nodeFor('d7')},
            ),
            GameAction(
              type: MillActionTypes.move,
              payload: <String, Object?>{'toNode': _nodeFor('g7')},
            ),
          ]);

      expect(indices, <int>{_legacyGridIndex('a7'), _legacyGridIndex('d7')});
    });

    test('maps selected source moves to legal destination points', () {
      final Set<int> indices =
          PiecePainter.legalMoveDestinationGridIndicesFromLegalActions(
            <GameAction>[
              GameAction(
                type: MillActionTypes.move,
                payload: <String, Object?>{
                  'fromNode': _nodeFor('a7'),
                  'toNode': _nodeFor('d7'),
                },
              ),
              GameAction(
                type: MillActionTypes.move,
                payload: <String, Object?>{
                  'fromNode': _nodeFor('a7'),
                  'toNode': _nodeFor('g7'),
                },
              ),
              GameAction(
                type: MillActionTypes.move,
                payload: <String, Object?>{
                  'fromNode': _nodeFor('d6'),
                  'toNode': _nodeFor('d7'),
                },
              ),
              GameAction(
                type: MillActionTypes.place,
                payload: <String, Object?>{'toNode': _nodeFor('a4')},
              ),
              GameAction(
                type: MillActionTypes.remove,
                payload: <String, Object?>{'toNode': _nodeFor('g4')},
              ),
            ],
            selectedSourceGridIndex: _legacyGridIndex('a7'),
          );

      expect(indices, <int>{_legacyGridIndex('d7'), _legacyGridIndex('g7')});
      expect(
        PiecePainter.legalMoveDestinationGridIndicesFromLegalActions(
          const <GameAction>[],
          selectedSourceGridIndex: null,
        ),
        isEmpty,
      );
    });

    test('maps placing actions to legal empty points without a source', () {
      final Set<int> indices =
          PiecePainter.legalMoveDestinationGridIndicesFromLegalActions(
            <GameAction>[
              GameAction(
                type: MillActionTypes.place,
                payload: <String, Object?>{'toNode': _nodeFor('a7')},
              ),
              GameAction(
                type: MillActionTypes.place,
                payload: <String, Object?>{'toNode': _nodeFor('d7')},
              ),
              GameAction(
                type: MillActionTypes.remove,
                payload: <String, Object?>{'toNode': _nodeFor('g7')},
              ),
            ],
            selectedSourceGridIndex: null,
          );

      expect(indices, <int>{_legacyGridIndex('a7'), _legacyGridIndex('d7')});
    });

    test('repaints when native board occupancy changes', () {
      final NativeMillSnapshotBoardView before = _viewWithBlackAtNode(23);
      final NativeMillSnapshotBoardView after = _viewWithBlackAtNode(22);

      final PiecePainter oldPainter = _painterFor(before);
      final PiecePainter newPainter = _painterFor(after);

      expect(newPainter.shouldRepaint(oldPainter), isTrue);
    });

    test('repaints when a piece number changes', () {
      final NativeMillSnapshotBoardView view = _viewWithBlackAtNode(23);
      final PiecePainter oldPainter = _painterFor(view);
      final PiecePainter newPainter = _painterFor(
        view,
        pieceNumbersByNode: const <int, int>{23: 1},
      );

      expect(newPainter.shouldRepaint(oldPainter), isTrue);
    });

    test('repaints when legal destination points change', () {
      final NativeMillSnapshotBoardView view = _viewWithBlackAtNode(23);
      final PiecePainter oldPainter = _painterFor(view);
      final PiecePainter newPainter = _painterFor(
        view,
        legalMoveDestinationGridIndices: <int>{_legacyGridIndex('d7')},
      );

      expect(newPainter.shouldRepaint(oldPainter), isTrue);
    });

    testWidgets('paints a placement number when the setting is enabled', (
      WidgetTester tester,
    ) async {
      DB().displaySettings = DB().displaySettings.copyWith(
        isNumbersOnPiecesShown: true,
      );
      final NativeMillSnapshotBoardView view = _viewWithBlackAtNode(23);
      final PiecePainter painter = _painterFor(
        view,
        pieceNumbersByNode: const <int, int>{23: 7},
      );

      void paint(Canvas canvas) =>
          painter.paint(canvas, const Size.square(350));

      expect(paint, paints..paragraph());
    });

    testWidgets('rotates offline-board pieces for the player facing from top', (
      WidgetTester tester,
    ) async {
      DB().displaySettings = DB().displaySettings.copyWith(
        isNumbersOnPiecesShown: true,
      );
      final NativeMillSnapshotBoardView view = _viewWithBlackAtNode(23);
      final PiecePainter upright = _painterFor(
        view,
        pieceNumbersByNode: const <int, int>{23: 2},
      );
      final PiecePainter rotated = _painterFor(
        view,
        pieceNumbersByNode: const <int, int>{23: 2},
        rotatePiecesForOfflineBoard: true,
      );

      void paintUpright(Canvas canvas) =>
          upright.paint(canvas, const Size.square(350));
      void paintRotated(Canvas canvas) =>
          rotated.paint(canvas, const Size.square(350));

      expect(paintUpright, isNot(paints..rotate()));
      expect(
        paintRotated,
        paints
          ..save()
          ..rotate(angle: pi)
          ..paragraph()
          ..restore(),
      );
      expect(rotated.shouldRepaint(upright), isTrue);
    });

    testWidgets('paints completed native move at destination', (
      WidgetTester tester,
    ) async {
      final GameController controller = GameController();
      controller.reset();
      controller.animationManager = HeadlessAnimationManager();

      final int sourceIndex = _legacyGridIndex('a7');
      final int destinationIndex = _legacyGridIndex('d7');
      controller.gameInstance
        ..blurIndex = sourceIndex
        ..focusIndex = destinationIndex;

      const Size size = Size.square(350);
      final Offset sourcePoint = pointFromIndex(sourceIndex, size);
      final Offset destinationPoint = pointFromIndex(destinationIndex, size);
      final double pieceRadius = _pieceRadius(size);

      final NativeMillSnapshotBoardView view = _viewWithBlackAtNode(
        _nodeFor('d7'),
      );
      final PiecePainter painter = _painterFor(view);
      void paint(Canvas canvas) => painter.paint(canvas, size);

      expect(
        paint,
        paints..circle(
          x: destinationPoint.dx,
          y: destinationPoint.dy,
          radius: pieceRadius,
        ),
      );
      expect(
        paint,
        isNot(
          paints
            ..circle(x: sourcePoint.dx, y: sourcePoint.dy, radius: pieceRadius),
        ),
      );
    });

    testWidgets('paints selected moving piece at its board square', (
      WidgetTester tester,
    ) async {
      final GameController controller = GameController();
      controller.reset();
      controller.animationManager = HeadlessAnimationManager();
      controller.gameInstance.gameMode = GameMode.puzzle;
      controller.puzzleHumanColor = PieceColor.black;

      final int sourceIndex = _legacyGridIndex('d3');
      controller.gameInstance
        ..blurIndex = sourceIndex
        ..focusIndex = null;

      const Size size = Size.square(350);
      final Offset sourcePoint = pointFromIndex(sourceIndex, size);
      final Offset bottomRight = Offset(size.width, size.height);
      final double pieceRadius = _pieceRadius(size);

      final NativeMillSnapshotBoardView view = _viewWithBlackAtNode(
        _nodeFor('d3'),
      );
      final PiecePainter painter = PiecePainter(
        placeAnimationValue: 0.0,
        moveAnimationValue: 1.0,
        removeAnimationValue: 1.0,
        pickUpAnimationValue: 0.5,
        putDownAnimationValue: 1.0,
        isPutDownAnimating: false,
        pieceImages: null,
        placeEffectAnimation: RadialPieceEffectAnimation(),
        removeEffectAnimation: ExplodePieceEffectAnimation(),
        nativeBoardView: view,
      );
      void paint(Canvas canvas) => painter.paint(canvas, size);

      expect(
        paint,
        paints
          ..circle(x: sourcePoint.dx, y: sourcePoint.dy, radius: pieceRadius),
      );
      expect(
        paint,
        isNot(
          paints
            ..circle(x: bottomRight.dx, y: bottomRight.dy, radius: pieceRadius),
        ),
      );
    });
  });
}

NativeMillSnapshotBoardView _viewWithBlackAtNode(int node) {
  final Uint8List payload = Uint8List(256);
  payload[node] = 2;
  return NativeMillSnapshotBoardView.fromSnapshot(
    GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: PlayerSeat.first,
      outcome: const GameOutcome.ongoing(),
      payload: <String, Object?>{'tgfPayload': payload},
    ),
  )!;
}

PiecePainter _painterFor(
  NativeMillSnapshotBoardView view, {
  Map<int, int> pieceNumbersByNode = const <int, int>{},
  Set<int> legalMoveDestinationGridIndices = const <int>{},
  bool rotatePiecesForOfflineBoard = false,
}) {
  return PiecePainter(
    placeAnimationValue: 1.0,
    moveAnimationValue: 1.0,
    removeAnimationValue: 1.0,
    pickUpAnimationValue: 1.0,
    putDownAnimationValue: 1.0,
    isPutDownAnimating: false,
    pieceImages: null,
    placeEffectAnimation: RadialPieceEffectAnimation(),
    removeEffectAnimation: ExplodePieceEffectAnimation(),
    nativeBoardView: view,
    legalMoveDestinationGridIndices: legalMoveDestinationGridIndices,
    pieceNumbersByNode: pieceNumbersByNode,
    rotatePiecesForOfflineBoard: rotatePiecesForOfflineBoard,
  );
}

int _legacyGridIndex(String notation) {
  final int square = MillBoardCoordinateMaps.notationToSquare[notation]!;
  return MillBoardCoordinateMaps.squareToGridIndex[square]!;
}

int _nodeFor(String notation) {
  final int square = MillBoardCoordinateMaps.notationToSquare[notation]!;
  return MillBoardCoordinateMaps.legacySquareToNode[square]!;
}

double _pieceRadius(Size size) {
  final double pieceWidth =
      (size.width - AppTheme.boardPadding * 2) *
          DB().displaySettings.pieceWidth /
          6 -
      1;
  return pieceWidth / 2;
}
