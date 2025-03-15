// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// annotation_manager.dart

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../generated/intl/l10n.dart';
import '../../../shared/database/database.dart';
import '../../../shared/services/logger.dart';
import '../../../shared/themes/app_theme.dart';
import '../painters/painters.dart'; // Provides points, offsetFromPoint, pointFromIndex

/// AnnotationTool is an enum listing the possible drawing tools.
enum AnnotationTool { line, arrow, circle, dot, cross, rect, text, move }

/// AnnotationShape is the base class for all drawable annotations.
/// It holds a color field, and each subclass implements its own drawing and dragging logic.
abstract class AnnotationShape {
  AnnotationShape({required this.color});

  /// The color of this shape.
  Color color;

  /// Draws the shape on the provided [canvas] within the specified [size].
  void draw(Canvas canvas, Size size);

  /// Returns `true` if the tap position hits this shape (for selection).
  bool hitTest(Offset tapPosition);

  /// Translates the shape by the given [delta] offset for dragging.
  void translate(Offset delta);
}

// ---------------------------------------------------------------------------
// Shape Implementations
// ---------------------------------------------------------------------------

class AnnotationCircle extends AnnotationShape {
  AnnotationCircle({
    required this.center,
    required this.radius,
    required Color color,
    this.strokeWidth = 3.0,
  }) : super(color: color) {
    paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
  }

  // Factory constructor remains available (but is no longer used by the circle tool).
  factory AnnotationCircle.fromPoints({
    required Offset start,
    required Offset end,
    required Color color,
    double strokeWidth = 3.0,
  }) {
    final Offset center = Offset(
      (start.dx + end.dx) / 2,
      (start.dy + end.dy) / 2,
    );
    final double radius = (start - end).distance / 2;
    return AnnotationCircle(
      center: center,
      radius: radius,
      color: color,
      strokeWidth: strokeWidth,
    );
  }

  Offset center;
  double radius;
  final double strokeWidth;
  late Paint paint;

  @override
  void translate(Offset delta) {
    center += delta;
  }

  @override
  void draw(Canvas canvas, Size size) {
    paint.color = color;
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool hitTest(Offset tapPosition) {
    final double dist = (tapPosition - center).distance;
    return dist <= radius + 5.0;
  }
}

class AnnotationLine extends AnnotationShape {
  AnnotationLine({
    required this.start,
    required this.end,
    required super.color,
    this.strokeWidth = 3.0,
  });

  Offset start;
  Offset end;
  final double strokeWidth;

  @override
  void translate(Offset delta) {
    start += delta;
    end += delta;
  }

  @override
  void draw(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawLine(start, end, paint);
  }

  @override
  bool hitTest(Offset tapPosition) {
    const double threshold = 6.0;
    final double lineLen = (end - start).distance;
    if (lineLen < 0.5) {
      return (start - tapPosition).distance < threshold;
    }
    final double t = ((tapPosition.dx - start.dx) * (end.dx - start.dx) +
            (tapPosition.dy - start.dy) * (end.dy - start.dy)) /
        (lineLen * lineLen);
    if (t < 0) {
      return (tapPosition - start).distance <= threshold;
    } else if (t > 1) {
      return (tapPosition - end).distance <= threshold;
    } else {
      final Offset projection = Offset(
        start.dx + t * (end.dx - start.dx),
        start.dy + t * (end.dy - start.dy),
      );
      return (tapPosition - projection).distance <= threshold;
    }
  }
}

class AnnotationArrow extends AnnotationShape {
  AnnotationArrow({
    required this.start,
    required this.end,
    required Color color,
    this.strokeWidth = 3.0,
  }) : super(color: color) {
    paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
  }

  Offset start;
  Offset end;
  final double strokeWidth;
  late Paint paint;

  @override
  void translate(Offset delta) {
    start += delta;
    end += delta;
  }

