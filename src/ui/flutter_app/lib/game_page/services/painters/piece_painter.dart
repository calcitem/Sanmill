// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// piece_painter.dart

part of '../../../game_page/services/painters/painters.dart';

/// Custom Piece Painter
///
/// Painter to draw each piece on the board.
/// It asserts the Canvas to be a square.
class PiecePainter extends CustomPainter {
  PiecePainter({
    required this.placeAnimationValue,
    required this.moveAnimationValue,
    required this.removeAnimationValue,
    required this.pickUpAnimationValue,
    required this.putDownAnimationValue,
    required this.isPutDownAnimating,
    required this.pieceImages,
    required this.placeEffectAnimation,
    required this.removeEffectAnimation,
  });

  final double placeAnimationValue;
  final double moveAnimationValue;
  final double removeAnimationValue;
  final double pickUpAnimationValue;
  final double putDownAnimationValue;
  final bool isPutDownAnimating;

  final Map<PieceColor, ui.Image?>? pieceImages;

  // Animation instances for place and remove effects.
  final PieceEffectAnimation placeEffectAnimation;
  final PieceEffectAnimation removeEffectAnimation;

  /// Calculate the scale and shadow properties for a piece based on animation state
  /// Returns a map with 'scale', 'shadowBlur' and 'lift' keys
  Map<String, double> _calculatePieceEffects(
    int index,
    int? focusIndex,
    int? blurIndex,
  ) {
    double scale = 1.0;
    double shadowBlur = 2.0;
    double lift = 0.0;

    // Pick-up and Put-down animations are only for Moving phase
    if (GameController().position.phase != Phase.moving) {
      return <String, double>{
        'scale': scale,
        'shadowBlur': shadowBlur,
        'lift': lift,
      };
    }

    // If animation duration is 0 (instant move), do not apply any scale/lift effects
    // This respects the user setting for "No animation"
    if (DB().displaySettings.animationDuration == 0) {
      return <String, double>{
        'scale': scale,
        'shadowBlur': shadowBlur,
        'lift': lift,
      };
    }

    // Determine if this is the selected piece (at blur position during moves)
    final bool isSelectedPiece =
        (blurIndex != null && index == blurIndex) ||
        (blurIndex != null &&
            focusIndex != null &&
            index == focusIndex &&
            moveAnimationValue < 1.0);

    // Determine if put-down animation should be active for this piece
    final bool isPuttingDown =
        isPutDownAnimating && focusIndex != null && index == focusIndex;

    if (isPuttingDown) {
      // Put-down effect: piece at focus position landing after place/move
      // Scale down from 1.1 to 1.0 (reverse of pick-up)
      final double putDownProgress = putDownAnimationValue;
      scale = 1.1 - (putDownProgress * 0.1);
      // Reduced shadow blur range for a tighter, closer-to-ground feel
      shadowBlur = 6.0 - (putDownProgress * 4.0);
      // Reduced lift height to 6.0 for a more realistic, less floaty appearance
      lift = 6.0 - (putDownProgress * 6.0);
    } else if (isSelectedPiece) {
      // Pick-up effect: piece at blur position (selected for movement)
      // Scale up from 1.0 to 1.1, then stay at 1.1 while selected
      final double pickUpProgress = pickUpAnimationValue.clamp(0.0, 1.0);
      scale = 1.0 + (pickUpProgress * 0.1);
      // Reduced shadow blur range
      shadowBlur = 2.0 + (pickUpProgress * 4.0);
      // Reduced lift height to 6.0
      lift = pickUpProgress * 6.0;
    }

    return <String, double>{
      'scale': scale,
      'shadowBlur': shadowBlur,
      'lift': lift,
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    assert(size.width == size.height);
    final int? focusIndex = GameController().gameInstance.focusIndex;
    final int? blurIndex = GameController().gameInstance.blurIndex;
    final int? removeIndex = GameController().gameInstance.removeIndex;

    final Paint paint = Paint();
    final Path shadowPath = Path();

    // Separate lists for normal and moving pieces.
    final List<Piece> normalPiecesToDraw = <Piece>[];
    final List<Piece> movingPiecesToDraw = <Piece>[];

    final double pieceWidth =
        (size.width - AppTheme.boardPadding * 2) *
            DB().displaySettings.pieceWidth /
            6 -
        1;

    // Variable to hold the current position of the moving piece.
    Offset? movingPos;

    // Draw pieces on board.
    for (int row = 0; row < 7; row++) {
      for (int col = 0; col < 7; col++) {
        final int index = row * 7 + col;

        final PieceColor pieceColor = GameController().position.pieceOnGrid(
          index,
        );

        Offset pos;

        // Check if this piece is currently placing.
        final bool isPlacingPiece =
            (placeAnimationValue < 1.0) &&
            (focusIndex != null) &&
            (blurIndex == null) &&
            (index == focusIndex);

        // Check if this piece is currently moving.
        final bool isMovingPiece =
            (moveAnimationValue < 1.0) &&
            (focusIndex != null) &&
            (blurIndex != null) &&
            (index == focusIndex) &&
            !GameController().animationManager.isRemoveAnimationAnimating();

        // Check if this piece is currently being removed.
        final bool isRemovingPiece =
            (removeAnimationValue < 1.0) &&
            (removeIndex != null) &&
            (index == removeIndex);

        if (isPlacingPiece) {
          pos = pointFromIndex(index, size);

          placeEffectAnimation.draw(
            canvas,
            pos,
            pieceWidth,
            placeAnimationValue,
          );
          // Continue to draw the placing piece normally after the effect.
        }

        if (isMovingPiece) {
          // Calculate interpolated position between blurIndex and focusIndex.
          final Offset fromPos = pointFromIndex(blurIndex, size);
          final Offset toPos = pointFromIndex(focusIndex, size);

          pos = Offset.lerp(fromPos, toPos, moveAnimationValue)!;

          // Store the moving piece's current position for highlight.
          movingPos = pos;
        } else {
          // Use the normal position.
          pos = pointFromIndex(index, size);
        }

        if (isRemovingPiece) {
          removeEffectAnimation.draw(
            canvas,
            pos,
            pieceWidth,
            removeAnimationValue,
          );
          continue; // Skip normal drawing.
        }

        if (pieceColor == PieceColor.none) {
          continue;
        }

        final int sq = indexToSquare[index]!;
        final SquareAttribute squareAttribute =
            GameController().position.sqAttrList[sq];

        final ui.Image? image = pieceImages == null
            ? null
            : pieceImages?[pieceColor];

        final double adjustedPieceWidth = pieceWidth;

        final Piece piece = Piece(
          pieceColor: pieceColor,
          pos: pos,
          diameter: adjustedPieceWidth,
          index: index,
          squareAttribute: squareAttribute,
          image: image,
        );

        // Add to the appropriate list based on whether it's moving.
        if (isMovingPiece) {
          movingPiecesToDraw.add(piece);
        } else {
          normalPiecesToDraw.add(piece);
        }

        shadowPath.addOval(
          Rect.fromCircle(center: pos, radius: adjustedPieceWidth / 2),
        );
      }
    }

    // Draw shadows for normal pieces.
    for (final Piece piece in normalPiecesToDraw) {
      if (piece.image == null) {
        final Map<String, double> effects = _calculatePieceEffects(
          piece.index,
          focusIndex,
          blurIndex,
        );
        final double scale = effects['scale']!;
        final double shadowBlur = effects['shadowBlur']!;

        canvas.drawShadow(
          Path()..addOval(
            Rect.fromCircle(
              center: piece.pos,
              radius: (piece.diameter / 2) * scale,
            ),
          ),
          Colors.black,
          shadowBlur,
          true,
        );
      }
    }

    // Draw shadows for moving pieces.
    for (final Piece piece in movingPiecesToDraw) {
      if (piece.image == null) {
        final Map<String, double> effects = _calculatePieceEffects(
          piece.index,
          focusIndex,
          blurIndex,
        );
        final double scale = effects['scale']!;
        final double shadowBlur = effects['shadowBlur']!;

        canvas.drawShadow(
          Path()..addOval(
            Rect.fromCircle(
              center: piece.pos,
              radius: (piece.diameter / 2) * scale,
            ),
          ),
          Colors.black,
          shadowBlur,
          true,
        );
      }
    }

    paint.style = PaintingStyle.fill;

    Color blurPositionColor = Colors.transparent;

    // Draw normal pieces first.
    for (final Piece piece in normalPiecesToDraw) {
      blurPositionColor = piece.pieceColor.blurPositionColor;

      const double opacity = 1.0;

      // Calculate animation effects for this piece
      final Map<String, double> effects = _calculatePieceEffects(
        piece.index,
        focusIndex,
        blurIndex,
      );
      final double scale = effects['scale']!;
      final double lift = effects['lift']!;

      final double pieceRadius = (piece.diameter / 2) * scale;
      final double pieceInnerRadius = pieceRadius * 0.99;

      final Offset drawPos = piece.pos - Offset(0, lift);

      if (piece.image != null) {
        paintImage(
          canvas: canvas,
          rect: Rect.fromCircle(center: drawPos, radius: pieceInnerRadius),
          image: piece.image!,
          fit: BoxFit.cover,
        );
      } else {
        // Draw border of the piece.
        paint.color = piece.pieceColor.borderColor.withValues(alpha: opacity);

        if (DB().colorSettings.boardBackgroundColor == Colors.white) {
          paint.style = PaintingStyle.stroke;
          paint.strokeWidth = 4.0;
        } else {
          paint.style = PaintingStyle.fill;
        }

        canvas.drawCircle(drawPos, pieceRadius, paint);

        // Fill the piece with main color.
        paint.style = PaintingStyle.fill;
        paint.color = piece.pieceColor.mainColor.withValues(alpha: opacity);
        canvas.drawCircle(drawPos, pieceInnerRadius, paint);
      }

      // Draw numbers on pieces if enabled.
      if (DB().displaySettings.isNumbersOnPiecesShown &&
          piece.squareAttribute?.placedPieceNumber != null &&
          piece.squareAttribute!.placedPieceNumber > 0) {
        // Text Drawing:
        final TextPainter textPainter = TextPainter(
          text: TextSpan(
            text: piece.squareAttribute?.placedPieceNumber.toString(),
            style: TextStyle(
              color: piece.pieceColor.mainColor.computeLuminance() > 0.5
                  ? Colors.black
                  : Colors.white,
              fontSize: piece.diameter * 0.5,
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();

        // Calculate offset for centering the text.
        final Offset textOffset = Offset(
          drawPos.dx - textPainter.width / 2,
          drawPos.dy - textPainter.height / 2,
        );

        textPainter.paint(canvas, textOffset);
      }
    }

    // Draw moving pieces on top of normal pieces.
    for (final Piece piece in movingPiecesToDraw) {
      blurPositionColor = piece.pieceColor.blurPositionColor;

      const double opacity = 1.0;

      // Calculate animation effects for this piece
      final Map<String, double> effects = _calculatePieceEffects(
        piece.index,
        focusIndex,
        blurIndex,
      );
      final double scale = effects['scale']!;
      final double lift = effects['lift']!;

      final double pieceRadius = (piece.diameter / 2) * scale;
      final double pieceInnerRadius = pieceRadius * 0.99;

      final Offset drawPos = piece.pos - Offset(0, lift);

      if (piece.image != null) {
        paintImage(
          canvas: canvas,
          rect: Rect.fromCircle(center: drawPos, radius: pieceInnerRadius),
          image: piece.image!,
          fit: BoxFit.cover,
        );
      } else {
        // Draw border of the piece.
        paint.color = piece.pieceColor.borderColor.withValues(alpha: opacity);

        if (DB().colorSettings.boardBackgroundColor == Colors.white) {
          paint.style = PaintingStyle.stroke;
          paint.strokeWidth = 4.0;
        } else {
          paint.style = PaintingStyle.fill;
        }

        canvas.drawCircle(drawPos, pieceRadius, paint);

        // Fill the piece with main color.
        paint.style = PaintingStyle.fill;
        paint.color = piece.pieceColor.mainColor.withValues(alpha: opacity);
        canvas.drawCircle(drawPos, pieceInnerRadius, paint);
      }

      // Draw numbers on pieces if enabled.
      if (DB().displaySettings.isNumbersOnPiecesShown &&
          piece.squareAttribute?.placedPieceNumber != null &&
          piece.squareAttribute!.placedPieceNumber > 0) {
        // Text Drawing:
        final TextPainter textPainter = TextPainter(
          text: TextSpan(
            text: piece.squareAttribute?.placedPieceNumber.toString(),
            style: TextStyle(
              color: piece.pieceColor.mainColor.computeLuminance() > 0.5
                  ? Colors.black
                  : Colors.white,
              fontSize: piece.diameter * 0.5,
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();

        // Calculate offset for centering the text.
        final Offset textOffset = Offset(
          drawPos.dx - textPainter.width / 2,
          drawPos.dy - textPainter.height / 2,
        );

        textPainter.paint(canvas, textOffset);
      }
    }

    // Draw capturable pieces highlight if enabled
    if (DB().displaySettings.isCapturablePiecesHighlightShown &&
        GameController().gameInstance.gameMode != GameMode.setupPosition &&
        GameController().position.action == Act.remove) {
      final List<int> capturablePieces = GameController().position
          .getCapturablePieces();

      paint.color = DB().colorSettings.capturablePieceHighlightColor;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 3;

      for (final int sq in capturablePieces) {
        final int? index = squareToIndex[sq];
        if (index != null) {
          final Offset pos = pointFromIndex(index, size);
          canvas.drawCircle(pos, pieceWidth / 2, paint);
        }
      }
    }

    // Draw focus and blur positions.
    if (focusIndex != null &&
        GameController().gameInstance.gameMode != GameMode.setupPosition) {
      paint.color = DB().colorSettings.pieceHighlightColor;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2;

      // Calculate lift and scale for the focus piece to ensure the ring follows the piece and matches size
      final Map<String, double> effects = _calculatePieceEffects(
        focusIndex,
        focusIndex,
        blurIndex,
      );
      final double lift = effects['lift']!;
      final double scale = effects['scale']!;

      // If the piece is moving, use the interpolated position for highlight.
      final Offset focusPos =
          (movingPos ?? pointFromIndex(focusIndex, size)) - Offset(0, lift);

      // Scale the highlight circle radius to match the piece scale
      canvas.drawCircle(focusPos, (pieceWidth / 2) * scale, paint);
    }

    if (blurIndex != null &&
        GameController().gameInstance.gameMode != GameMode.setupPosition) {
      // Calculate lift for the blur piece
      final Map<String, double> effects = _calculatePieceEffects(
        blurIndex,
        focusIndex,
        blurIndex,
      );
      final double lift = effects['lift']!;

      // If color is transparent, use a fallback color to avoid crashing
      if (blurPositionColor == Colors.transparent) {
        paint.color = Colors.grey.withValues(alpha: 0.5); // Fallback color
      } else {
        paint.color = blurPositionColor;
      }

      paint.style = PaintingStyle.fill;

      // Blur remains at the original position but follows lift
      canvas.drawCircle(
        pointFromIndex(blurIndex, size) - Offset(0, lift),
        pieceWidth / 2 * 0.8,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(PiecePainter oldDelegate) =>
      placeAnimationValue != oldDelegate.placeAnimationValue ||
      moveAnimationValue != oldDelegate.moveAnimationValue ||
      removeAnimationValue != oldDelegate.removeAnimationValue ||
      pickUpAnimationValue != oldDelegate.pickUpAnimationValue ||
      putDownAnimationValue != oldDelegate.putDownAnimationValue ||
      isPutDownAnimating != oldDelegate.isPutDownAnimating;
}
