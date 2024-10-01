// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

part of '../../../game_page/services/painters/painters.dart';

/// Piece Information
///
/// Holds parameters needed to paint each piece.
@immutable
class Piece {
  const Piece({
    required this.pieceColor,
    required this.pos,
    required this.diameter,
    required this.index,
    this.squareAttribute,
    this.image,
  });

  /// The color of the piece.
  final PieceColor pieceColor;

  /// The position of the piece on the canvas.
  final Offset pos;

  /// The diameter of the piece.
  final double diameter;

  /// The index of the piece.
  final int index;

  final SquareAttribute? squareAttribute;
  final ui.Image? image;
}

/// Custom Piece Painter
///
/// Painter to draw each piece on the board.
/// It asserts the Canvas to be a square.
class PiecePainter extends CustomPainter {
  PiecePainter({
    required this.placeAnimationValue,
    required this.moveAnimationValue,
    required this.removeAnimationValue,
    required this.pieceImages,
  });

  final double placeAnimationValue;
  final double moveAnimationValue;
  final double removeAnimationValue;

  final Map<PieceColor, ui.Image?>? pieceImages;

  @override
  void paint(Canvas canvas, Size size) {
    assert(size.width == size.height);
    final int? focusIndex = GameController().gameInstance.focusIndex;
    final int? blurIndex = GameController().gameInstance.blurIndex;
    final int? removeIndex = GameController().gameInstance.removeIndex;

    final Paint paint = Paint();
    final Path shadowPath = Path();
    final List<Piece> piecesToDraw = <Piece>[];

    final double pieceWidth = (size.width - AppTheme.boardPadding * 2) *
            DB().displaySettings.pieceWidth /
            6 -
        1;

    // Variable to hold the current position of the moving piece
    Offset? movingPos;

    // Draw pieces on board
    for (int row = 0; row < 7; row++) {
      for (int col = 0; col < 7; col++) {
        final int index = row * 7 + col;

        final PieceColor pieceColor =
            GameController().position.pieceOnGrid(index);

        Offset pos;

        // Check if this piece is currently placing
        final bool isPlacingPiece = (placeAnimationValue < 1.0) &&
            (focusIndex != null) &&
            (blurIndex == null) &&
            (index == focusIndex);

        // Check if this piece is currently moving
        final bool isMovingPiece = (moveAnimationValue < 1.0) &&
            (focusIndex != null) &&
            (blurIndex != null) &&
            (index == focusIndex) &&
            !GameController().animationManager.isRemoveAnimationAnimating();

        // Check if this piece is currently being removed
        final bool isRemovingPiece = (removeAnimationValue < 1.0) &&
            (removeIndex != null) &&
            (index == removeIndex);

        if (isPlacingPiece) {
          pos = pointFromIndex(index, size);

          drawPlaceEffect(
            canvas,
            pos,
            pieceWidth,
            placeAnimationValue,
          );
          //continue; // Skip normal drawing
        }

        if (isMovingPiece) {
          // Calculate interpolated position between blurIndex and focusIndex
          final Offset fromPos = pointFromIndex(blurIndex, size);
          final Offset toPos = pointFromIndex(focusIndex, size);

          pos = Offset.lerp(fromPos, toPos, moveAnimationValue)!;

          // Store the moving piece's current position for highlight
          movingPos = pos;
        } else {
          // Use the normal position
          pos = pointFromIndex(index, size);
        }

        if (isRemovingPiece) {
          drawRemoveEffect(
            canvas,
            pos,
            pieceWidth,
            removeAnimationValue,
          );
          continue; // Skip normal drawing
        }

        if (pieceColor == PieceColor.none) {
          continue;
        }

        final int sq = indexToSquare[index]!;
        final SquareAttribute squareAttribute =
            GameController().position.sqAttrList[sq];

        final ui.Image? image =
            pieceImages == null ? null : pieceImages?[pieceColor];

        final double adjustedPieceWidth = pieceWidth;

        piecesToDraw.add(
          Piece(
            pieceColor: pieceColor,
            pos: pos,
            diameter: adjustedPieceWidth,
            index: index,
            squareAttribute: squareAttribute,
            image: image,
          ),
        );

        shadowPath.addOval(
          Rect.fromCircle(
            center: pos,
            radius: adjustedPieceWidth / 2,
          ),
        );
      }
    }

    // Draw shadow of pieces if image is not available
    if (pieceImages == null) {
      canvas.drawShadow(shadowPath, Colors.black, 2, true);
    }

    paint.style = PaintingStyle.fill;

    Color blurPositionColor = Colors.transparent;
    for (final Piece piece in piecesToDraw) {
      blurPositionColor = piece.pieceColor.blurPositionColor;

      const double opacity = 1.0;

      final double pieceRadius = piece.diameter / 2;
      final double pieceInnerRadius = pieceRadius * 0.99;

      if (piece.image != null) {
        paintImage(
          canvas: canvas,
          rect: Rect.fromCircle(
            center: piece.pos,
            radius: pieceInnerRadius,
          ),
          image: piece.image!,
          fit: BoxFit.cover,
        );
      } else {
        // Draw border of the piece
        paint.color = piece.pieceColor.borderColor.withOpacity(opacity);

        if (DB().colorSettings.boardBackgroundColor == Colors.white) {
          paint.style = PaintingStyle.stroke;
          paint.strokeWidth = 4.0;
        } else {
          paint.style = PaintingStyle.fill;
        }

        canvas.drawCircle(
          piece.pos,
          pieceRadius,
          paint,
        );

        // Fill the piece with main color
        paint.style = PaintingStyle.fill;
        paint.color = piece.pieceColor.mainColor.withOpacity(opacity);
        canvas.drawCircle(
          piece.pos,
          pieceInnerRadius,
          paint,
        );
      }

      // Draw numbers on pieces if enabled
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

        // Calculate offset for centering the text
        final Offset textOffset = Offset(
          piece.pos.dx - textPainter.width / 2,
          piece.pos.dy - textPainter.height / 2,
        );

        textPainter.paint(canvas, textOffset);
      }
    }