  @override
  void draw(Canvas canvas, Size size) {
    // Set the paint color
    paint.color = color;

    // Define arrow parameters
    const double arrowLength = 15.0; // Length from arrow tip to the base center
    const double arrowWidth = 12.0; // Maximum width of the arrow tip

    // Calculate the angle of the line's direction
    final double angle = (end - start).direction;

    // Adjust the endpoint so that the arrow head does not extend beyond the target point
    final Offset adjustedEnd = end -
        Offset(
          arrowLength * cos(angle),
          arrowLength * sin(angle),
        );

    // Draw the main line from the start to the adjusted endpoint
    canvas.drawLine(start, adjustedEnd, paint);

    // Draw a solid circle at the start point (arrow tail)
    // The diameter is set to half of the arrow tip's width, so the radius is arrowWidth/4
    final Paint circlePaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(start, arrowWidth / 4, circlePaint);

    // Calculate a perpendicular vector to the line's direction
    final Offset perpendicular = Offset(-sin(angle), cos(angle));

    // Determine the two base points of the arrow head using the perpendicular vector
    final Offset arrowBaseLeft =
        adjustedEnd + (perpendicular * (arrowWidth / 2));
    final Offset arrowBaseRight =
        adjustedEnd - (perpendicular * (arrowWidth / 2));

    // Construct a filled triangle for the arrow head with its tip at the target point
    final Path arrowPath = Path()
      ..moveTo(end.dx, end.dy) // Arrow tip exactly at the target point
      ..lineTo(arrowBaseLeft.dx, arrowBaseLeft.dy)
      ..lineTo(arrowBaseRight.dx, arrowBaseRight.dy)
      ..close();

    // Use a paint with fill style for the arrow head to ensure a solid triangle
    final Paint arrowPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;

    // Draw the filled arrow head
    canvas.drawPath(arrowPath, arrowPaint);
  }

  @override
  bool hitTest(Offset tapPosition) {
    final AnnotationLine line = AnnotationLine(
      start: start,
      end: end,
      color: color,
      strokeWidth: strokeWidth,
    );
    return line.hitTest(tapPosition);
  }
}

class AnnotationRect extends AnnotationShape {
  AnnotationRect({
    required this.start,
    required this.end,
    required Color color,
    this.strokeWidth = 3.0,
  }) : super(color: color) {
    paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
  }

  Offset start;
  Offset end;
  final double strokeWidth;
  late Paint paint;

  @override
  void translate(Offset delta) {
    start += delta;
    end += delta;
  }

  @override
  void draw(Canvas canvas, Size size) {
    paint.color = color;
    canvas.drawRect(Rect.fromPoints(start, end), paint);
  }

  @override
  bool hitTest(Offset tapPosition) {
    final Rect rect = Rect.fromPoints(start, end).inflate(5);
    return rect.contains(tapPosition);
  }
}

class AnnotationDot extends AnnotationShape {
  AnnotationDot({
    required this.point,
    required super.color,
    this.radius = 4.0,
  });

  Offset point;
  double radius;

  @override
  void translate(Offset delta) {
    point += delta;
  }

  @override
  void draw(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(point, radius, paint);
  }

  @override
  bool hitTest(Offset tapPosition) {
    final double dist = (tapPosition - point).distance;
    return dist <= radius + 5.0;
  }
}

class AnnotationCross extends AnnotationShape {
  AnnotationCross({
    required this.point,
    required super.color,
    this.crossSize = 8.0,
    this.strokeWidth = 3.0,
  });

  /// The center point of the cross.
  Offset point;

  /// Half the length of each diagonal line.
  double crossSize;

  /// The stroke width for drawing the cross.
  final double strokeWidth;

  @override
  void translate(Offset delta) {
    point += delta;
  }

  @override
  void draw(Canvas canvas, Size size) {
    // Create a paint object with stroke style for drawing the cross.
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    // Calculate the endpoints for the two diagonals to form an 'X'.
    final Offset topLeft = Offset(point.dx - crossSize, point.dy - crossSize);
    final Offset bottomRight =
        Offset(point.dx + crossSize, point.dy + crossSize);
    final Offset topRight = Offset(point.dx + crossSize, point.dy - crossSize);
    final Offset bottomLeft =
        Offset(point.dx - crossSize, point.dy + crossSize);

    // Draw the two diagonal lines to form an "X".
    canvas.drawLine(topLeft, bottomRight, paint);
    canvas.drawLine(topRight, bottomLeft, paint);
  }

