// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

part of '../../../game_page/services/painters/painters.dart';

/// The atomic actions that make up the most recent Mill turn.
///
/// A turn starts with a placement or movement and can continue with one or
/// more removals. Keeping those actions together lets the board distinguish a
/// move that still requires a removal from a fully completed turn.
@immutable
class MillTurnHighlight {
  const MillTurnHighlight({
    required this.side,
    required this.primaryType,
    required this.fromSquare,
    required this.toSquare,
    required this.removedSquares,
    required this.isComplete,
  });

  final PieceColor side;
  final MoveType? primaryType;
  final int? fromSquare;
  final int? toSquare;
  final List<int> removedSquares;
  final bool isComplete;

  /// Builds a highlight from the current recorder path.
  ///
  /// Consecutive actions by the same side are scanned backwards until their
  /// placement or movement is found. This is the shape used by Mill turns
  /// whose removal is recorded as a separate atomic action.
  static MillTurnHighlight? fromPath(
    List<ExtMove> path, {
    required bool isRemovalPending,
  }) {
    if (path.isEmpty) {
      return null;
    }

    final ExtMove latest = path.last;
    if (latest.type == MoveType.draw || latest.type == MoveType.none) {
      return null;
    }

    final PieceColor side = latest.side;
    MoveType? primaryType;
    int? fromSquare;
    int? toSquare;
    final List<int> removedSquaresReversed = <int>[];

    for (int index = path.length - 1; index >= 0; index--) {
      final ExtMove action = path[index];
      if (action.side != side) {
        break;
      }

      switch (action.type) {
        case MoveType.remove:
          removedSquaresReversed.add(action.to);
          break;
        case MoveType.place:
          primaryType = MoveType.place;
          toSquare = action.to;
          index = -1;
          break;
        case MoveType.move:
          primaryType = MoveType.move;
          fromSquare = action.from;
          toSquare = action.to;
          index = -1;
          break;
        case MoveType.draw:
        case MoveType.none:
          index = -1;
          break;
      }
    }

    if (primaryType == null && removedSquaresReversed.isEmpty) {
      return null;
    }

    return MillTurnHighlight(
      side: side,
      primaryType: primaryType,
      fromSquare: fromSquare,
      toSquare: toSquare,
      removedSquares: List<int>.unmodifiable(removedSquaresReversed.reversed),
      isComplete: !isRemovalPending,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MillTurnHighlight &&
        other.side == side &&
        other.primaryType == primaryType &&
        other.fromSquare == fromSquare &&
        other.toSquare == toSquare &&
        listEquals(other.removedSquares, removedSquares) &&
        other.isComplete == isComplete;
  }

  @override
  int get hashCode => Object.hash(
    side,
    primaryType,
    fromSquare,
    toSquare,
    Object.hashAll(removedSquares),
    isComplete,
  );
}

/// Paints the most recent complete or provisional Mill turn.
class TurnHighlightPainter extends CustomPainter {
  const TurnHighlightPainter({
    required this.highlight,
    required this.color,
    required this.pieceWidth,
  });

  final MillTurnHighlight? highlight;
  final Color color;
  final double pieceWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final MillTurnHighlight? turn = highlight;
    if (turn == null) {
      return;
    }

    final bool provisional = !turn.isComplete;
    final double boardInnerWidth = size.width - AppTheme.boardPadding * 2;
    final double pieceDiameter = boardInnerWidth * pieceWidth / 6 - 1;
    final double radius = max(8, pieceDiameter * 0.57);
    final double strokeWidth = provisional ? 2.0 : 3.5;
    final Paint paint = Paint()
      ..color = color.withValues(alpha: provisional ? 0.78 : 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (turn.primaryType) {
      case MoveType.place:
        final int? square = turn.toSquare;
        if (square != null) {
          _drawRing(
            canvas,
            pointFromSquare(square, size),
            radius,
            paint,
            dashed: provisional,
          );
        }
        break;
      case MoveType.move:
        final int? from = turn.fromSquare;
        final int? to = turn.toSquare;
        if (from != null && to != null) {
          _drawArrow(
            canvas,
            pointFromSquare(from, size),
            pointFromSquare(to, size),
            radius,
            paint,
            dashed: provisional,
          );
        }
        break;
      case MoveType.remove:
      case MoveType.draw:
      case MoveType.none:
      case null:
        break;
    }

    for (final int square in turn.removedSquares) {
      _drawRemoval(
        canvas,
        pointFromSquare(square, size),
        radius * 0.66,
        paint,
        dashed: provisional,
      );
    }
  }

  static void _drawRing(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint, {
    required bool dashed,
  }) {
    if (!dashed) {
      canvas.drawCircle(center, radius, paint);
      return;
    }

    const int segmentCount = 16;
    const double segmentSweep = pi / segmentCount;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);
    for (int segment = 0; segment < segmentCount; segment++) {
      canvas.drawArc(
        rect,
        segment * 2 * pi / segmentCount,
        segmentSweep,
        false,
        paint,
      );
    }
  }

  static void _drawArrow(
    Canvas canvas,
    Offset rawStart,
    Offset rawEnd,
    double inset,
    Paint paint, {
    required bool dashed,
  }) {
    final Offset direction = rawEnd - rawStart;
    if (direction.distance == 0) {
      return;
    }
    final Offset unit = direction / direction.distance;
    final Offset start = rawStart + unit * inset;
    final Offset end = rawEnd - unit * inset;
    _drawLine(canvas, start, end, paint, dashed: dashed);

    final double headLength = max(9, inset * 0.45);
    final double headAngle = pi / 6;
    final Offset left = end - _rotate(unit, headAngle) * headLength;
    final Offset right = end - _rotate(unit, -headAngle) * headLength;
    _drawLine(canvas, end, left, paint, dashed: dashed);
    _drawLine(canvas, end, right, paint, dashed: dashed);
  }

  static Offset _rotate(Offset vector, double angle) {
    final double cosine = cos(angle);
    final double sine = sin(angle);
    return Offset(
      vector.dx * cosine - vector.dy * sine,
      vector.dx * sine + vector.dy * cosine,
    );
  }

  static void _drawRemoval(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint, {
    required bool dashed,
  }) {
    _drawLine(
      canvas,
      center + Offset(-radius, -radius),
      center + Offset(radius, radius),
      paint,
      dashed: dashed,
    );
    _drawLine(
      canvas,
      center + Offset(-radius, radius),
      center + Offset(radius, -radius),
      paint,
      dashed: dashed,
    );
  }

  static void _drawLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    required bool dashed,
  }) {
    if (!dashed) {
      canvas.drawLine(start, end, paint);
      return;
    }

    final Offset delta = end - start;
    final double length = delta.distance;
    if (length == 0) {
      return;
    }
    final Offset unit = delta / length;
    const double dashLength = 7;
    const double gapLength = 5;
    double distance = 0;
    while (distance < length) {
      final double dashEnd = min(distance + dashLength, length);
      canvas.drawLine(start + unit * distance, start + unit * dashEnd, paint);
      distance += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant TurnHighlightPainter oldDelegate) {
    return oldDelegate.highlight != highlight ||
        oldDelegate.color != color ||
        oldDelegate.pieceWidth != pieceWidth;
  }
}
