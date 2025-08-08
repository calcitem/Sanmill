// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// kids_board.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../appearance_settings/models/color_settings.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/services/kids_ui_service.dart';
import '../../shared/services/logger.dart';
import '../../shared/themes/kids_theme.dart';
import '../services/mill.dart';
import '../services/painters/painters.dart' as core;

// Use helpers from core board utils to guarantee consistency

/// Kids-friendly game board widget
/// Designed with larger touch areas, bright colors, and fun animations
class KidsBoard extends StatefulWidget {
  const KidsBoard({
    super.key,
    this.onMoveMade,
    this.onMillFormed,
  });

  /// Callback when a move is made
  final VoidCallback? onMoveMade;

  /// Callback when a mill is formed
  final VoidCallback? onMillFormed;

  @override
  State<KidsBoard> createState() => _KidsBoardState();
}

class _KidsBoardState extends State<KidsBoard> with TickerProviderStateMixin {
  static const String _logTag = "[kids_board]";

  // Animation controllers for fun effects
  late AnimationController _pulseController;
  late AnimationController _celebrationController;
  late Animation<double> _pulseAnimation;

  // Track the selected piece for visual feedback
  int? _selectedSquare;

  // Highlight possible moves for educational purposes
  List<int> _possibleMoves = <int>[];

  @override
  void initState() {
    super.initState();

    // Initialize pulse animation for selected pieces
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // Initialize celebration animation
    _celebrationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _celebrationController.dispose();
    super.dispose();
  }

  Future<void> _handleTap(Offset localPosition, double boardSize) async {
    // Calculate which square was tapped using Kids board layout
    final int? square = _computeSquareFromLocal(localPosition, boardSize);

    if (square == null) {
      logger.t("$_logTag Tap not on a valid square");
      return;
    }

    logger.t("$_logTag Tap on square <$square>");

    // Provide haptic feedback for kids
    HapticFeedback.lightImpact();

    // Use real game engine instead of simulation
    final TapHandler tapHandler = TapHandler(context: context);

    try {
      // Call the real game engine
      final EngineResponse response = await tapHandler.onBoardTap(square);

      // Process engine response with kid-friendly messages
      switch (response) {
        case EngineResponseOK():
          GameController().gameResultNotifier.showResult(force: true);
          // Only call onMoveMade for successful moves
          widget.onMoveMade?.call();
          break;
        case EngineResponseHumanOK():
          GameController().gameResultNotifier.showResult();
          // Only call onMoveMade for successful human moves
          widget.onMoveMade?.call();
          break;
        case EngineTimeOut():
          // Non-intrusive tip for timeout; no modal dialog
          GameController().headerTipNotifier.showTip('Timeout');
          break;
        case EngineNoBestMove():
          // Non-intrusive tip for invalid move; no modal dialog
          GameController().headerTipNotifier.showTip('Try a different move');
          break;
        case EngineGameIsOver():
          GameController().gameResultNotifier.showResult(force: true);
          // Game is over, show celebration but don't trigger new move celebration
          break;
        default:
          break;
      }
    } catch (e) {
      logger.e("$_logTag Error processing tap: $e");
      // Don't call onMoveMade for errors - no move was made
      GameController().headerTipNotifier.showTip("Let's try that again!");
    }

    // Update UI state for visual feedback
    setState(() {
      _selectedSquare = square;
      _possibleMoves = <int>[];
    });
  }

  // Convert a local tap position to engine square using Kids board geometry.
  // This matches the Kids painter layout (12% padding, inner 76%).
  int? _computeSquareFromLocal(Offset local, double boardSize) {
    // Temporarily align the core point conversion with Kids painter padding
    final double kidsPadding = boardSize * 0.12;
    final double oldPadding = AppTheme.boardPadding;
    AppTheme.boardPadding = kidsPadding;
    try {
      final Offset pt = core.pointFromOffset(local, boardSize);
      return core.squareFromPoint(pt);
    } finally {
      AppTheme.boardPadding = oldPadding;
    }
  }