  @override
  bool hitTest(Offset tapPosition) {
    // Define a bounding box around the cross for hit testing.
    final double halfSize = crossSize + 5.0;
    final Rect bbox = Rect.fromCenter(
      center: point,
      width: halfSize * 2,
      height: halfSize * 2,
    );
    return bbox.contains(tapPosition);
  }
}

class AnnotationText extends AnnotationShape {
  AnnotationText({
    required this.point,
    required this.text,
    required super.color,
    this.fontSize = 16.0,
  });

  // The point now represents the center of the text.
  Offset point;
  String text;
  final double fontSize;

  @override
  void translate(Offset delta) {
    point += delta;
  }

  @override
  void draw(Canvas canvas, Size size) {
    // Create a TextSpan with the desired style.
    final TextSpan span = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
      ),
    );
    // Layout the text to measure its dimensions.
    final TextPainter tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    );
    tp.layout();

    // Calculate the offset to draw the text so that it is centered at 'point'.
    final Offset drawOffset = point - Offset(tp.width / 2, tp.height / 2);

    // Paint the text at the computed offset.
    tp.paint(canvas, drawOffset);
  }

  @override
  bool hitTest(Offset tapPosition) {
    // Create a TextSpan with the desired style.
    final TextSpan span = TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: fontSize),
    );
    // Layout the text to measure its dimensions.
    final TextPainter tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    );
    tp.layout();

    // Define the bounding box with the text centered at 'point'.
    final Rect bbox = Rect.fromCenter(
      center: point,
      width: tp.width,
      height: tp.height,
    ).inflate(5);

    // Return true if the tap position falls within the bounding box.
    return bbox.contains(tapPosition);
  }
}

// ---------------------------------------------------------------------------
// AnnotationCommand / Undo-Redo
// ---------------------------------------------------------------------------

enum AnnotationCommandType {
  addShape,
  removeShape,
  changeColor,
  changeText,
  moveText,
  translateShape,
}

class AnnotationCommand {
  AnnotationCommand({
    required this.type,
    required this.shape,
    this.oldColor,
    this.newColor,
    this.oldText,
    this.newText,
    this.oldOffset,
    this.newOffset,
    this.delta,
    required this.manager,
  });

  final AnnotationCommandType type;
  final AnnotationShape shape;
  final Color? oldColor;
  final Color? newColor;
  final String? oldText;
  final String? newText;
  final Offset? oldOffset;
  final Offset? newOffset;
  final Offset? delta; // Offset by which the shape was translated
  final AnnotationManager manager;

  void redo() {
    switch (type) {
      case AnnotationCommandType.addShape:
        manager.shapes.add(shape);
        break;
      case AnnotationCommandType.removeShape:
        manager.shapes.remove(shape);
        break;
      case AnnotationCommandType.changeColor:
        if (newColor != null) {
          shape.color = newColor!;
        }
        break;
      case AnnotationCommandType.changeText:
        if (shape is AnnotationText && newText != null) {
          (shape as AnnotationText).text = newText!;
        }
        break;
      case AnnotationCommandType.moveText:
        if (shape is AnnotationText && newOffset != null) {
          (shape as AnnotationText).point = newOffset!;
        }
        break;
      case AnnotationCommandType.translateShape:
        if (delta != null) {
          shape.translate(delta!);
        }
        break;
    }
  }

  void undo() {
    switch (type) {
      case AnnotationCommandType.addShape:
        manager.shapes.remove(shape);
        break;
      case AnnotationCommandType.removeShape:
        manager.shapes.add(shape);
        break;
      case AnnotationCommandType.changeColor:
        if (oldColor != null) {
          shape.color = oldColor!;
        }
        break;
      case AnnotationCommandType.changeText:
        if (shape is AnnotationText && oldText != null) {
          (shape as AnnotationText).text = oldText!;
        }
        break;
      case AnnotationCommandType.moveText:
        if (shape is AnnotationText && oldOffset != null) {
          (shape as AnnotationText).point = oldOffset!;
        }
        break;
      case AnnotationCommandType.translateShape:
        if (delta != null) {
          shape.translate(-delta!); // Reverse the translation
        }
        break;
    }
  }
}

