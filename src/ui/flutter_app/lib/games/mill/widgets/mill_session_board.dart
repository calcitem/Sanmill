// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../appearance_settings/models/color_settings.dart';
import '../../../game_platform/game_session.dart';
import '../../../generated/intl/l10n.dart';
import '../../../rule_settings/models/rule_settings.dart';
import '../../../shared/database/database.dart';
import '../../../shared/themes/app_theme.dart';
import '../../../shared/themes/board_marker_palette.dart';
import '../mill_action_codec.dart';
import '../mill_board_coordinate_maps.dart';
import '../mill_board_geometry.dart';
import '../mill_session_tap_controller.dart';
import '../native_mill_game_session.dart';
import '../native_mill_snapshot_board_view.dart';

typedef MillSessionPositionChanged =
    void Function({
      required String previousFen,
      required String currentFen,
      required GameAction action,
    });

/// A self-contained interactive Mill board backed by a native game session.
///
/// The widget applies only legal actions exposed by [session]. It owns no game
/// history or global controller state, so callers can safely use it for
/// secondary experiences such as opening exploration and mistake correction.
class MillSessionBoard extends StatefulWidget {
  const MillSessionBoard({
    super.key,
    required this.session,
    required this.tapController,
    required this.rules,
    required this.heightFactor,
    required this.onPositionChanged,
    this.boardKey,
    this.semanticLabel,
    this.enabled = true,
    this.highlightActions = const <String>[],
  });

  final NativeMillGameSession session;
  final MillSessionTapController tapController;
  final RuleSettings rules;
  final double heightFactor;
  final MillSessionPositionChanged onPositionChanged;
  final Key? boardKey;
  final String? semanticLabel;
  final bool enabled;
  final List<String> highlightActions;

  @override
  State<MillSessionBoard> createState() => _MillSessionBoardState();
}

class _MillSessionBoardState extends State<MillSessionBoard> {
  Future<void> _handleTap(Offset localPosition, Size size) async {
    if (!widget.enabled) {
      return;
    }
    final int node = MillBoardGeometry.nodeFromPosition(localPosition, size);
    if (node < 0) {
      widget.tapController.clearSelection();
      setState(() {});
      return;
    }
    final String notation = MillBoardCoordinateMaps.nodeToNotation(node);
    assert(notation.isNotEmpty, 'Interactive Mill node must have notation.');
    final String previousFen = widget.session.getFen();
    final MillSessionTapResult result = await widget.tapController.tap(
      session: widget.session,
      tappedLabel: notation,
    );
    if (!mounted) {
      return;
    }
    if (result.status == MillSessionTapStatus.applied) {
      final GameAction? action = result.action;
      assert(action != null, 'Applied board tap must include its action.');
      if (action == null) {
        throw StateError('Applied board tap must include its action.');
      }
      widget.onPositionChanged(
        previousFen: previousFen,
        currentFen: widget.session.getFen(),
        action: action,
      );
    }
    if (result.status != MillSessionTapStatus.ignored) {
      setState(() {});
    }
  }