  @override
  Widget build(BuildContext context) {
    final KidsUIService kidsUIService = KidsUIService.instance;
    final ColorSettings colorTheme =
        KidsTheme.kidsColorThemes[kidsUIService.currentKidsTheme]!;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double boardSize = math.min(
          constraints.maxWidth - 32, // Padding
          constraints.maxHeight - 32,
        );

        return Center(
          child: Container(
            width: boardSize,
            height: boardSize,
            decoration: BoxDecoration(
              color: colorTheme.boardBackgroundColor,
              borderRadius: BorderRadius.circular(24.0),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24.0),
              child: Stack(
                children: <Widget>[
                  // Board background pattern
                  CustomPaint(
                    size: Size(boardSize, boardSize),
                    painter: KidsBoardBackgroundPainter(colorTheme: colorTheme),
                  ),

                  // Game board and pieces
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (TapUpDetails details) {
                      _handleTap(details.localPosition, boardSize);
                    },
                    child: CustomPaint(
                      size: Size(boardSize, boardSize),
                      painter: KidsBoardPainter(
                        colorTheme: colorTheme,
                        selectedSquare: _selectedSquare,
                        possibleMoves: _possibleMoves,
                        pulseAnimation: _pulseAnimation,
                      ),
                      foregroundPainter: KidsPiecePainter(
                        colorTheme: colorTheme,
                        selectedSquare: _selectedSquare,
                        pulseAnimation: _pulseAnimation,
                      ),
                    ),
                  ),

                  // Celebration overlay (when mill is formed)
                  AnimatedBuilder(
                    animation: _celebrationController,
                    builder: (BuildContext context, Widget? child) {
                      if (_celebrationController.value == 0) {
                        return const SizedBox.shrink();
                      }

                      return Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: CelebrationPainter(
                              animation: _celebrationController.value,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Painter for the kids board background pattern
class KidsBoardBackgroundPainter extends CustomPainter {
  KidsBoardBackgroundPainter({required this.colorTheme});

  final ColorSettings colorTheme;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..style = PaintingStyle.fill;

    // Draw a fun pattern in the background
    final double patternSize = size.width / 10;
    paint.color = colorTheme.boardBackgroundColor.withOpacity(0.3);

    for (double x = 0; x < size.width; x += patternSize * 2) {
      for (double y = 0; y < size.height; y += patternSize * 2) {
        canvas.drawCircle(
          Offset(x + patternSize / 2, y + patternSize / 2),
          patternSize / 4,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Painter for the kids board lines and points
class KidsBoardPainter extends CustomPainter {
  KidsBoardPainter({
    required this.colorTheme,
    this.selectedSquare,
    this.possibleMoves = const <int>[],
    required this.pulseAnimation,
  });

  final ColorSettings colorTheme;
  final int? selectedSquare;
  final List<int> possibleMoves;
  final Animation<double> pulseAnimation;

  @override
  void paint(Canvas canvas, Size size) {
    assert(size.width == size.height);

    // Calculate board dimensions with extra padding for kids
    final double padding = size.width * 0.12; // Larger padding for kids
    final double innerSize = size.width - (padding * 2);

    // Create paint for board lines
    final Paint linePaint = Paint()
      ..color = colorTheme.boardLineColor
      ..strokeWidth = 4.0 // Thicker lines for kids
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round; // Rounded line ends

    // Get point positions
    final List<Offset> pointOffsets = core.points
        .map((Offset e) => Offset(
              padding + (e.dx / 6) * innerSize,
              padding + (e.dy / 6) * innerSize,
            ))
        .toList();

    // Draw board lines with fun style
    _drawBoardLines(canvas, pointOffsets, linePaint);

    // Draw points with kids-friendly style
    _drawBoardPoints(canvas, pointOffsets, size);

    // Highlight possible moves
    _drawPossibleMoves(canvas, pointOffsets);
  }

  void _drawBoardLines(Canvas canvas, List<Offset> points, Paint paint) {
    // Draw the three squares
    final List<List<int>> squares = <List<int>>[
      <int>[0, 1, 2, 14, 23, 22, 21, 9], // Outer square
      <int>[3, 4, 5, 13, 20, 19, 18, 10], // Middle square
      <int>[6, 7, 8, 12, 17, 16, 15, 11], // Inner square
    ];

    for (final List<int> square in squares) {
      final Path path = Path();
      path.moveTo(points[square[0]].dx, points[square[0]].dy);

      for (int i = 1; i < square.length; i++) {
        path.lineTo(points[square[i]].dx, points[square[i]].dy);
      }
      path.close();

      canvas.drawPath(path, paint);
    }

    // Draw connecting lines
    final List<List<int>> connections = <List<int>>[
      <int>[1, 4, 7], // Top vertical
      <int>[9, 10, 11], // Left horizontal
      <int>[12, 13, 14], // Right horizontal
      <int>[16, 19, 22], // Bottom vertical
    ];

    for (final List<int> connection in connections) {
      canvas.drawLine(
        points[connection[0]],
        points[connection[2]],
        paint,
      );
    }
  }

  void _drawBoardPoints(Canvas canvas, List<Offset> points, Size boardSize) {
    final Paint pointPaint = Paint()..style = PaintingStyle.fill;

    final double pointRadius =
        boardSize.width * 0.025; // Larger points for kids

    for (int i = 0; i < points.length; i++) {
      // Check if this point is selected
      final bool isSelected = i == selectedSquare;

      // Animated radius for selected point
      final double radius =
          isSelected ? pointRadius * pulseAnimation.value : pointRadius;

      // Different colors for interaction states
      if (isSelected) {
        // Selected point - bright and pulsing
        pointPaint.color = colorTheme.pieceHighlightColor;

        // Draw glow effect
        final Paint glowPaint = Paint()
          ..color = colorTheme.pieceHighlightColor.withOpacity(0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);

        canvas.drawCircle(points[i], radius * 1.5, glowPaint);
      } else if (possibleMoves.contains(i)) {
        // Possible move - highlighted
        pointPaint.color = Colors.green.shade400;
      } else {
        // Normal point
        pointPaint.color = colorTheme.boardLineColor.withOpacity(0.8);
      }

      // Draw the point
      canvas.drawCircle(points[i], radius, pointPaint);

      // Draw inner circle for better visibility
      if (!isSelected) {
        pointPaint.color = colorTheme.boardBackgroundColor;
        canvas.drawCircle(points[i], radius * 0.6, pointPaint);
      }
    }
  }

  void _drawPossibleMoves(Canvas canvas, List<Offset> points) {
    if (possibleMoves.isEmpty) {
      return;
    }

    final Paint highlightPaint = Paint()
      ..color = Colors.green.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    for (final int move in possibleMoves) {
      if (move < points.length) {
        canvas.drawCircle(
          points[move],
          20.0,
          highlightPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant KidsBoardPainter oldDelegate) =>
      oldDelegate.selectedSquare != selectedSquare ||
      oldDelegate.possibleMoves != possibleMoves;
}

/// Painter for the game pieces with kids-friendly design
class KidsPiecePainter extends CustomPainter {
  KidsPiecePainter({
    required this.colorTheme,
    this.selectedSquare,
    required this.pulseAnimation,
  });

  final ColorSettings colorTheme;
  final int? selectedSquare;
  final Animation<double> pulseAnimation;

  @override
  void paint(Canvas canvas, Size size) {
    // Get real game position instead of demo data
    final Map<int, PieceColor> currentPositions = <int, PieceColor>{};

    // Get actual pieces from game controller using public API
    for (int index = 0; index < core.points.length; index++) {
      final PieceColor piece = GameController().position.pieceOnGrid(index);
      if (piece != PieceColor.none) {
        currentPositions[index] = piece;
      }
    }

    // Calculate board dimensions
    final double padding = size.width * 0.12;
    final double innerSize = size.width - (padding * 2);
    final double pieceRadius = size.width * 0.045; // Larger pieces for kids

    // Draw pieces based on actual game state
    currentPositions.forEach((int pointIndex, PieceColor pieceColor) {
      if (pointIndex < core.points.length) {
        final Offset point = core.points[pointIndex];
        final Offset piecePos = Offset(
          padding + (point.dx / 6) * innerSize,
          padding + (point.dy / 6) * innerSize,
        );

        _drawKidsPiece(
          canvas,
          piecePos,
          pieceColor,
          pieceRadius,
          isSelected: pointIndex == selectedSquare,
        );
      }
    });

    // Draw selected square indicator if any
    if (selectedSquare != null && selectedSquare! < core.points.length) {
      final Offset point = core.points[selectedSquare!];
      final Offset selectedPos = Offset(
        padding + (point.dx / 6) * innerSize,
        padding + (point.dy / 6) * innerSize,
      );

      // Draw selection indicator (larger circle for kids)
      final Paint selectionPaint = Paint()
        ..color = colorTheme.pieceHighlightColor.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0;

      canvas.drawCircle(
        selectedPos,
        pieceRadius * 1.5,
        selectionPaint,
      );
    }
  }

  void _drawKidsPiece(
    Canvas canvas,
    Offset position,
    PieceColor pieceColor,
    double radius, {
    bool isSelected = false,
  }) {
    final Paint paint = Paint()..style = PaintingStyle.fill;

    // Animated radius for selected pieces
    final double actualRadius =
        isSelected ? radius * pulseAnimation.value : radius;

    // Base colors from theme
    final Color baseColor = pieceColor == PieceColor.white
        ? colorTheme.whitePieceColor
        : colorTheme.blackPieceColor;

    // Draw shadow for depth
    final Paint shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

    canvas.drawCircle(
      position + const Offset(2, 3),
      actualRadius,
      shadowPaint,
    );

    // Draw main piece with gradient for 3D effect
    final Rect rect = Rect.fromCircle(center: position, radius: actualRadius);
    paint.shader = RadialGradient(
      colors: <Color>[
        baseColor.withOpacity(0.9),
        baseColor,
        baseColor.withOpacity(0.7),
      ],
      stops: const <double>[0.0, 0.7, 1.0],
      center: const Alignment(-0.3, -0.3),
    ).createShader(rect);

    canvas.drawCircle(position, actualRadius, paint);

    // Draw highlight for glossy effect
    paint.shader = null;
    paint.color = Colors.white.withOpacity(0.3);

    final Path highlightPath = Path();
    highlightPath.addArc(
      Rect.fromCircle(
        center: position - Offset(actualRadius * 0.3, actualRadius * 0.3),
        radius: actualRadius * 0.6,
      ),
      -math.pi * 0.8,
      math.pi * 0.6,
    );

    canvas.drawPath(highlightPath, paint);

    // Draw smiley face on pieces for extra friendliness
    _drawSmileyFace(canvas, position, actualRadius * 0.7, pieceColor);
  }

  void _drawSmileyFace(
      Canvas canvas, Offset center, double size, PieceColor pieceColor) {
    final Paint facePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = pieceColor == PieceColor.white
          ? Colors.grey.shade700
          : Colors.white.withOpacity(0.8);

    // Eyes
    final double eyeOffset = size * 0.25;
    final double eyeRadius = size * 0.08;

    facePaint.style = PaintingStyle.fill;
    canvas.drawCircle(
      center + Offset(-eyeOffset, -eyeOffset * 0.5),
      eyeRadius,
      facePaint,
    );
    canvas.drawCircle(
      center + Offset(eyeOffset, -eyeOffset * 0.5),
      eyeRadius,
      facePaint,
    );

    // Smile
    facePaint.style = PaintingStyle.stroke;
    final Path smilePath = Path();
    final Rect smileRect = Rect.fromCenter(
      center: center + Offset(0, size * 0.1),
      width: size * 0.6,
      height: size * 0.4,
    );
    smilePath.addArc(smileRect, 0.2, math.pi - 0.4);

    canvas.drawPath(smilePath, facePaint);
  }

  @override
  bool shouldRepaint(covariant KidsPiecePainter oldDelegate) =>
      oldDelegate.selectedSquare != selectedSquare;
}

/// Painter for celebration effects when forming a mill
class CelebrationPainter extends CustomPainter {
  CelebrationPainter({required this.animation});

  final double animation;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint();
    final double progress = animation;

    // Draw expanding stars
    for (int i = 0; i < 8; i++) {
      final double angle = (i * math.pi * 2) / 8;
      final double distance = size.width * 0.3 * progress;

      final Offset starPos = Offset(
        size.width / 2 + math.cos(angle) * distance,
        size.height / 2 + math.sin(angle) * distance,
      );

      paint.color = Colors.yellow.withOpacity(1.0 - progress);

      _drawStar(canvas, starPos, 20 * (1.0 - progress * 0.5), paint);
    }
  }

  void _drawStar(Canvas canvas, Offset center, double size, Paint paint) {
    final Path path = Path();

    for (int i = 0; i < 10; i++) {
      final double angle = (i * math.pi * 2) / 10 - math.pi / 2;
      final double radius = i % 2 == 0 ? size : size * 0.5;

      final Offset point = center +
          Offset(
            math.cos(angle) * radius,
            math.sin(angle) * radius,
          );

      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CelebrationPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
