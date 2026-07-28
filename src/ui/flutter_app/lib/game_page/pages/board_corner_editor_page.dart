// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../services/board_image_recognition.dart';

/// Lets the user align four handles with the outer square intersections.
class BoardCornerEditorPage extends StatefulWidget {
  const BoardCornerEditorPage({
    super.key,
    required this.imageBytes,
    required this.imageSize,
    this.initialCorners,
    this.cornerSuggestion,
  });

  final Uint8List imageBytes;
  final Size imageSize;
  final BoardImageCorners? initialCorners;
  final Future<BoardImageCorners?>? cornerSuggestion;

  @override
  State<BoardCornerEditorPage> createState() => _BoardCornerEditorPageState();
}

class _BoardCornerEditorPageState extends State<BoardCornerEditorPage> {
  static const double _handleDiameter = 38;

  late BoardImageCorners _initialCorners;
  late BoardImageCorners _corners;
  bool _cornersEdited = false;
  bool _isDetectingCorners = false;

  @override
  void initState() {
    super.initState();
    _initialCorners = widget.initialCorners ?? BoardImageCorners.inset();
    _corners = _initialCorners;
    _isDetectingCorners = widget.cornerSuggestion != null;
    unawaited(_applyCornerSuggestion());
  }

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    return Scaffold(
      key: const Key('board_corner_editor_page'),
      appBar: AppBar(
        title: Text(strings.adjustBoardArea),
        leading: IconButton(
          key: const Key('board_corner_editor_cancel'),
          tooltip: strings.cancel,
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 4,
              child: _isDetectingCorners
                  ? LinearProgressIndicator(
                      key: const Key('board_corner_editor_detection_progress'),
                      semanticsLabel: strings.analyzingGameBoardImage,
                    )
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                strings.boardRecognitionCornerInstruction,
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final Size canvasSize = constraints.biggest;
                  final Rect imageRect = _fittedImageRect(canvasSize);
                  final List<Offset> displayedPoints = <Offset>[
                    for (final Offset point in _corners.points)
                      Offset(
                        imageRect.left + point.dx * imageRect.width,
                        imageRect.top + point.dy * imageRect.height,
                      ),
                  ];

                  return ColoredBox(
                    color: Colors.black,
                    child: Stack(
                      children: <Widget>[
                        Positioned.fromRect(
                          rect: imageRect,
                          child: Image.memory(
                            widget.imageBytes,
                            key: const Key('board_corner_editor_image'),
                            fit: BoxFit.fill,
                            gaplessPlayback: true,
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _BoardCornerPolygonPainter(
                                points: displayedPoints,
                                valid: _corners.isValid,
                              ),
                            ),
                          ),
                        ),
                        for (
                          int index = 0;
                          index < displayedPoints.length;
                          index++
                        )
                          Positioned(
                            left:
                                displayedPoints[index].dx - _handleDiameter / 2,
                            top:
                                displayedPoints[index].dy - _handleDiameter / 2,
                            width: _handleDiameter,
                            height: _handleDiameter,
                            child: Semantics(
                              label: '${strings.adjustBoardArea} ${index + 1}',
                              child: GestureDetector(
                                key: Key('board_corner_handle_$index'),
                                behavior: HitTestBehavior.opaque,
                                onPanUpdate: (DragUpdateDetails details) {
                                  _moveHandle(index, details.delta, imageRect);
                                },
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black.withValues(alpha: 0.65),
                                    border: Border.all(
                                      color: _corners.isValid
                                          ? Colors.amber
                                          : Colors.redAccent,
                                      width: 3,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: _corners.isValid
                  ? const SizedBox(height: 12)
                  : Padding(
                      key: const Key('board_corner_editor_invalid'),
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        strings.boardRecognitionInvalidCorners,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: OutlinedButton.icon(
                      key: const Key('board_corner_editor_reset'),
                      onPressed: () {
                        setState(() {
                          _cornersEdited = true;
                          _corners = _initialCorners;
                        });
                      },
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        strings.resetToDefaults,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      key: const Key('board_corner_editor_confirm'),
                      onPressed: _corners.isValid
                          ? () => Navigator.of(context).pop(_corners)
                          : null,
                      child: Text(
                        strings.confirm,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Rect _fittedImageRect(Size canvasSize) {
    final FittedSizes fitted = applyBoxFit(
      BoxFit.contain,
      widget.imageSize,
      canvasSize,
    );
    return Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & canvasSize,
    );
  }

  Future<void> _applyCornerSuggestion() async {
    final Future<BoardImageCorners?>? suggestion = widget.cornerSuggestion;
    if (suggestion == null) {
      return;
    }
    BoardImageCorners? detected;
    try {
      detected = await suggestion;
    } catch (_) {
      detected = null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _isDetectingCorners = false;
      if (!_cornersEdited && (detected?.isValid ?? false)) {
        _initialCorners = detected!;
        _corners = detected;
      }
    });
  }

  void _moveHandle(int index, Offset delta, Rect imageRect) {
    if (imageRect.width <= 0 || imageRect.height <= 0) {
      return;
    }
    final Offset current = _corners.points[index];
    final Offset next = Offset(
      (current.dx + delta.dx / imageRect.width).clamp(0.0, 1.0),
      (current.dy + delta.dy / imageRect.height).clamp(0.0, 1.0),
    );
    setState(() {
      _cornersEdited = true;
      _corners = _corners.replace(index, next);
    });
  }
}

class _BoardCornerPolygonPainter extends CustomPainter {
  const _BoardCornerPolygonPainter({required this.points, required this.valid});

  final List<Offset> points;
  final bool valid;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length != 4) {
      return;
    }
    final Path path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final Offset point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..color = (valid ? Colors.amber : Colors.redAccent).withValues(
          alpha: 0.12,
        ),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = valid ? Colors.amber : Colors.redAccent,
    );
  }

  @override
  bool shouldRepaint(covariant _BoardCornerPolygonPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.valid != valid;
}