    // Draw focus and blur positions
    if (focusIndex != null &&
        GameController().gameInstance.gameMode != GameMode.setupPosition) {
      paint.color = DB().colorSettings.pieceHighlightColor;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2;

      // If the piece is moving, use the interpolated position for highlight
      final Offset focusPos = movingPos ?? pointFromIndex(focusIndex, size);

      canvas.drawCircle(
        focusPos,
        pieceWidth / 2,
        paint,
      );
    }

    if (blurIndex != null &&
        GameController().gameInstance.gameMode != GameMode.setupPosition) {
      if (kDebugMode) {
        if (blurPositionColor == Colors.transparent) {
          throw Exception('Blur position color is transparent');
        }
      }
      paint.color = blurPositionColor;
      paint.style = PaintingStyle.fill;

      // If the piece is moving, optionally update blur position if needed
      // Here, assuming blur remains at the original position
      canvas.drawCircle(
        pointFromIndex(blurIndex, size),
        pieceWidth / 2 * 0.8,
        paint,
      );
    }
  }

  void drawPlaceEffect(
    Canvas canvas,
    Offset center,
    double diameter,
    double animationValue,
  ) {
    if (DB().displaySettings.animationDuration == 0.0) {
      return;
    }

    // Apply easing to the animation value
    final double easedAnimation = Curves.easeOut.transform(animationValue);

    // Calculate the maximum and current radius based on the diameter and animation
    final double maxRadius = diameter * 0.25;
    final double currentRadius = diameter + maxRadius * easedAnimation;

    // Define the main and secondary opacities
    final double mainOpacity = 0.6 * (1.0 - easedAnimation);
    final double secondOpacity = mainOpacity * 0.8;

    // Cache the board line color to avoid repeated calls
    final ui.Color boardLineColor = DB().colorSettings.boardLineColor;

    // Define the configuration for each effect layer
    final List<_EffectLayer> layers = <_EffectLayer>[
      // Main layer
      _EffectLayer(
        radiusFactor: 1.0,
        opacityFactor: 0.8,
      ),
      // Second layer
      _EffectLayer(
        radiusFactor: 0.75,
        opacityFactor: 0.5,
      ),
      // Third layer
      _EffectLayer(
        radiusFactor: 0.5,
        opacityFactor: 0.2,
      ),
    ];

    // Iterate over each layer configuration to draw the circles
    for (final _EffectLayer layer in layers) {
      // Determine the radius for the current layer
      final double layerRadius = currentRadius * layer.radiusFactor;

      // Determine the opacity for the current layer
      double layerOpacity;
      if (layer.opacityFactor == 1.0) {
        layerOpacity = mainOpacity;
      } else if (layer.opacityFactor == 0.8) {
        layerOpacity = secondOpacity;
      } else {
        layerOpacity = mainOpacity * layer.opacityFactor;
      }

      // Create the paint with a radial gradient shader
      final Paint paint = Paint()
        ..shader = RadialGradient(
          colors: <ui.Color>[
            boardLineColor.withOpacity(layerOpacity),
            boardLineColor.withOpacity(0.0),
          ],
          stops: const <double>[
            0.0,
            1.0,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: layerRadius))
        ..style = PaintingStyle.fill;

      // Draw the circle on the canvas
      canvas.drawCircle(center, layerRadius, paint);
    }
  }

  void drawRemoveEffect(
    Canvas canvas,
    Offset center,
    double diameter,
    double animationValue,
  ) {
    if (DB().displaySettings.animationDuration == 0.0) {
      return;
    }

    final int numParticles = DB().ruleSettings.piecesCount;
    final double maxDistance = diameter * 3;
    final double particleMaxSize = diameter * 0.12;
    final double particleMinSize = diameter * 0.05;

    final double time = Curves.easeOut.transform(animationValue);

    final int seed = DateTime.now().millisecondsSinceEpoch;
    final Random random = Random(seed);

    for (int i = 0; i < numParticles; i++) {
      final double angle =
          (i / numParticles) * 2 * pi + random.nextDouble() * 0.2;
      final double speed = 0.5 + random.nextDouble() * 0.4;

      final double distance = speed * time * maxDistance;
      final Offset offset = Offset(cos(angle), sin(angle)) * distance;
      final Offset particlePos = center + offset;

      final double opacity = (1.0 - time).clamp(0.0, 1.0);

      final Color particleColor = HSVColor.fromAHSV(
        opacity,
        random.nextDouble() * 360,
        1.0,
        1.0,
      ).toColor();

      final Paint particlePaint = Paint()
        ..color = particleColor
        ..style = PaintingStyle.fill;

      final double particleSize = particleMinSize +
          (particleMaxSize - particleMinSize) *
              (1.0 - time) *
              (0.8 + random.nextDouble() * 0.4);

      canvas.drawCircle(particlePos, particleSize, particlePaint);
    }
  }

  @override
  bool shouldRepaint(PiecePainter oldDelegate) =>
      placeAnimationValue != oldDelegate.placeAnimationValue ||
      moveAnimationValue != oldDelegate.moveAnimationValue ||
      removeAnimationValue != oldDelegate.removeAnimationValue;
}

/// A helper class to define the properties of each effect layer.
class _EffectLayer {
  _EffectLayer({
    required this.radiusFactor,
    required this.opacityFactor,
  });

  /// The factor by which to multiply the current radius.
  final double radiusFactor;

  /// The factor by which to multiply the main opacity.
  final double opacityFactor;
}
