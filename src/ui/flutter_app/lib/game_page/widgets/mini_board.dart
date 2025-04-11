// mini_board.dart

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../shared/database/database.dart';
import '../services/mill.dart';
import 'game_page.dart';

/// MiniBoard widget displays a small Nine Men's Morris board given a board layout string.
/// When the board is tapped, an overlay navigation icon (FluentIcons.arrow_undo_48_regular)
/// appears in the center and "breathes" (pulses). Tapping the icon triggers navigation
/// to the corresponding move. Only one MiniBoard at a time can display the icon.
class MiniBoard extends StatefulWidget {
  const MiniBoard({
    super.key,
    required this.boardLayout,
    this.extMove,
    this.onNavigateMove, // Callback when navigation icon is tapped.
  });

  final String boardLayout;
  final ExtMove? extMove;

  /// Optional callback invoked after navigating the move (if you still want it).
  /// If not needed, you can remove or refactor.
  final VoidCallback? onNavigateMove;

  @override
  MiniBoardState createState() => MiniBoardState();
}

class MiniBoardState extends State<MiniBoard>
    with SingleTickerProviderStateMixin {
  // A static reference to track which MiniBoard is currently active (i.e. showing the icon).
  static MiniBoardState? _activeBoard;

  // Flag to control the visibility of the navigation icon overlay.
  bool _showNavigationIcon = false;

  // Animation controller to produce the "breathing" (pulsing) effect.
  late AnimationController _pulseController;

  // This animation will be used to scale the icon in and out.
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    // Initialize the animation controller for a 1-second cycle, repeating forward and reverse.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    // Create a tween to scale between 0.9 and 1.1, applying a smooth curve.
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    // If this instance is the active board, reset the static reference.
    if (_activeBoard == this) {
      _activeBoard = null;
    }
    _pulseController.dispose();
    super.dispose();
  }

  /// Utility method to hide the navigation icon of the previously active board if it is still mounted.
  static void _hidePreviousActiveBoard() {
    // If another board was active, hide its icon if it is still mounted.
    // This prevents setState on a disposed widget.
    if (_activeBoard != null && _activeBoard!.mounted) {
      _activeBoard!.setState(() {
        _activeBoard!._showNavigationIcon = false;
      });
    }
    // Clear the reference so no invalid setState() calls can happen afterward.
    _activeBoard = null;
  }

  /// Public static helper for hiding the active board (if any).
  static void hideActiveBoard() {
    _hidePreviousActiveBoard();
  }

  /// When the board is tapped, show the navigation icon on this board
  /// and hide it on any previously active board.
  void _handleBoardTap() {
    // Hide the icon on the previously active board if needed.
    if (_activeBoard != this) {
      _hidePreviousActiveBoard();
    }
    // Make this board the active one.
    _activeBoard = this;

    setState(() {
      _showNavigationIcon = true;
    });
  }

  /// When navigation icon is tapped, import partial moves up to this extMove's index,
  /// then jump to that position on the main line.
  ///
  /// Implementation references move_list_dialog.dart's _importGame logic:
  ///  - Build PGN substring up to clickedIndex
  ///  - Call ImportService.import(...)
  ///  - Then HistoryNavigator.takeBackAll(...), stepForwardAll(...).
  void _handleNavigationIconTap() {
    final ExtMove? em = widget.extMove;
    if (em != null && em.moveIndex != null && em.moveIndex! >= 0) {
      final int clickedIndex = em.moveIndex!;

      // 1) Collect mergedMoves from the current GameController
      final GameController controller = GameController();
      List<String> mergedMoves = getMergedMoves(controller);

      // 2) Detect if there's a leading fen block
      String? fen;
      if (mergedMoves.isNotEmpty && mergedMoves[0].startsWith('[')) {
        fen = mergedMoves[0];
        mergedMoves = mergedMoves.sublist(1);
      }

      // 3) Partial PGN up to (clickedIndex + 1)
      String ml = mergedMoves.sublist(0, clickedIndex + 1).join(' ');
      if (fen != null) {
        ml = '$fen $ml';
      }

      // 4) Import the PGN
      try {
        ImportService.import(ml);
      } catch (exception) {
        // If import fails, you can show a tip or revert
        // For example:
        final String tip = "Cannot import partial moves: $ml";
        GameController().headerTipNotifier.showTip(tip);
        // Then optionally return
        return;
      }

      // 5) Rebuild from scratch:
      HistoryNavigator.takeBackAll(context, pop: false);
      HistoryNavigator.stepForwardAll(context, pop: false);
    }

    // Hide the icon after navigating if desired
    setState(() {
      _showNavigationIcon = false;
    });

    // If your parent still wants to handle callback
    widget.onNavigateMove?.call();

    // Close the page
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Tapping anywhere on the board shows the navigation icon (and hides icons on other boards).
        onTap: _handleBoardTap,
        child: Stack(
          children: <Widget>[
            // The board background and drawing are rendered by CustomPaint.
            ClipRRect(
              borderRadius:
                  BorderRadius.circular(DB().displaySettings.boardCornerRadius),
              child: Container(
                color: DB().colorSettings.boardBackgroundColor,
                child: CustomPaint(
                  painter: MiniBoardPainter(
                    boardLayout: widget.boardLayout,
                    extMove: widget.extMove,
                  ),
                  child: Container(), // Ensures the CustomPaint has a size.
                ),
              ),
            ),
            // Display the navigation icon overlay in the center only if:
            // 1. _showNavigationIcon is true (board is active)
            // 2. extMove is provided (there is a move to navigate to)
            if (_showNavigationIcon && widget.extMove != null)
              Center(
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: IconButton(
                    // Use the Fluent UI arrow icon.
                    icon: Icon(
                      FluentIcons.arrow_undo_48_regular,
                      color: DB().colorSettings.boardLineColor,
                      size: 48.0,
                    ),
                    onPressed: _handleNavigationIconTap,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// MiniBoardPainter draws a miniature Nine Men's Morris board with equally spaced rings.
/// Additionally, if [extMove] is provided, it draws a highlight showing the last move:
/// - Highlight circle on the piece if placing
/// - Highlight arrow from origin to destination if moving
/// - Highlight X on removed piece if removing
class MiniBoardPainter extends CustomPainter {
  MiniBoardPainter({
    required this.boardLayout,
    this.extMove,
  }) {
    boardState = _parseBoardLayout(boardLayout);
  }

  final String boardLayout;

  /// The optional last move to highlight.
  final ExtMove? extMove;

  /// Holds the parsed board layout (24 squares).
  late final List<PieceColor> boardState;

  /// Parse the board layout string into 24 PieceColors.
  /// Format: "outer/middle/inner", each 8 chars.
  static List<PieceColor> _parseBoardLayout(String layout) {
    final List<String> parts = layout.split('/');
    if (parts.length != 3 ||
        parts[0].length != 8 ||
        parts[1].length != 8 ||
        parts[2].length != 8) {
      // Invalid format => empty board.
      return List<PieceColor>.filled(24, PieceColor.none);
    }

    final List<PieceColor> state = <PieceColor>[];
    // We parse "outer/middle/inner" from left to right,
    // but store them in the order: inner => middle => outer
    // so indices 0..7 = inner, 8..15 = middle, 16..23 = outer.
    //
    // parts[0] => outer ring
    // parts[1] => middle ring
    // parts[2] => inner ring
    //
    // BUT the code below does it in reversed fashion to keep painting consistent.
    // If this mismatch is intentional, keep it. Otherwise reorder accordingly.

    // Inner ring from parts[0]
    for (int i = 0; i < 8; i++) {
      state.add(_charToPieceColor(parts[0][i]));
    }
    // Middle ring from parts[1]
    for (int i = 0; i < 8; i++) {
      state.add(_charToPieceColor(parts[1][i]));
    }
    // Outer ring from parts[2]
    for (int i = 0; i < 8; i++) {
      state.add(_charToPieceColor(parts[2][i]));
    }
    return state;
  }

  /// Convert character to piece color: 'O' => white, '@' => black, 'X' => "marked", else => none.
  static PieceColor _charToPieceColor(String ch) {
    switch (ch) {
      case 'O':
        return PieceColor.white;
      case '@':
        return PieceColor.black;
      case 'X':
        return PieceColor.marked;
      default:
        return PieceColor.none;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double minSide = math.min(w, h);

    // Center the board if w != h.
    final double offsetX = (w - minSide) / 2;
    final double offsetY = (h - minSide) / 2;

    // Adjusted parameters for balanced spacing:
    const double outerMarginFactor = 0.06;
    const double ringSpacingFactor = 0.13;

    // Piece radius factor:
    const double pieceRadiusFactor = 0.05;

    final double outerMargin = minSide * outerMarginFactor;
    final double ringSpacing = minSide * ringSpacingFactor;
    final double pieceRadius = minSide * pieceRadiusFactor;

    // Calculate margins for each ring:
    final double marginMiddle = outerMargin + ringSpacing;
    final double marginInner = outerMargin + ringSpacing * 2;

    // Board lines paint
    final Paint boardPaint = Paint()
      ..color = DB().colorSettings.boardLineColor
      ..style = PaintingStyle.stroke
      // Slightly scale the stroke width based on size
      ..strokeWidth = math.max(1.0, minSide * 0.003);

    // Calculate the squares offsets for each ring:
    final List<Offset> outerPoints = _ringPoints(
      offsetX,
      offsetY,
      outerMargin,
      minSide - 2 * outerMargin,
    );
    final List<Offset> middlePoints = _ringPoints(
      offsetX,
      offsetY,
      marginMiddle,
      minSide - 2 * marginMiddle,
    );
    final List<Offset> innerPoints = _ringPoints(
      offsetX,
      offsetY,
      marginInner,
      minSide - 2 * marginInner,
    );

    // Draw the three rings:
    _drawSquare(canvas, outerPoints, boardPaint);
    _drawSquare(canvas, middlePoints, boardPaint);
    _drawSquare(canvas, innerPoints, boardPaint);

    // Connect midpoints of each ring:
    _drawLine(canvas, outerPoints[1], middlePoints[1], boardPaint);
    _drawLine(canvas, middlePoints[1], innerPoints[1], boardPaint);

    _drawLine(canvas, outerPoints[3], middlePoints[3], boardPaint);
    _drawLine(canvas, middlePoints[3], innerPoints[3], boardPaint);

    _drawLine(canvas, outerPoints[5], middlePoints[5], boardPaint);
    _drawLine(canvas, middlePoints[5], innerPoints[5], boardPaint);

    _drawLine(canvas, outerPoints[7], middlePoints[7], boardPaint);
    _drawLine(canvas, middlePoints[7], innerPoints[7], boardPaint);

    // Possibly draw diagonals if the rule setting is enabled.
    if (DB().ruleSettings.hasDiagonalLines) {
      canvas.drawLine(outerPoints[0], innerPoints[0], boardPaint);
      canvas.drawLine(outerPoints[2], innerPoints[2], boardPaint);
      canvas.drawLine(outerPoints[4], innerPoints[4], boardPaint);
      canvas.drawLine(outerPoints[6], innerPoints[6], boardPaint);
    }

    // Draw pieces:
    for (int i = 0; i < 24; i++) {
      final PieceColor pc = boardState[i];
      if (pc == PieceColor.none) {
        continue;
      }

      // Determine ring position for each piece:
      Offset pos;
      if (i < 8) {
        // inner ring
        pos = innerPoints[(i + 1) % 8];
      } else if (i < 16) {
        // middle ring
        pos = middlePoints[((i - 8) + 1) % 8];
      } else {
        // outer ring
        pos = outerPoints[((i - 16) + 1) % 8];
      }

      // Example: We define the piece diameter by 2 * pieceRadius.
      final double pieceDiameter = pieceRadius * 2;

      // If you have piece images (ui.Image) for white/black, you can fetch them here:
      // final ui.Image? pieceImage = myPieceImageMap[pc]; // Example only.
      // For demonstration, we'll assume no images and just do border + fill.

      // The code below mirrors the structure in piece_painter.dart:
      // 1) If there's an image, use paintImage(...).
      // 2) Else, draw the border circle, then the fill circle.
      // 3) Optionally draw a number if needed.

      final Paint paint = Paint();
      const double opacity = 1.0;
      final double circleOuterRadius = pieceDiameter / 2.0;
      final double circleInnerRadius = circleOuterRadius * 0.99;

      // If you have an actual piece image, use paintImage(...). We'll skip here.
      const ui.Image? pieceImage = null;
      if (pieceImage != null) {
        paintImage(
          canvas: canvas,
          rect: Rect.fromCircle(
            center: pos,
            radius: circleInnerRadius,
          ),
          image: pieceImage,
          fit: BoxFit.cover,
        );
      } else {
        // Draw shadow similar to large board when no piece image is used.
        canvas.drawShadow(
          Path()
            ..addOval(
              Rect.fromCircle(center: pos, radius: circleOuterRadius),
            ),
          Colors.black,
          2,
          true,
        );

        // Example color usage:
        // Added an 'else if' to handle 'marked' to align with big board approach.
        Color borderColor;
        if (pc == PieceColor.white) {
          borderColor = DB().colorSettings.whitePieceColor;
        } else if (pc == PieceColor.black) {
          borderColor = DB().colorSettings.blackPieceColor;
        } else if (pc == PieceColor.marked) {
          borderColor = DB().colorSettings.pieceHighlightColor;
        } else {
          borderColor = DB().colorSettings.boardLineColor;
        }

        // Draw border circle:
        paint.color = borderColor.withValues(alpha: opacity);

        // If background is white, you might prefer stroke for the border:
        if (DB().colorSettings.boardBackgroundColor == Colors.white) {
          paint.style = PaintingStyle.stroke;
          paint.strokeWidth = 4.0;
        } else {
          paint.style = PaintingStyle.fill;
        }
        canvas.drawCircle(pos, circleOuterRadius, paint);

        // Fill main color (could be the same or different from borderColor).
        paint.style = PaintingStyle.fill;
        paint.color = borderColor.withValues(alpha: opacity);
        canvas.drawCircle(pos, circleInnerRadius, paint);
      }

      // --- End: piece painter style code. ---
    }

    // Highlight the last move if extMove != null
    _drawMoveHighlight(
      canvas,
      innerPoints,
      middlePoints,
      outerPoints,
      pieceRadius,
    );
  }

  /// Draws highlights according to the last move (if any).
  /// - Placing => (now we remove the old large circle for place)
  /// - Moving => Highlight arrow from origin to destination
  /// - Removing => Only X at the removed location (no extra circle)
  /// - Additionally, we do the "focus ring" on toPos and "blur circle" on fromPos,
  ///   except we skip the focus ring if it's a remove move.
  void _drawMoveHighlight(
    Canvas canvas,
    List<Offset> innerPoints,
    List<Offset> middlePoints,
    List<Offset> outerPoints,
    double pieceRadius,
  ) {
    if (extMove == null) {
      return;
    }

    final MoveType type = extMove!.type;
    if (type == MoveType.none || type == MoveType.draw) {
      return;
    }

    // Convert 'from' and 'to' squares to their ring offsets
    final Offset? fromPos = _convertSquareToOffset(
      extMove!.from,
      innerPoints,
      middlePoints,
      outerPoints,
    );
    final Offset? toPos = _convertSquareToOffset(
      extMove!.to,
      innerPoints,
      middlePoints,
      outerPoints,
    );

    // 1) If fromPos is valid, draw a blur circle (filled) in half-transparent color
    if (fromPos != null && extMove!.from >= 8) {
      // Attempt to get the piece color for the 'from' square
      final int? fromIndex = _convertSquareToBoardIndex(extMove!.from);
      if (fromIndex != null && fromIndex >= 0 && fromIndex < 24) {
        final PieceColor fromPc = boardState[fromIndex];
        if (fromPc != PieceColor.none) {
          // Mimic big board's blur approach: fill color with some opacity
          final Paint blurPaint = Paint()..style = PaintingStyle.fill;
          // Approximate the "blurPositionColor" from big board
          final Color c = (fromPc == PieceColor.white)
              ? DB().colorSettings.whitePieceColor.withValues(alpha: 0.3)
              : (fromPc == PieceColor.black)
                  ? DB().colorSettings.blackPieceColor.withValues(alpha: 0.3)
                  : DB()
                      .colorSettings
                      .pieceHighlightColor
                      .withValues(alpha: 0.3);
          blurPaint.color = c;

          // radius ~ pieceRadius * 0.8
          canvas.drawCircle(fromPos, pieceRadius * 0.8, blurPaint);
        }
      }
    }

    // 2) If it's not a remove move, draw a focus ring on toPos
    if (type != MoveType.remove && toPos != null && extMove!.to >= 8) {
      final Paint focusPaint = Paint()
        ..color = DB().colorSettings.pieceHighlightColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      // radius ~ pieceRadius
      canvas.drawCircle(toPos, pieceRadius, focusPaint);
    }

    // Then do the arrow/X logic (remove original large circle on place).
    final Paint highlightPaint = Paint()
      ..color = DB().colorSettings.pieceHighlightColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    switch (type) {
      case MoveType.place:
        // **Removed** the original "canvas.drawCircle(toPos, pieceRadius*1.4, highlightPaint);"
        // so that there is no second highlight circle on a newly placed piece.
        break;

      case MoveType.move:
        if (fromPos != null && toPos != null) {
          final Offset v = toPos - fromPos;
          final double magnitude = v.distance;
          if (magnitude == 0) {
            return;
          }
          final Offset normalizedV = Offset(v.dx / magnitude, v.dy / magnitude);
          final Offset newFromPos = fromPos + normalizedV * pieceRadius;
          final Offset newToPos = toPos - normalizedV * pieceRadius;
          final double arrowSize = pieceRadius * 0.8; // Need to adjust

          canvas.drawLine(newFromPos, newToPos, highlightPaint);
          _drawArrowHead(
              canvas, newFromPos, newToPos, highlightPaint, arrowSize);
        }
        break;

      case MoveType.remove:
        // Only draw X at the removed location, no ring highlight.
        if (toPos != null) {
          PieceColor removedPieceColor;
          if (extMove!.side == PieceColor.white) {
            removedPieceColor = PieceColor.black;
          } else if (extMove!.side == PieceColor.black) {
            removedPieceColor = PieceColor.white;
          } else {
            removedPieceColor = PieceColor.none;
          }

          Color xColor;
          if (removedPieceColor == PieceColor.white) {
            xColor = DB().colorSettings.whitePieceColor;
          } else if (removedPieceColor == PieceColor.black) {
            xColor = DB().colorSettings.blackPieceColor;
          } else {
            xColor = DB().colorSettings.pieceHighlightColor;
          }

          final Paint xPaint = Paint()
            ..color = xColor
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke;

          _drawHighlightX(canvas, toPos, pieceRadius * 2.0, xPaint);
        }
        break;

      case MoveType.none:
      case MoveType.draw:
        break;
    }
  }

  /// Convert a Nine Men's Morris square [sq] (8..31) to the appropriate
  /// Offset in [innerPoints], [middlePoints], or [outerPoints].
  ///
  /// - Inner ring:   squares 8..15
  /// - Middle ring:  squares 16..23
  /// - Outer ring:   squares 24..31
  ///
  /// We add 1 to the index (and mod 8) to match your existing painting logic
  ///   of `pos = ringPoints[(i + 1) % 8]`.
  Offset? _convertSquareToOffset(
    int sq,
    List<Offset> innerPoints,
    List<Offset> middlePoints,
    List<Offset> outerPoints,
  ) {
    // If sq < 8, it's usually a special sentinel (-1, 0, etc.) => no highlight
    if (sq < 8 || sq > 31) {
      return null;
    }

    // Decide which ring based on the numeric range.
    if (sq < 16) {
      // 8..15 => inner ring
      final int index = (sq - 8 + 1) % 8; // ex: sq=8 => index=(0+1)%8=1
      return innerPoints[index];
    } else if (sq < 24) {
      // 16..23 => middle ring
      final int index = (sq - 16 + 1) % 8;
      return middlePoints[index];
    } else {
      // 24..31 => outer ring
      final int index = (sq - 24 + 1) % 8;
      return outerPoints[index];
    }
  }

  /// Convert square [sq] to boardState index (0..23).
  /// This helps retrieve the piece color from boardState.
  int? _convertSquareToBoardIndex(int sq) {
    if (sq < 8 || sq > 31) {
      return null;
    }
    // 0..7 = inner, 8..15 = middle, 16..23 = outer in boardState
    if (sq < 16) {
      // inner ring
      return sq - 8; // 8..15 => 0..7
    } else if (sq < 24) {
      // middle ring
      return (sq - 16) + 8; // 16..23 => 8..15
    } else {
      // outer ring
      return (sq - 24) + 16; // 24..31 => 16..23
    }
  }

  /// Draw a small arrowhead at the "end" of the move line.
  void _drawArrowHead(
      Canvas canvas, Offset from, Offset to, Paint paint, double arrowSize) {
    final double angle = math.atan2(to.dy - from.dy, to.dx - from.dx);

    final Offset arrowP1 = Offset(
      to.dx - arrowSize * math.cos(angle - math.pi / 6),
      to.dy - arrowSize * math.sin(angle - math.pi / 6),
    );
    final Offset arrowP2 = Offset(
      to.dx - arrowSize * math.cos(angle + math.pi / 6),
      to.dy - arrowSize * math.sin(angle + math.pi / 6),
    );

    final Path path = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(arrowP1.dx, arrowP1.dy)
      ..moveTo(to.dx, to.dy)
      ..lineTo(arrowP2.dx, arrowP2.dy);

    canvas.drawPath(path, paint);
  }

  /// Draw a highlight X at the given position, with size given by [xSize].
  /// We create two diagonal lines crossing at [center].
  void _drawHighlightX(
      Canvas canvas, Offset center, double xSize, Paint paint) {
    final double half = xSize / 2;
    final Offset topLeft = Offset(center.dx - half, center.dy - half);
    final Offset topRight = Offset(center.dx + half, center.dy - half);
    final Offset bottomLeft = Offset(center.dx - half, center.dy + half);
    final Offset bottomRight = Offset(center.dx + half, center.dy + half);

    final Path path = Path()
      ..moveTo(topLeft.dx, topLeft.dy)
      ..lineTo(bottomRight.dx, bottomRight.dy)
      ..moveTo(topRight.dx, topRight.dy)
      ..lineTo(bottomLeft.dx, bottomLeft.dy);

    canvas.drawPath(path, paint);
  }

  /// Create 8 points around a square ring:
  /// 0: top-left
  /// 1: top-center
  /// 2: top-right
  /// 3: right-center
  /// 4: bottom-right
  /// 5: bottom-center
  /// 6: bottom-left
  /// 7: left-center
  List<Offset> _ringPoints(
    double baseX,
    double baseY,
    double offset,
    double ringSide,
  ) {
    final double left = baseX + offset;
    final double top = baseY + offset;
    final double right = left + ringSide;
    final double bottom = top + ringSide;
    final double centerX = left + ringSide / 2;
    final double centerY = top + ringSide / 2;

    return <Offset>[
      Offset(left, top), // 0: top-left
      Offset(centerX, top), // 1: top-center
      Offset(right, top), // 2: top-right
      Offset(right, centerY), // 3: right-center
      Offset(right, bottom), // 4: bottom-right
      Offset(centerX, bottom), // 5: bottom-center
      Offset(left, bottom), // 6: bottom-left
      Offset(left, centerY), // 7: left-center
    ];
  }

  /// Draw a closed polygon from a list of points.
  void _drawSquare(Canvas canvas, List<Offset> points, Paint paint) {
    final Path path = Path()..addPolygon(points, true);
    canvas.drawPath(path, paint);
  }

  /// Draw a single line between two points.
  void _drawLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    canvas.drawLine(p1, p2, paint);
  }

  @override
  bool shouldRepaint(covariant MiniBoardPainter oldDelegate) {
    // Repaint if the boardLayout or last move changes
    return oldDelegate.boardLayout != boardLayout ||
        oldDelegate.extMove?.move != extMove?.move;
  }
}