  Future<void> _handleNotationTap(String notation) async {
    if (!widget.enabled) {
      return;
    }
    final String previousFen = widget.session.getFen();
    final MillSessionTapResult result = await widget.tapController.tap(
      session: widget.session,
      tappedLabel: notation,
    );
    if (!mounted) {
      return;
    }
    if (result.status == MillSessionTapStatus.applied) {
      final GameAction? action = result.action;
      assert(action != null, 'Applied board tap must include its action.');
      if (action == null) {
        throw StateError('Applied board tap must include its action.');
      }
      widget.onPositionChanged(
        previousFen: previousFen,
        currentFen: widget.session.getFen(),
        action: action,
      );
    }
    if (result.status != MillSessionTapStatus.ignored) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorSettings colors = DB().colorSettings;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final BoardMarkerPalette markerPalette = BoardMarkerPalette.fromBackground(
      colors.boardBackgroundColor,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double available = math.min(
          constraints.maxWidth,
          MediaQuery.sizeOf(context).height * widget.heightFactor,
        );
        final double side = available.isFinite ? available : 320;
        return Center(
          child: SizedBox.square(
            key: widget.boardKey,
            dimension: side,
            child: ValueListenableBuilder<GameStateSnapshot>(
              valueListenable: widget.session.state,
              builder:
                  (
                    BuildContext context,
                    GameStateSnapshot snapshot,
                    Widget? child,
                  ) {
                    final _MillSessionLegalHints legalHints =
                        _MillSessionLegalHints.fromActions(
                          legalActions: widget.enabled
                              ? widget.session.legalActions
                              : const <GameAction>[],
                          selectedFrom: widget.tapController.selectedFrom,
                        );
                    final NativeMillSnapshotBoardView? boardView =
                        NativeMillSnapshotBoardView.fromSnapshot(snapshot);
                    final Widget updatedBoard = Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          excludeFromSemantics: true,
                          onTapUp: widget.enabled
                              ? (TapUpDetails details) => _handleTap(
                                  details.localPosition,
                                  Size.square(side),
                                )
                              : null,
                          child: CustomPaint(
                            painter: _MillSessionBoardPainter(
                              snapshot: snapshot,
                              selectedFrom: widget.tapController.selectedFrom,
                              legalHints: legalHints,
                              hasDiagonalLines: widget.rules.hasDiagonalLines,
                              boardBackgroundColor: colors.boardBackgroundColor,
                              boardLineColor: colors.boardLineColor,
                              whitePieceColor: colors.whitePieceColor,
                              blackPieceColor: colors.blackPieceColor,
                              markerPalette: markerPalette,
                              shadowColor: colorScheme.shadow,
                              highlightActions: widget.highlightActions,
                            ),
                            child: child,
                          ),
                        ),
                        for (
                          int node = 0;
                          node < MillBoardGeometry.nodeCount;
                          node++
                        )
                          _BoardNodeSemantics(
                            node: node,
                            side: side,
                            occupant: boardView?.pieceAtNode(node),
                            selected:
                                widget.tapController.selectedFrom ==
                                MillBoardCoordinateMaps.nodeToNotation(node),
                            enabled: widget.enabled,
                            onTap: _handleNotationTap,
                          ),
                      ],
                    );
                    final String? label = widget.semanticLabel;
                    return label == null
                        ? updatedBoard
                        : Semantics(
                            label: label,
                            container: true,
                            explicitChildNodes: true,
                            child: updatedBoard,
                          );
                  },
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}

class _BoardNodeSemantics extends StatelessWidget {
  const _BoardNodeSemantics({
    required this.node,
    required this.side,
    required this.occupant,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final int node;
  final double side;
  final PlayerSeat? occupant;
  final bool selected;
  final bool enabled;
  final Future<void> Function(String notation) onTap;

  @override
  Widget build(BuildContext context) {
    final String notation = MillBoardCoordinateMaps.nodeToNotation(node);
    final S strings = S.of(context);
    final String pointLabel = switch (occupant) {
      PlayerSeat.first => '${strings.whitePiece}: $notation',
      PlayerSeat.second => '${strings.blackPiece}: $notation',
      PlayerSeat.none || null => '$notation: ${strings.emptyPoint}',
    };
    final String label = selected
        ? '$pointLabel, ${strings.selected}'
        : pointLabel;
    final Offset center = MillBoardGeometry.nodeOffset(node, Size.square(side));
    final double target = math.max(44, side * 0.12);
    return Positioned(
      left: center.dx - target / 2,
      top: center.dy - target / 2,
      width: target,
      height: target,
      child: Semantics(
        key: Key('mill_session_board_node_$notation'),
        button: enabled,
        enabled: enabled,
        label: label,
        onTap: enabled ? () => onTap(notation) : null,
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _MillSessionLegalHints {
  const _MillSessionLegalHints({
    required this.sources,
    required this.targets,
    required this.removals,
  });

  factory _MillSessionLegalHints.fromActions({
    required Iterable<GameAction> legalActions,
    required String? selectedFrom,
  }) {
    final Set<int> sources = <int>{};
    final Set<int> targets = <int>{};
    final Set<int> removals = <int>{};
    final String? selected = selectedFrom?.toLowerCase();

    for (final GameAction action in legalActions) {
      final String? move = MillActionCodec.moveStringFrom(action);
      if (move == null || move.isEmpty) {
        continue;
      }
      if (action.type == MillActionTypes.remove && move.startsWith('x')) {
        _addNotationNode(removals, move.substring(1));
        continue;
      }
      if (action.type == MillActionTypes.place) {
        continue;
      }
      if (action.type != MillActionTypes.move || !move.contains('-')) {
        continue;
      }

      final List<String> parts = move.split('-');
      if (parts.length != 2) {
        continue;
      }
      final String from = parts[0].toLowerCase();
      final String to = parts[1].toLowerCase();
      if (selected == null || selected.isEmpty) {
        _addNotationNode(sources, from);
      } else if (from == selected) {
        _addNotationNode(targets, to);
      }
    }

    return _MillSessionLegalHints(
      sources: sources,
      targets: targets,
      removals: removals,
    );
  }

  final Set<int> sources;
  final Set<int> targets;
  final Set<int> removals;

  static void _addNotationNode(Set<int> nodes, String notation) {
    final int node = MillBoardCoordinateMaps.notationToNode(notation);
    if (node >= 0) {
      nodes.add(node);
    }
  }
}

class _MillSessionBoardPainter extends CustomPainter {
  const _MillSessionBoardPainter({
    required this.snapshot,
    required this.selectedFrom,
    required this.legalHints,
    required this.hasDiagonalLines,
    required this.boardBackgroundColor,
    required this.boardLineColor,
    required this.whitePieceColor,
    required this.blackPieceColor,
    required this.markerPalette,
    required this.shadowColor,
    required this.highlightActions,
  });

  final GameStateSnapshot snapshot;
  final String? selectedFrom;
  final _MillSessionLegalHints legalHints;
  final bool hasDiagonalLines;
  final Color boardBackgroundColor;
  final Color boardLineColor;
  final Color whitePieceColor;
  final Color blackPieceColor;
  final BoardMarkerPalette markerPalette;
  final Color shadowColor;
  final List<String> highlightActions;

  @override
  void paint(Canvas canvas, Size size) {
    final NativeMillSnapshotBoardView? board =
        NativeMillSnapshotBoardView.fromSnapshot(snapshot);

    final RRect background = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.shortestSide * 0.035),
    );
    canvas.drawRRect(background, Paint()..color = boardBackgroundColor);

    _drawCoordinates(canvas, size);
    _drawLines(canvas, size);
    _drawPoints(canvas, size);
    _drawHints(
      canvas,
      size,
      legalHints.targets,
      markerPalette.contrast,
      filled: true,
      opacity: 0.62,
      radiusFactor: 0.018,
    );
    _drawHints(
      canvas,
      size,
      legalHints.removals,
      markerPalette.contrast,
      filled: false,
      opacity: 0.82,
      radiusFactor: 0.06,
    );

    if (board != null) {
      _drawPieces(canvas, size, board);
    }
    _drawSelectedNode(canvas, size);
    _drawActionHighlights(canvas, size);
  }

  void _drawCoordinates(Canvas canvas, Size size) {
    final double side = size.shortestSide;
    final double padding = side * MillBoardGeometry.defaultPaddingFraction;
    final double cell = (side - padding * 2) / 6;
    final double originX = (size.width - side) / 2 + padding;
    final double originY = (size.height - side) / 2 + padding;
    final TextStyle textStyle = TextStyle(
      color: boardLineColor.withValues(alpha: 1.0),
      fontSize: AppTheme.textScaler.scale(math.max(10, side * 0.045)),
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    );

    for (int index = 0; index < _verticalCoordinates.length; index++) {
      _paintCoordinate(
        canvas,
        text: _verticalCoordinates[index],
        style: textStyle,
        center: Offset(originX - padding / 2, originY + index * cell),
      );
    }

    for (int index = 0; index < _horizontalCoordinates.length; index++) {
      _paintCoordinate(
        canvas,
        text: _horizontalCoordinates[index],
        style: textStyle,
        center: Offset(
          originX + index * cell,
          originY + cell * 6 + padding / 2,
        ),
      );
    }
  }

  void _paintCoordinate(
    Canvas canvas, {
    required String text,
    required TextStyle style,
    required Offset center,
  }) {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(style: style, text: text),
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  void _drawLines(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..color = boardLineColor
      ..strokeWidth = math.max(2, size.shortestSide * 0.007)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final List<List<int>> lines = hasDiagonalLines
        ? MillBoardCoordinateMaps.diagonalMillNodeLines
        : MillBoardCoordinateMaps.standardMillNodeLines;
    for (final List<int> line in lines) {
      final Path path = Path();
      for (int i = 0; i < line.length; i++) {
        final Offset point = MillBoardGeometry.nodeOffset(line[i], size);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, linePaint);
    }
  }

  void _drawPoints(Canvas canvas, Size size) {
    final Paint pointPaint = Paint()..color = boardLineColor;
    final double radius = size.shortestSide * 0.013;
    for (int node = 0; node < MillBoardGeometry.nodeCount; node++) {
      canvas.drawCircle(
        MillBoardGeometry.nodeOffset(node, size),
        radius,
        pointPaint,
      );
    }
  }

  void _drawHints(
    Canvas canvas,
    Size size,
    Set<int> nodes,
    Color color, {
    required bool filled,
    required double opacity,
    required double radiusFactor,
  }) {
    if (nodes.isEmpty) {
      return;
    }
    final Paint paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = math.max(2, size.shortestSide * 0.006)
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke;
    final double radius = size.shortestSide * radiusFactor;
    for (final int node in nodes) {
      canvas.drawCircle(
        MillBoardGeometry.nodeOffset(node, size),
        radius,
        paint,
      );
    }
  }

  void _drawPieces(
    Canvas canvas,
    Size size,
    NativeMillSnapshotBoardView board,
  ) {
    final double radius = size.shortestSide * 0.052;
    final Paint shadowPaint = Paint()
      ..color = shadowColor.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final Paint outlinePaint = Paint()
      ..color = boardLineColor.withValues(alpha: 0.55)
      ..strokeWidth = math.max(1, size.shortestSide * 0.004)
      ..style = PaintingStyle.stroke;

    for (int node = 0; node < MillBoardGeometry.nodeCount; node++) {
      final PlayerSeat? seat = board.pieceAtNode(node);
      if (seat == null) {
        continue;
      }
      final Offset center = MillBoardGeometry.nodeOffset(node, size);
      final Color pieceColor = seat == PlayerSeat.first
          ? whitePieceColor
          : blackPieceColor;
      final Paint piecePaint = Paint()..color = pieceColor;
      canvas.drawCircle(center.translate(1.5, 2), radius, shadowPaint);
      canvas.drawCircle(center, radius, piecePaint);
      canvas.drawCircle(center, radius, outlinePaint);
      if (board.markedNodes.contains(node)) {
        final Paint markedPaint = Paint()
          ..color = markerPalette.contrast
          ..strokeWidth = math.max(2, size.shortestSide * 0.007)
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(center, radius * 1.22, markedPaint);
      }
    }
  }

  void _drawSelectedNode(Canvas canvas, Size size) {
    final String? selected = selectedFrom;
    if (selected == null || selected.isEmpty) {
      return;
    }
    final int node = MillBoardCoordinateMaps.notationToNode(selected);
    if (node < 0) {
      return;
    }
    final Paint paint = Paint()
      ..color = markerPalette.contrast
      ..strokeWidth = math.max(2, size.shortestSide * 0.009)
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(
      MillBoardGeometry.nodeOffset(node, size),
      size.shortestSide * 0.068,
      paint,
    );
  }

  void _drawActionHighlights(Canvas canvas, Size size) {
    if (highlightActions.isEmpty) {
      return;
    }
    final double side = size.shortestSide;
    final Paint paint = Paint()
      ..color = markerPalette.completedMove
      ..strokeWidth = math.max(2.5, side * 0.009)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final double radius = side * 0.067;

    for (final String action in highlightActions) {
      if (action.startsWith('x')) {
        final int node = MillBoardCoordinateMaps.notationToNode(
          action.substring(1),
        );
        if (node < 0) {
          continue;
        }
        final Offset center = MillBoardGeometry.nodeOffset(node, size);
        final double arm = radius * 0.65;
        canvas.drawLine(
          center.translate(-arm, -arm),
          center.translate(arm, arm),
          paint,
        );
        canvas.drawLine(
          center.translate(-arm, arm),
          center.translate(arm, -arm),
          paint,
        );
        continue;
      }
      if (action.contains('-')) {
        final List<String> parts = action.split('-');
        if (parts.length != 2) {
          continue;
        }
        final int from = MillBoardCoordinateMaps.notationToNode(parts[0]);
        final int to = MillBoardCoordinateMaps.notationToNode(parts[1]);
        if (from < 0 || to < 0) {
          continue;
        }
        final Offset fromCenter = MillBoardGeometry.nodeOffset(from, size);
        final Offset toCenter = MillBoardGeometry.nodeOffset(to, size);
        canvas.drawLine(fromCenter, toCenter, paint);
        canvas.drawCircle(fromCenter, radius * 0.72, paint);
        canvas.drawCircle(toCenter, radius, paint);
        continue;
      }
      final int node = MillBoardCoordinateMaps.notationToNode(action);
      if (node >= 0) {
        canvas.drawCircle(
          MillBoardGeometry.nodeOffset(node, size),
          radius,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MillSessionBoardPainter oldDelegate) {
    return oldDelegate.snapshot != snapshot ||
        oldDelegate.selectedFrom != selectedFrom ||
        oldDelegate.legalHints != legalHints ||
        oldDelegate.hasDiagonalLines != hasDiagonalLines ||
        oldDelegate.boardBackgroundColor != boardBackgroundColor ||
        oldDelegate.boardLineColor != boardLineColor ||
        oldDelegate.whitePieceColor != whitePieceColor ||
        oldDelegate.blackPieceColor != blackPieceColor ||
        oldDelegate.markerPalette != markerPalette ||
        !listEquals(oldDelegate.highlightActions, highlightActions);
  }
}

const List<String> _verticalCoordinates = <String>[
  '7',
  '6',
  '5',
  '4',
  '3',
  '2',
  '1',
];
const List<String> _horizontalCoordinates = <String>[
  'a',
  'b',
  'c',
  'd',
  'e',
  'f',
  'g',
];
