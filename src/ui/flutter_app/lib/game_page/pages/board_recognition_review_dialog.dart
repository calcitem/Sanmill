// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../services/board_image_recognition.dart';
import '../services/mill.dart';

/// Interactive confirmation for a recognized position.
class BoardRecognitionReviewDialog extends StatefulWidget {
  const BoardRecognitionReviewDialog({super.key, required this.result});

  final BoardRecognitionResult result;

  @override
  State<BoardRecognitionReviewDialog> createState() =>
      _BoardRecognitionReviewDialogState();
}

class _BoardRecognitionReviewDialogState
    extends State<BoardRecognitionReviewDialog> {
  late final Map<int, PieceColor> _pieces;
  late final Map<int, double> _confidences;

  @override
  void initState() {
    super.initState();
    assert(widget.result.isSuccess);
    assert(widget.result.rectifiedImageBytes != null);
    _pieces = Map<int, PieceColor>.from(widget.result.pieces);
    _confidences = Map<int, double>.from(widget.result.confidences);
  }

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final int whiteCount = _pieces.values
        .where((PieceColor color) => color == PieceColor.white)
        .length;
    final int blackCount = _pieces.values
        .where((PieceColor color) => color == PieceColor.black)
        .length;
    final bool hasPieces = whiteCount + blackCount > 0;

    return Dialog(
      key: const Key('board_recognition_review_dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 900),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                strings.identificationResults,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                strings.boardRecognitionReviewInstruction,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          return GestureDetector(
                            key: const Key('board_recognition_review_board'),
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (TapUpDetails details) =>
                                _handleBoardTap(details, constraints.biggest),
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                Image.memory(
                                  widget.result.rectifiedImageBytes!,
                                  fit: BoxFit.fill,
                                  gaplessPlayback: true,
                                ),
                                CustomPaint(
                                  painter: _RecognitionReviewPainter(
                                    points: widget.result.boardPoints,
                                    pieces: Map<int, PieceColor>.unmodifiable(
                                      _pieces,
                                    ),
                                    confidences: Map<int, double>.unmodifiable(
                                      _confidences,
                                    ),
                                    imageSize: Size(
                                      widget.result.processedWidth.toDouble(),
                                      widget.result.processedHeight.toDouble(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 24,
                runSpacing: 8,
                children: <Widget>[
                  Text(strings.boardRecognitionWhitePieceCount(whiteCount)),
                  Text(strings.boardRecognitionBlackPieceCount(blackCount)),
                ],
              ),
              const SizedBox(height: 12),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                overflowSpacing: 8,
                children: <Widget>[
                  TextButton(
                    key: const Key('board_recognition_review_cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(strings.cancel),
                  ),
                  ElevatedButton(
                    key: const Key('board_recognition_review_apply'),
                    onPressed: hasPieces
                        ? () => Navigator.of(
                            context,
                          ).pop(Map<int, PieceColor>.from(_pieces))
                        : null,
                    child: Text(strings.applyToBoard),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleBoardTap(TapUpDetails details, Size boardSize) {
    if (widget.result.processedWidth <= 0 ||
        widget.result.processedHeight <= 0) {
      return;
    }

    // The GestureDetector is square and the rectified image fills it.
    final double scaleX =
        widget.result.processedWidth / math.max(1, boardSize.width);
    final double scaleY =
        widget.result.processedHeight / math.max(1, boardSize.height);
    final Offset imagePoint = Offset(
      details.localPosition.dx * scaleX,
      details.localPosition.dy * scaleY,
    );

    int? nearestIndex;
    double nearestDistance = double.infinity;
    for (int index = 0; index < widget.result.boardPoints.length; index++) {
      final BoardPoint point = widget.result.boardPoints[index];
      final double distance =
          (Offset(point.x.toDouble(), point.y.toDouble()) - imagePoint)
              .distance;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
      }
    }
    if (nearestIndex == null) {
      return;
    }
    final BoardPoint point = widget.result.boardPoints[nearestIndex];
    if (nearestDistance > point.radius * 1.5) {
      return;
    }

    setState(() {
      _pieces[nearestIndex!] = switch (_pieces[nearestIndex]) {
        PieceColor.none || null => PieceColor.white,
        PieceColor.white => PieceColor.black,
        _ => PieceColor.none,
      };
      _confidences[nearestIndex] = 1;
    });
  }
}

class _RecognitionReviewPainter extends CustomPainter {
  const _RecognitionReviewPainter({
    required this.points,
    required this.pieces,
    required this.confidences,
    required this.imageSize,
  });

  final List<BoardPoint> points;
  final Map<int, PieceColor> pieces;
  final Map<int, double> confidences;
  final Size imageSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width <= 0 || imageSize.height <= 0) {
      return;
    }
    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;
    final double scale = math.min(scaleX, scaleY);

    for (int index = 0; index < points.length; index++) {
      final BoardPoint point = points[index];
      final Offset center = Offset(point.x * scaleX, point.y * scaleY);
      final double radius = math.max(8, point.radius * scale * 0.72);
      final PieceColor color = pieces[index] ?? PieceColor.none;
      final double confidence = confidences[index] ?? 0;

      if (color == PieceColor.none) {
        canvas.drawCircle(
          center,
          math.max(5, radius * 0.28),
          Paint()
            ..style = PaintingStyle.fill
            ..color = Colors.lightBlueAccent.withValues(alpha: 0.85),
        );
      } else {
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..style = PaintingStyle.fill
            ..color = color == PieceColor.white ? Colors.white : Colors.black,
        );
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = color == PieceColor.white ? Colors.black87 : Colors.white,
        );
      }

      if (confidence < 0.55) {
        canvas.drawCircle(
          center,
          radius + 4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = Colors.amber,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RecognitionReviewPainter oldDelegate) =>
      oldDelegate.pieces != pieces ||
      oldDelegate.confidences != confidences ||
      oldDelegate.points != points ||
      oldDelegate.imageSize != imageSize;
}
