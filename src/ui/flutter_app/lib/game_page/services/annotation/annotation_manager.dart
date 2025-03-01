// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)
//
// annotation_manager.dart
//
// This file contains the annotation system for drawing shapes and text
// overlays on a board. It supports various shape types (line, arrow, circle,
// rectangle, dot, cross, text) and provides selection, highlighting,
// management, and dragging functionality via AnnotationManager.

import 'dart:math';

import 'package:flutter/material.dart';

import '../mill.dart'; // Provides Position, PieceColor, GameController
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
    this.strokeWidth = 2.0,
  }) : super(color: color) {
    paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
  }

  factory AnnotationCircle.fromPoints({
    required Offset start,
    required Offset end,
    required Color color,
    double strokeWidth = 2.0,
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
    this.strokeWidth = 2.0,
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
    this.strokeWidth = 2.0,
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
    paint.color = color;
    canvas.drawLine(start, end, paint);

    // Draw arrowhead
    const double arrowSize = 10.0;
    final double angle = (end - start).direction;
    final Offset arrowP1 = end -
        Offset(
          arrowSize * cos(angle - pi / 6),
          arrowSize * sin(angle - pi / 6),
        );
    final Offset arrowP2 = end -
        Offset(
          arrowSize * cos(angle + pi / 6),
          arrowSize * sin(angle + pi / 6),
        );
    canvas.drawLine(end, arrowP1, paint);
    canvas.drawLine(end, arrowP2, paint);
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
    this.strokeWidth = 2.0,
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
    this.strokeWidth = 2.0,
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

  Offset point;
  String text;
  final double fontSize;

  @override
  void translate(Offset delta) {
    point += delta;
  }

  @override
  void draw(Canvas canvas, Size size) {
    final TextSpan span = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
      ),
    );
    final TextPainter tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, point);
  }

  @override
  bool hitTest(Offset tapPosition) {
    final TextSpan span = TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: fontSize),
    );
    final TextPainter tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    final Rect bbox = Rect.fromLTWH(
      point.dx,
      point.dy,
      tp.width,
      tp.height,
    ).inflate(5);
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

  final List<AnnotationShape> shapes = <AnnotationShape>[];

  AnnotationShape? _currentDrawingShape;

  AnnotationShape? get currentDrawingShape => _currentDrawingShape;

  final List<AnnotationCommand> _undoStack = <AnnotationCommand>[];
  final List<AnnotationCommand> _redoStack = <AnnotationCommand>[];

  AnnotationTool currentTool = AnnotationTool.line;
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
    // Highlight bounding or shape region
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
// AnnotationOverlay
// ---------------------------------------------------------------------------

/// AnnotationOverlay with gesture detection to support drawing shapes
/// and moving them with snap-to-board logic.
class AnnotationOverlay extends StatefulWidget {
  const AnnotationOverlay({
    super.key,
    required this.annotationManager,
    required this.child,
  });

  final AnnotationManager annotationManager;
  final Widget child;

  @override
  State<AnnotationOverlay> createState() => _AnnotationOverlayState();
}

class _AnnotationOverlayState extends State<AnnotationOverlay> {
  /// If `_firstTapPosition` is null, the next tap we receive will become
  /// the "start" point for two-tap tools. If non-null, the next tap is the "end" point.
  Offset? _firstTapPosition;

  /// Tracks the starting position for moving a shape when the move tool is selected.
  Offset? _moveStartPosition;

  /// Distance threshold (in logical pixels) for snapping.
  /// If a tap is within this distance of a board feature, it will snap.
  static const double _snapThreshold = 20.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        // 1) The underlying content (the game board, etc.)
        widget.child,