// ---------------------------------------------------------------------------
// Manager
// ---------------------------------------------------------------------------

class AnnotationManager extends ChangeNotifier {
  static const int maxHistorySteps = 200;
  bool snapToBoard = true;

  final List<AnnotationShape> shapes = <AnnotationShape>[];

  AnnotationShape? _currentDrawingShape;

  AnnotationShape? get currentDrawingShape => _currentDrawingShape;

  final List<AnnotationCommand> _undoStack = <AnnotationCommand>[];
  final List<AnnotationCommand> _redoStack = <AnnotationCommand>[];

  // Set the default tool to circle (third button) instead of line.
  AnnotationTool currentTool = AnnotationTool.circle;
  Color currentColor = Colors.red;

  AnnotationShape? _selectedShape;

  AnnotationShape? get selectedShape => _selectedShape;

  // -------------------------------------------------------------------------
  // Public APIs
  // -------------------------------------------------------------------------

  /// Translates the given [shape] by [delta] and records the action for undo/redo.
  void translateShape(AnnotationShape shape, Offset delta) {
    if (!shapes.contains(shape)) {
      return;
    }
    shape.translate(delta);
    _redoStack.clear();
    _pushUndoCommand(
      AnnotationCommand(
        type: AnnotationCommandType.translateShape,
        shape: shape,
        delta: delta,
        manager: this,
      ),
    );
    notifyListeners();
  }

  void selectShape(AnnotationShape? shape) {
    _selectedShape = shape;
    notifyListeners();
  }

  void clearSelection() {
    _selectedShape = null;
    notifyListeners();
  }

  void setCurrentDrawingShape(AnnotationShape? shape) {
    _currentDrawingShape = shape;
    notifyListeners();
  }

  void addShape(AnnotationShape shape) {
    shapes.add(shape);
    _redoStack.clear();
    _pushUndoCommand(
      AnnotationCommand(
        type: AnnotationCommandType.addShape,
        shape: shape,
        manager: this,
      ),
    );
    notifyListeners();
  }

  void removeShape(AnnotationShape shape) {
    if (shapes.remove(shape)) {
      _redoStack.clear();
      _pushUndoCommand(
        AnnotationCommand(
          type: AnnotationCommandType.removeShape,
          shape: shape,
          manager: this,
        ),
      );
      notifyListeners();
    }
  }

  void changeColor(AnnotationShape shape, Color newColor) {
    if (!shapes.contains(shape)) {
      return;
    }
    final Color oldColor = shape.color;
    shape.color = newColor;
    _redoStack.clear();
    _pushUndoCommand(
      AnnotationCommand(
        type: AnnotationCommandType.changeColor,
        shape: shape,
        oldColor: oldColor,
        newColor: newColor,
        manager: this,
      ),
    );
    notifyListeners();
  }

  void changeText(AnnotationText shape, String newText) {
    final String oldText = shape.text;
    shape.text = newText;
    _redoStack.clear();
    _pushUndoCommand(
      AnnotationCommand(
        type: AnnotationCommandType.changeText,
        shape: shape,
        oldText: oldText,
        newText: newText,
        manager: this,
      ),
    );
    notifyListeners();
  }

  void moveText(AnnotationText shape, Offset oldOffset, Offset newOffset) {
    shape.point = newOffset;
    _redoStack.clear();
    _pushUndoCommand(
      AnnotationCommand(
        type: AnnotationCommandType.moveText,
        shape: shape,
        oldOffset: oldOffset,
        newOffset: newOffset,
        manager: this,
      ),
    );
    notifyListeners();
  }

  void clear() {
    shapes.clear();
    _currentDrawingShape = null;
    _undoStack.clear();
    _redoStack.clear();
    _selectedShape = null;
    notifyListeners();
  }

