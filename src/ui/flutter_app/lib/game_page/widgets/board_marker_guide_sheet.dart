// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/themes/board_marker_palette.dart';
import 'mini_board.dart';

enum _BoardMarkerSampleKind {
  selected,
  legalDestination,
  removable,
  completedMove,
  pendingRemoval,
  bestSuggestion,
  secondarySuggestion,
  threat,
}

Future<void> showBoardMarkerGuide(
  BuildContext context, {
  bool remoteGame = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) =>
        BoardMarkerGuideSheet(remoteGame: remoteGame),
  );
}

class BoardMarkerGuideSheet extends StatelessWidget {
  const BoardMarkerGuideSheet({super.key, this.remoteGame = false});

  final bool remoteGame;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final List<({String label, _BoardMarkerSampleKind kind})> markers =
        <({String label, _BoardMarkerSampleKind kind})>[
          (
            label: strings.markerSelectedPiece,
            kind: _BoardMarkerSampleKind.selected,
          ),
          (
            label: strings.markerLegalDestination,
            kind: _BoardMarkerSampleKind.legalDestination,
          ),
          (
            label: strings.markerRemovablePiece,
            kind: _BoardMarkerSampleKind.removable,
          ),
          (
            label: strings.markerCompletedMove,
            kind: _BoardMarkerSampleKind.completedMove,
          ),
          (
            label: strings.markerPendingRemoval,
            kind: _BoardMarkerSampleKind.pendingRemoval,
          ),
        ];
    if (!remoteGame) {
      markers.addAll(<({String label, _BoardMarkerSampleKind kind})>[
        (
          label: strings.markerBestSuggestion,
          kind: _BoardMarkerSampleKind.bestSuggestion,
        ),
        (
          label: strings.markerSecondarySuggestion,
          kind: _BoardMarkerSampleKind.secondarySuggestion,
        ),
        (label: strings.markerThreat, kind: _BoardMarkerSampleKind.threat),
      ]);
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: math.min(MediaQuery.sizeOf(context).height * 0.88, 720),
      ),
      child: Column(
        key: const Key('board_marker_guide_sheet'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              strings.boardMarkerGuide,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: markers.length + (remoteGame ? 0 : 2),
              separatorBuilder: (BuildContext context, int index) =>
                  const Divider(height: 1, indent: 164),
              itemBuilder: (BuildContext context, int index) {
                if (index < markers.length) {
                  final ({String label, _BoardMarkerSampleKind kind}) marker =
                      markers[index];
                  return _GuideRow(
                    label: marker.label,
                    sample: _BoardMarkerSample(kind: marker.kind),
                  );
                }
                if (index == markers.length) {
                  return _GuideRow(
                    label: strings.markerReviewQuality,
                    sample: const _QualityBadgeSample(),
                  );
                }
                return _GuideRow(
                  label: strings.drawingColors,
                  sample: const _DrawingColorSample(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  const _GuideRow({required this.label, required this.sample});

  final String label;
  final Widget sample;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: <Widget>[
            ExcludeSemantics(
              child: SizedBox(width: 128, height: 48, child: sample),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardMarkerSample extends StatelessWidget {
  const _BoardMarkerSample({required this.kind});

  final _BoardMarkerSampleKind kind;

  @override
  Widget build(BuildContext context) {
    final Color boardColor = DB().colorSettings.boardBackgroundColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: boardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: CustomPaint(
        key: Key('board_marker_sample_${kind.name}'),
        painter: _BoardMarkerSamplePainter(
          kind: kind,
          palette: BoardMarkerPalette.fromBackground(boardColor),
          whitePieceColor: DB().colorSettings.whitePieceColor,
          blackPieceColor: DB().colorSettings.blackPieceColor,
        ),
      ),
    );
  }
}

class _BoardMarkerSamplePainter extends CustomPainter {
  const _BoardMarkerSamplePainter({
    required this.kind,
    required this.palette,
    required this.whitePieceColor,
    required this.blackPieceColor,
  });

  final _BoardMarkerSampleKind kind;
  final BoardMarkerPalette palette;
  final Color whitePieceColor;
  final Color blackPieceColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset start = Offset(size.width * 0.25, size.height * 0.5);
    final Offset end = Offset(size.width * 0.75, size.height * 0.5);
    final Paint paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (kind) {
      case _BoardMarkerSampleKind.selected:
        _drawPiece(canvas, start, whitePieceColor);
        canvas.drawCircle(
          start,
          15,
          paint
            ..color = palette.contrast
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      case _BoardMarkerSampleKind.legalDestination:
        canvas.drawCircle(
          size.center(Offset.zero),
          5,
          paint
            ..color = palette.contrast.withValues(alpha: 0.62)
            ..style = PaintingStyle.fill,
        );
      case _BoardMarkerSampleKind.removable:
        _drawPiece(canvas, size.center(Offset.zero), blackPieceColor);
        canvas.drawCircle(
          size.center(Offset.zero),
          15,
          paint
            ..color = palette.contrast.withValues(alpha: 0.82)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      case _BoardMarkerSampleKind.completedMove:
        _drawTrail(canvas, start, end, palette.completedMove, dashed: false);
      case _BoardMarkerSampleKind.pendingRemoval:
        _drawTrail(canvas, start, end, palette.completedMove, dashed: true);
      case _BoardMarkerSampleKind.bestSuggestion:
        _drawArrow(canvas, start, end, palette.bestMove, width: 5);
      case _BoardMarkerSampleKind.secondarySuggestion:
        _drawArrow(canvas, start, end, palette.secondaryMove, width: 2.5);
      case _BoardMarkerSampleKind.threat:
        _drawDashedArrow(canvas, start, end, palette.threat);
    }
  }

  void _drawPiece(Canvas canvas, Offset center, Color color) {
    canvas.drawCircle(center, 12, Paint()..color = color);
  }

  void _drawTrail(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color, {
    required bool dashed,
  }) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = dashed ? 2.5 : 4
      ..strokeCap = StrokeCap.round;
    if (dashed) {
      _drawDashedLine(canvas, start, end, paint);
    } else {
      canvas.drawLine(start, end, paint);
    }
    canvas.drawCircle(start, 6, paint);
    canvas.drawCircle(end, 6, paint);
  }

  void _drawArrow(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color, {
    required double width,
  }) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, end - const Offset(8, 0), paint);
    final Path head = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(end.dx - 12, end.dy - 8)
      ..lineTo(end.dx - 12, end.dy + 8)
      ..close();
    canvas.drawPath(head, paint..style = PaintingStyle.fill);
    canvas.drawCircle(start, 5, paint);
  }

  void _drawDashedArrow(Canvas canvas, Offset start, Offset end, Color color) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    _drawDashedLine(canvas, start, end - const Offset(8, 0), paint);
    final Path head = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(end.dx - 12, end.dy - 8)
      ..lineTo(end.dx - 12, end.dy + 8)
      ..close();
    canvas.drawPath(head, paint);
    canvas.drawCircle(start, 6, paint);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    final Offset delta = end - start;
    final double length = delta.distance;
    final Offset direction = delta / length;
    for (double distance = 0; distance < length; distance += 10) {
      canvas.drawLine(
        start + direction * distance,
        start + direction * math.min(distance + 5, length),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BoardMarkerSamplePainter oldDelegate) {
    return oldDelegate.kind != kind ||
        oldDelegate.palette != palette ||
        oldDelegate.whitePieceColor != whitePieceColor ||
        oldDelegate.blackPieceColor != blackPieceColor;
  }
}

class _QualityBadgeSample extends StatelessWidget {
  const _QualityBadgeSample();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      runAlignment: WrapAlignment.center,
      spacing: 3,
      runSpacing: 3,
      children: <int>[1, 3, 5, 6, 2, 4].map((int nag) {
        return Container(
          width: 30,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: MiniBoardPainter.qualityBadgeBackgroundColor(nag),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            MiniBoardPainter.qualityNagSymbol(nag),
            style: TextStyle(
              color: MiniBoardPainter.qualityBadgeForegroundColor(nag),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _DrawingColorSample extends StatelessWidget {
  const _DrawingColorSample();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      runAlignment: WrapAlignment.center,
      spacing: 8,
      children:
          const <Color>[
            Colors.green,
            Colors.red,
            Colors.blue,
            Colors.yellow,
          ].map((Color color) {
            return DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: const SizedBox.square(dimension: 22),
            );
          }).toList(),
    );
  }
}