        // 2) The overlay for annotations
        Positioned.fill(
          child: GestureDetector(
            onTapDown: (TapDownDetails details) {
              final RenderBox box = context.findRenderObject()! as RenderBox;
              final Offset tapPos = box.globalToLocal(details.globalPosition);

              // Call our handleTap logic
              _handleTap(tapPos);
            },
            child: CustomPaint(
              painter: AnnotationPainter(widget.annotationManager),
            ),
          ),
        ),
      ],
    );
  }

  /// Handles a single tap at [tapPos].
  /// - For move tool: First tap selects the shape, second tap moves it.
  /// - For other tools: Follows original drawing logic.
  void _handleTap(Offset tapPos) {
    final AnnotationTool currentTool = widget.annotationManager.currentTool;
    final Color currentColor = widget.annotationManager.currentColor;

    // Snap the tap position before doing anything else
    final Offset snappedPos = _snapToBoardFeatures(tapPos, _snapThreshold);

    // Check if the tap hits an existing shape
    final AnnotationShape? maybeHitShape = _hitTestShape(snappedPos);
    if (maybeHitShape != null) {
      widget.annotationManager.selectShape(maybeHitShape);
      // If move tool is selected, record the tap position as the move start
      if (currentTool == AnnotationTool.move) {
        _moveStartPosition = snappedPos;
      } else {
        return; // For other tools, stop here after selection
      }
    } else {
      widget.annotationManager.clearSelection();
      if (currentTool == AnnotationTool.move) {
        _moveStartPosition = null;
      }
    }

    // Handle the move tool's second tap
    if (currentTool == AnnotationTool.move &&
        _moveStartPosition != null &&
        widget.annotationManager.selectedShape != null) {
      final Offset delta = snappedPos - _moveStartPosition!;
      widget.annotationManager.translateShape(
        widget.annotationManager.selectedShape!,
        delta,
      );
      widget.annotationManager.clearSelection();
      _moveStartPosition = null;
    } else {
      // Handle other tools
      switch (currentTool) {
        case AnnotationTool.dot:
          _createDot(snappedPos, currentColor);
          break;
        case AnnotationTool.cross:
          _createCross(snappedPos, currentColor);
          break;
        case AnnotationTool.text:
          _createTextAt(snappedPos, currentColor);
          break;
        case AnnotationTool.line:
        case AnnotationTool.arrow:
        case AnnotationTool.circle:
        case AnnotationTool.rect:
          _handleTwoTapTool(snappedPos, currentTool, currentColor);
          break;
        case AnnotationTool.move:
          // Already handled above
          break;
      }
    }

    setState(() {
      // Trigger redraw
    });
  }

  /// Detects if the user tapped on an existing shape for selection.
  AnnotationShape? _hitTestShape(Offset tapPos) {
    // Reverse iterate to select the topmost shape first
    final List<AnnotationShape> shapes = widget.annotationManager.shapes;
    for (int i = shapes.length - 1; i >= 0; i--) {
      if (shapes[i].hitTest(tapPos)) {
        return shapes[i];
      }
    }
    return null;
  }

  /// Creates a dot at the specified [point] with the given [color].
  void _createDot(Offset point, Color color) {
    final AnnotationDot shape = AnnotationDot(point: point, color: color);
    widget.annotationManager.addShape(shape);
  }

  /// Creates a cross at the specified [point] with the given [color].
  void _createCross(Offset point, Color color) {
    final AnnotationCross shape = AnnotationCross(point: point, color: color);
    widget.annotationManager.addShape(shape);
  }

  /// Creates a text annotation at the specified [point] with the given [color].
  Future<void> _createTextAt(Offset point, Color color) async {
    // Create a TextEditingController to manage the TextField's input
    final TextEditingController controller = TextEditingController();

    final String? userText = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text("Add Text"),
        content: TextField(
          controller: controller, // Attach the controller to the TextField
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "Type your annotation",
          ),
          onSubmitted: (String val) =>
              Navigator.pop(ctx, val), // Handles Enter key
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            // Cancel button exits without value
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              // Return the text from the controller when OK is pressed
              Navigator.pop(ctx, controller.text);
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );

    // Check if the returned text is valid and create the annotation
    if (userText != null && userText.isNotEmpty) {
      final AnnotationText shape = AnnotationText(
        point: point,
        text: userText,
        color: color,
      );
      widget.annotationManager.addShape(shape);
    }
  }

  /// Handles two-tap tools (line, arrow, circle, rect).
  /// - First tap sets start point.
  /// - Second tap sets end point and creates the shape.
  void _handleTwoTapTool(Offset tapPos, AnnotationTool tool, Color color) {
    if (_firstTapPosition == null) {
      _firstTapPosition = tapPos;
    } else {
      final Offset start = _firstTapPosition!;
      final Offset end = tapPos;

      switch (tool) {
        case AnnotationTool.line:
          final AnnotationLine shape =
              AnnotationLine(start: start, end: end, color: color);
          widget.annotationManager.addShape(shape);
          break;
        case AnnotationTool.arrow:
          final AnnotationArrow shape =
              AnnotationArrow(start: start, end: end, color: color);
          widget.annotationManager.addShape(shape);
          break;
        case AnnotationTool.circle:
          final AnnotationCircle shape = AnnotationCircle.fromPoints(
            start: start,
            end: end,
            color: color,
          );
          widget.annotationManager.addShape(shape);
          break;
        case AnnotationTool.rect:
          final AnnotationRect shape =
              AnnotationRect(start: start, end: end, color: color);
          widget.annotationManager.addShape(shape);
          break;
        case AnnotationTool.dot:
        case AnnotationTool.cross:
        case AnnotationTool.text:
        case AnnotationTool.move:
          break; // These are handled elsewhere
      }

      _firstTapPosition = null; // Reset for next shape
    }
  }

  /// Snaps the tap position to the nearest board feature or piece center.
  Offset _snapToBoardFeatures(Offset rawTapPos, double threshold) {
    Offset currentBest = rawTapPos;
    double currentMinDistance = double.infinity;

    final RenderBox box = context.findRenderObject()! as RenderBox;
    final Size overlaySize = box.size;

    // Snap to board intersections
    for (final Offset boardLogicalPoint in points) {
      final Offset boardScreenPoint =
          offsetFromPoint(boardLogicalPoint, overlaySize);
      final double dist = (boardScreenPoint - rawTapPos).distance;
      if (dist < currentMinDistance && dist < threshold) {
        currentMinDistance = dist;
        currentBest = boardScreenPoint;
      }
    }

    // Snap to piece centers
    final Position position = GameController().position;
    for (int row = 0; row < 7; row++) {
      for (int col = 0; col < 7; col++) {
        final int index = row * 7 + col;
        final PieceColor pieceColor = position.pieceOnGrid(index);
        if (pieceColor == PieceColor.none) {
          continue;
        }

        final Offset piecePos = pointFromIndex(index, overlaySize);
        final double dist = (piecePos - rawTapPos).distance;
        if (dist < currentMinDistance && dist < threshold) {
          currentMinDistance = dist;
          currentBest = piecePos;
        }
      }
    }

    return currentBest;
  }
}

/// Extension to transform an offset into a direction vector with length=1.
extension _OffsetDirection on Offset {}