  void undo() {
    if (_undoStack.isNotEmpty) {
      final AnnotationCommand cmd = _undoStack.removeLast();
      cmd.undo();
      _redoStack.add(cmd);
      notifyListeners();
    }
  }

  void redo() {
    if (_redoStack.isNotEmpty) {
      final AnnotationCommand cmd = _redoStack.removeLast();
      cmd.redo();
      _undoStack.add(cmd);
      notifyListeners();
    }
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  void _pushUndoCommand(AnnotationCommand cmd) {
    _undoStack.add(cmd);
    if (_undoStack.length > maxHistorySteps) {
      _undoStack.removeAt(0);
    }
  }
}

// ---------------------------------------------------------------------------
// Painters
// ---------------------------------------------------------------------------

/// A CustomPainter that draws all shapes from AnnotationManager.
/// It also highlights the selected shape and draws currentDrawingShape if any.
class AnnotationPainter extends CustomPainter {
  const AnnotationPainter(this.manager);

  final AnnotationManager manager;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw committed shapes
    for (final AnnotationShape shape in manager.shapes) {
      shape.draw(canvas, size);
      if (shape == manager.selectedShape) {
        _drawHighlight(canvas, shape);
      }
    }
    // Draw in-progress shape
    final AnnotationShape? temp = manager.currentDrawingShape;
    if (temp != null) {
      temp.draw(canvas, size);
    }
  }

  void _drawHighlight(Canvas canvas, AnnotationShape shape) {
    final Paint p = Paint()
      ..color = Colors.yellow.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    // Highlight the bounding region of the shape.
    if (shape is AnnotationCircle) {
      canvas.drawCircle(shape.center, shape.radius + 5, p);
    } else if (shape is AnnotationLine) {
      final Rect r = Rect.fromPoints(shape.start, shape.end).inflate(5);
      canvas.drawRect(r, p);
    } else if (shape is AnnotationArrow) {
      final Rect r = Rect.fromPoints(shape.start, shape.end).inflate(5);
      canvas.drawRect(r, p);
    } else if (shape is AnnotationRect) {
      final Rect r = Rect.fromPoints(shape.start, shape.end).inflate(5);
      canvas.drawRect(r, p);
    } else if (shape is AnnotationDot) {
      canvas.drawCircle(shape.point, shape.radius + 5, p);
    } else if (shape is AnnotationCross) {
      final double extent = shape.crossSize + 5.0;
      final Rect r = Rect.fromCenter(
        center: shape.point,
        width: extent * 2,
        height: extent * 2,
      );
      canvas.drawRect(r, p);
    } else if (shape is AnnotationText) {
      final TextSpan span = TextSpan(
        text: shape.text,
        style: TextStyle(color: shape.color, fontSize: shape.fontSize),
      );
      final TextPainter tp =
          TextPainter(text: span, textDirection: TextDirection.ltr);
      tp.layout();
      final Rect r = Rect.fromLTWH(
        shape.point.dx,
        shape.point.dy,
        tp.width,
        tp.height,
      ).inflate(5);
      canvas.drawRect(r, p);
    }
  }

  @override
  bool shouldRepaint(AnnotationPainter oldDelegate) => true;
}

// ---------------------------------------------------------------------------
// AnnotationOverlay with context menu for deletion on long-press
// ---------------------------------------------------------------------------

/// AnnotationOverlay with gesture detection to support drawing shapes,
/// strictly snapping them to the board intersections.
/// Only long-press selection is kept (for deletion); single-tap selection is removed.
class AnnotationOverlay extends StatefulWidget {
  const AnnotationOverlay({
    super.key,
    required this.annotationManager,
    required this.child,
    required this.gameBoardKey,
  });

  final AnnotationManager annotationManager;
  final Widget child;
  final GlobalKey gameBoardKey;

  @override
  State<AnnotationOverlay> createState() => _AnnotationOverlayState();
}

class _AnnotationOverlayState extends State<AnnotationOverlay> {
  /// Two-tap tracking for line, arrow, and rect tools.
  Offset? _firstTapPosition;

  /// The piece width (diameter) used to set forced sizes on shapes.
  double get _pieceWidth {
    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) {
      // Handle the null or unexpected type case, e.g., return a default value.
      return 0;
    }
    final RenderBox box = renderObject;
    final Size overlaySize = box.size;
    return ((overlaySize.width - (AppTheme.boardPadding * 2)) *
            DB().displaySettings.pieceWidth /
            6) -
        1;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        // The board (or other content) underneath:
        widget.child,

        // Annotation overlay:
        Positioned.fill(
          child: GestureDetector(
            onTapDown: (TapDownDetails details) {
              final RenderBox box = context.findRenderObject()! as RenderBox;
              final Offset tapPos = box.globalToLocal(details.globalPosition);
              _handleTap(tapPos);
            },
            onLongPressStart: (LongPressStartDetails details) {
              _handleLongPressStart(details);
            },
            child: AnimatedBuilder(
              animation: widget.annotationManager,
              builder: (BuildContext context, _) {
                return CustomPaint(
                  painter: AnnotationPainter(widget.annotationManager),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Single Tap Logic
  // --------------------------------------------------------------------------
  //
  // Only shape creation remains. Two-tap creation is used for line/arrow/rect,
  // while circle/dot/cross/text are created with a single tap.
  void _handleTap(Offset tapPos) {
    final AnnotationTool currentTool = widget.annotationManager.currentTool;
    final Color currentColor = widget.annotationManager.currentColor;

    // Conditionally snap the tap position based on the tool.
    Offset pos;
    if (currentTool == AnnotationTool.rect) {
      pos = tapPos; // No snapping for the rectangle tool.
    } else {
      pos = _snapToBoardIntersection(tapPos); // Snap for other tools.
    }

    // Switch based on the current tool.
    switch (currentTool) {
      case AnnotationTool.dot:
        _createDot(pos, currentColor);
        break;
      case AnnotationTool.cross:
        _createCross(pos, currentColor);
        break;
      case AnnotationTool.text:
        _createTextAt(pos, currentColor);
        break;
      case AnnotationTool.line:
      case AnnotationTool.arrow:
      case AnnotationTool.rect:
        // Lines, arrows, and rectangles are created via two taps.
        _handleTwoTapTool(pos, currentTool, currentColor);
        break;
      case AnnotationTool.circle:
        _createCircle(pos, currentColor);
        break;
      case AnnotationTool.move:
        // Do nothing for the 'move' tool on single taps (disabled).
        break;
    }

    setState(() {});
  }

  /// Snaps [overlayLocalTap] to the nearest board intersection.
  Offset _snapToBoardIntersection(Offset overlayLocalTap) {
    // Attempt to get the board's RenderBox.
    final RenderObject? ro =
        widget.gameBoardKey.currentContext?.findRenderObject();
    if (ro is! RenderBox) {
      logger.w('GameBoard RenderBox is not available. Using original tap.');
      return overlayLocalTap;
    }
    final RenderBox boardBox = ro;

    // Convert overlay-local tap to board-local coordinates.
    final RenderBox overlayBox = context.findRenderObject()! as RenderBox;
    final Offset globalTapPos = overlayBox.localToGlobal(overlayLocalTap);
    final Offset boardLocalTap = boardBox.globalToLocal(globalTapPos);
    final Size boardSize = boardBox.size;

    // Find the closest intersection from `points`.
    Offset bestBoardLocal = boardLocalTap;
    double minDistance = double.infinity;
    for (final Offset boardLogicalPoint in points) {
      final Offset candidate = offsetFromPoint(boardLogicalPoint, boardSize);
      final double dist = (candidate - boardLocalTap).distance;
      if (dist < minDistance) {
        minDistance = dist;
        bestBoardLocal = candidate;
      }
    }

    // Convert back to overlay-local coordinates.
    final Offset snappedGlobal = boardBox.localToGlobal(bestBoardLocal);
    final Offset snappedOverlayLocal = overlayBox.globalToLocal(snappedGlobal);
    return snappedOverlayLocal;
  }

  // --------------------------------------------------------------------------
  // Long Press Logic
  // --------------------------------------------------------------------------
  //
  // Long-press is used to select a shape for deletion via a context menu.
  void _handleLongPressStart(LongPressStartDetails details) {
    final RenderBox box = context.findRenderObject()! as RenderBox;
    final Offset localPos = box.globalToLocal(details.globalPosition);

    final AnnotationShape? shape = _hitTestShape(localPos);
    if (shape == null) {
      return;
    }

    // On long press, select the shape.
    widget.annotationManager.selectShape(shape);

    final RenderBox? overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlayBox == null) {
      logger.w('Overlay render object is null');
      return;
    }

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        overlayBox.size.width - details.globalPosition.dx,
        overlayBox.size.height - details.globalPosition.dy,
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'delete',
          child: Text(S.of(context).delete),
        ),
      ],
    ).then((String? selected) {
      if (selected == 'delete') {
        widget.annotationManager.removeShape(shape);
        setState(() {});
      }
    });
  }

  /// Returns the topmost shape that contains [tapPos].
  AnnotationShape? _hitTestShape(Offset tapPos) {
    final List<AnnotationShape> shapes = widget.annotationManager.shapes;
    for (int i = shapes.length - 1; i >= 0; i--) {
      if (shapes[i].hitTest(tapPos)) {
        return shapes[i];
      }
    }
    return null;
  }

  /// Creates a dot at the snapped position with a fixed radius.
  void _createDot(Offset point, Color color) {
    final double radius = _pieceWidth / 6; // For a small dot.
    final AnnotationDot shape =
        AnnotationDot(point: point, color: color, radius: radius);
    widget.annotationManager.addShape(shape);
  }

  /// Creates a cross at the snapped position with a bounding box equal to the piece diameter.
  void _createCross(Offset point, Color color) {
    final double crossSize = _pieceWidth / 2;
    final AnnotationCross shape = AnnotationCross(
      point: point,
      color: color,
      crossSize: crossSize,
    );
    widget.annotationManager.addShape(shape);
  }

  /// Creates a circle at the snapped position, using the piece radius.
  void _createCircle(Offset point, Color color) {
    final double forcedRadius = _pieceWidth / 2;
    final AnnotationCircle shape = AnnotationCircle(
      center: point,
      radius: forcedRadius,
      color: color,
    );
    widget.annotationManager.addShape(shape);
  }

  /// Prompts the user for text and creates an AnnotationText at the snapped position.
  Future<void> _createTextAt(Offset point, Color color) async {
    final TextEditingController controller = TextEditingController();

    final String? userText = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(S.of(context).addText),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: S.of(ctx).typeYourAnnotation,
          ),
          onSubmitted: (String val) => Navigator.pop(ctx, val),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(ctx).cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, controller.text);
            },
            child: Text(S.of(ctx).ok),
          ),
        ],
      ),
    );

    if (userText != null && userText.isNotEmpty) {
      final AnnotationText shape = AnnotationText(
        point: point,
        text: userText,
        color: color,
      );
      widget.annotationManager.addShape(shape);
    }
  }

  /// Handles two-tap tools (line, arrow, rect).
  void _handleTwoTapTool(Offset tapPos, AnnotationTool tool, Color color) {
    if (_firstTapPosition == null) {
      _firstTapPosition = tapPos;
    } else {
      final Offset start = _firstTapPosition!;
      final Offset end = tapPos;

      switch (tool) {
        case AnnotationTool.line:
          widget.annotationManager.addShape(
            AnnotationLine(start: start, end: end, color: color),
          );
          break;
        case AnnotationTool.arrow:
          widget.annotationManager.addShape(
            AnnotationArrow(start: start, end: end, color: color),
          );
          break;
        case AnnotationTool.rect:
          // Create a rectangle with the unsnapped start and end points.
          widget.annotationManager.addShape(
            AnnotationRect(start: start, end: end, color: color),
          );
          break;
        case AnnotationTool.circle:
        case AnnotationTool.dot:
        case AnnotationTool.cross:
        case AnnotationTool.text:
        case AnnotationTool.move:
          break;
      }

      _firstTapPosition = null;
    }
  }
}

/// Extension to transform an offset into a direction vector with a length of 1.
extension _OffsetDirection on Offset {}
