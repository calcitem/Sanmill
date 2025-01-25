// This file is part of Sanmill.
// Copyright (C) 2019-2025 The Sanmill developers
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

import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../../../shared/database/database.dart';

/// Abstract class for PlaceEffect animations.
abstract class PieceEffectAnimation {
  void draw(
      Canvas canvas, Offset center, double diameter, double animationValue);
}

/// Default implementation of the RemoveEffect animation.
class ExplodePieceEffectAnimation implements PieceEffectAnimation {
  @override
  void draw(
      Canvas canvas, Offset center, double diameter, double animationValue) {
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
}

/// Aura effect for placing a piece.
/// Displays a halo around the piece that pulsates like a breathing light.
class AuraPieceEffectAnimation implements PieceEffectAnimation {
  @override
  void draw(
    Canvas canvas,
    Offset center,
    double diameter,
    double animationValue,
  ) {
    if (DB().displaySettings.animationDuration == 0.0) {
      return;
    }

    // Use a sinusoidal function to create a breathing effect.
    final double easedAnimation =
        (sin(animationValue * pi * 2 - pi / 2) + 1) / 2;

    final double maxRadius = diameter * 1.2;
    final double radius =
        diameter / 2 + (maxRadius - diameter / 2) * easedAnimation;
    final double opacity = 0.1 * easedAnimation + 0.1;
    final ui.Color pieceHighlightColor = DB().colorSettings.pieceHighlightColor;

    final Paint paint = Paint()
      ..color = pieceHighlightColor.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = diameter * 0.1;

    canvas.drawCircle(center, radius, paint);
  }
}

/// Burst effect for placing a piece.
/// Emits small particles in random directions that fade out over time.
class BurstPieceEffectAnimation implements PieceEffectAnimation {
  final int particleCount = 20;
  final List<Offset> directions = List<Offset>.generate(
    20,
    (int index) => Offset(
      cos((2 * pi / 20) * index + Random().nextDouble() * pi / 10),
      sin((2 * pi / 20) * index + Random().nextDouble() * pi / 10),
    ),
  );

  @override
  void draw(
      Canvas canvas, Offset center, double diameter, double animationValue) {
    if (DB().displaySettings.animationDuration == 0.0) {
      return;
    }

    final double maxDistance = diameter;
    final double easedAnimation = Curves.easeOut.transform(animationValue);
    final ui.Color boardLineColor = DB().colorSettings.boardLineColor;

    for (int i = 0; i < particleCount; i++) {
      final Offset direction = directions[i];
      final double distance = maxDistance * easedAnimation;
      final double opacity = (1.0 - easedAnimation).clamp(0.0, 1.0) * 0.7;

      final Offset particlePosition = center + direction * distance;

      final Paint paint = Paint()
        ..color = boardLineColor.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(particlePosition, 2.0, paint);
    }
  }
}

/// Echo effect for placing a piece.
/// Creates multiple fading outlines of the piece expanding outward.
class EchoPieceEffectAnimation implements PieceEffectAnimation {
  final int echoCount = 3;

  @override
  void draw(
    Canvas canvas,
    Offset center,
    double diameter,
    double animationValue,
  ) {
    if (DB().displaySettings.animationDuration == 0.0) {
      return;
    }

    final ui.Color boardLineColor = DB().colorSettings.boardLineColor;

    for (int i = 0; i < echoCount; i++) {
      final double progress =
          ((animationValue * echoCount) - i).clamp(0.0, 1.0);
      final double easedProgress = Curves.easeOut.transform(progress);
      final double radius = diameter / 2 + diameter * easedProgress;
      final double opacity = (1.0 - easedProgress) * 0.4;

      final Paint paint = Paint()
        ..color = boardLineColor.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(center, radius, paint);
    }
  }
}

/// Expand effect for placing a piece.
class ExpandPieceEffectAnimation implements PieceEffectAnimation {
  @override
  void draw(
      Canvas canvas, Offset center, double diameter, double animationValue) {
    if (DB().displaySettings.animationDuration == 0.0) {
      return;
    }

    const double maxScale = 2.0;
    final double easedAnimation = Curves.elasticOut.transform(animationValue);
    final double scale = 1.0 + (maxScale - 1.0) * easedAnimation;
    final double opacity = (1.0 - animationValue).clamp(0.0, 1.0);
    final ui.Color boardLineColor = DB().colorSettings.boardLineColor;

    final Paint paint = Paint()
      ..color = boardLineColor.withValues(alpha: opacity * 0.4)
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.drawCircle(Offset.zero, diameter / 2, paint);
    canvas.restore();
  }
}

/// Fireworks effect animation.
/// Simulates a realistic fireworks explosion with colorful trajectories.
/// Particles shoot upwards, spread out, then slowly fall down and disappear,
/// leaving colorful trails that show both the upward and downward motion.
class FireworksPieceEffectAnimation implements PieceEffectAnimation {
  FireworksPieceEffectAnimation()
      : initialVelocities = List<Offset>.generate(
          particleCount,
          (int index) {
            final Random random = Random();
            // Initial speed
            final double speed = random.nextDouble() * 200 + 500;

            // Angle spread from -π to π to cover all directions (360 degrees)
            final double angle = -pi + (random.nextDouble() * 2 * pi);

            final double vx = speed * cos(angle);
            final double vy = speed * sin(angle);
            return Offset(vx, vy);
          },
        ),
        particleColors = List<ui.Color>.generate(
          particleCount,
          (int index) {
            final Random random = Random();
            // Generate random bright and varied colors for realism
            return ui.Color.fromARGB(
              255,
              100 + random.nextInt(156), // 100-255 to ensure brightness
              100 + random.nextInt(156),
              100 + random.nextInt(156),
            );
          },
        );
  static const int particleCount =
      100; // Increased for denser and more vibrant effect
  final List<Offset> initialVelocities;
  final List<ui.Color> particleColors;
  final double gravity = 800.0;

  @override
  void draw(
      Canvas canvas, Offset center, double diameter, double animationValue) {
    final double duration = DB().displaySettings.animationDuration;

    if (duration == 0.0) {
      return;
    }

    final double t = animationValue * duration; // Current time in seconds
    final double scale = diameter / 300.0; // Scale to fit within diameter

    final double g = gravity * scale; // Scaled gravity
    const int steps = 30; // Increased steps for smoother trajectories

    for (int i = 0; i < particleCount; i++) {
      final Offset initialVelocity = initialVelocities[i] * scale;
      final ui.Color color = particleColors[i];

      // Create a path to represent the particle's trajectory
      final Path path = Path();

      for (int j = 0; j <= steps; j++) {
        final double tj = (t * j) / steps;
        if (tj > t) {
          continue;
        }

        // Position calculation: s = ut + 0.5 * a * t^2
        final Offset position = center +
            initialVelocity * tj +
            Offset(0, 0.5 * g * tj * tj); // Gravity affects y-axis

        if (j == 0) {
          path.moveTo(position.dx, position.dy);
        } else {
          path.lineTo(position.dx, position.dy);
        }
      }

      // Fade out the trail over time
      final double opacity = (1.0 - animationValue).clamp(0.0, 1.0);

      final Paint paint = Paint()
        ..color =
            color.withValues(alpha: opacity * 0.7) // Reduced opacity for trails
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      // Draw the trajectory path
      canvas.drawPath(path, paint);

      // Draw the particle at its current position
      final Offset currentPosition =
          center + initialVelocity * t + Offset(0, 0.5 * g * t * t);

      final Paint particlePaint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      // Increase particle size for better visibility
      canvas.drawCircle(
          currentPosition, 4.0 * (1.0 - animationValue), particlePaint);
    }
  }
}

/// Glow effect animation.
class GlowPieceEffectAnimation extends PieceEffectAnimation {
  @override
  void draw(
      Canvas canvas, Offset center, double diameter, double animationValue) {
    // Draw a glowing effect by drawing multiple circles with increasing radius and decreasing opacity.
    const int numCircles = 5;
    final ui.Color pieceHighlightColor = DB().colorSettings.pieceHighlightColor;

    for (int i = 0; i < numCircles; i++) {
      final double fraction = i / numCircles;
      final double radius = (diameter / 2) * (1 + animationValue * fraction);
      final Paint paint = Paint()
        ..color = pieceHighlightColor.withValues(
            alpha: (1 - animationValue) * (1 - fraction))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius, paint);
    }
  }
}

/// Orbit effect for placing a piece.
/// Displays small circles orbiting around the center point.
class OrbitPieceEffectAnimation implements PieceEffectAnimation {
  final int orbitCount = 3;

  @override
  void draw(
      Canvas canvas, Offset center, double diameter, double animationValue) {
    if (DB().displaySettings.animationDuration == 0.0) {
      return;
    }

    final double easedAnimation = Curves.linear.transform(animationValue);
    final ui.Color boardLineColor = DB().colorSettings.boardLineColor;
    final double orbitRadius = diameter * 0.5;

    for (int i = 0; i < orbitCount; i++) {
      final double angle = easedAnimation * 2 * pi + (2 * pi * i / orbitCount);
      final Offset orbitCenter = Offset(
        center.dx + orbitRadius * cos(angle),
        center.dy + orbitRadius * sin(angle),
      );

      final double opacity = (1.0 - animationValue).clamp(0.0, 1.0);
      final Paint paint = Paint()
        ..color = boardLineColor.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(orbitCenter, diameter * 0.1, paint);
    }
  }
}

/// RadialAnimation implementation of the PlaceEffect animation.
/// Renamed from DefaultPieceEffectAnimation to a single-word name.
class RadialPieceEffectAnimation implements PieceEffectAnimation {
  @override
  void draw(
      Canvas canvas, Offset center, double diameter, double animationValue) {
    if (DB().displaySettings.animationDuration == 0.0) {
      return;
    }

    // Apply easing to the animation value.
    final double easedAnimation = Curves.easeOut.transform(animationValue);

    // Calculate the maximum and current radius based on the diameter and animation.
    final double maxRadius = diameter * 0.25;
    final double currentRadius = diameter + maxRadius * easedAnimation;

    // Define the main and secondary opacities.
    final double mainOpacity = 0.6 * (1.0 - easedAnimation);
    final double secondOpacity = mainOpacity * 0.8;

    // Cache the board line color to avoid repeated calls.
    final ui.Color boardLineColor = DB().colorSettings.boardLineColor;

    // Define the configuration for each effect layer.
    final List<_EffectLayer> layers = <_EffectLayer>[
      // Main layer.
      _EffectLayer(
        radiusFactor: 1.0,
        opacityFactor: 0.8,
      ),
      // Second layer.
      _EffectLayer(
        radiusFactor: 0.75,
        opacityFactor: 0.5,
      ),
      // Third layer.
      _EffectLayer(
        radiusFactor: 0.5,
        opacityFactor: 0.2,
      ),
    ];

    // Iterate over each layer configuration to draw the circles.
    for (final _EffectLayer layer in layers) {
      // Determine the radius for the current layer.
      final double layerRadius = currentRadius * layer.radiusFactor;

      // Determine the opacity for the current layer.
      double layerOpacity;
      if (layer.opacityFactor == 1.0) {
        layerOpacity = mainOpacity;
      } else if (layer.opacityFactor == 0.8) {
        layerOpacity = secondOpacity;
      } else {
        layerOpacity = mainOpacity * layer.opacityFactor;
      }

      // Create the paint with a radial gradient shader.
      final Paint paint = Paint()
        ..shader = RadialGradient(
          colors: <ui.Color>[
            boardLineColor.withValues(alpha: layerOpacity),
            boardLineColor.withValues(alpha: 0.0),
          ],
          stops: const <double>[
            0.0,
            1.0,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: layerRadius))
        ..style = PaintingStyle.fill;

      // Draw the circle on the canvas.
      canvas.drawCircle(center, layerRadius, paint);
    }
  }
}

/// Ripple effect for placing a piece.
class RipplePieceEffectAnimation implements PieceEffectAnimation {
  @override
  void draw(
      Canvas canvas, Offset center, double diameter, double animationValue) {
    if (DB().displaySettings.animationDuration == 0.0) {
      return;
    }

    final double maxRadius = diameter * 2.0;
    final double easedAnimation = Curves.easeOut.transform(animationValue);
    final ui.Color boardLineColor = DB().colorSettings.boardLineColor;

    // Draw multiple concentric circles with varying opacity and radius.
    for (int i = 0; i < 3; i++) {
      final double progress = (easedAnimation + i * 0.3) % 1.0;
      final double radius = maxRadius * progress;
      final double opacity = (1.0 - progress).clamp(0.0, 1.0);

      final Paint paint = Paint()
        ..color = boardLineColor.withValues(alpha: opacity * 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(center, radius, paint);
    }
  }
}

/// Rotate effect for placing a piece.
class RotatePieceEffectAnimation implements PieceEffectAnimation {
  @override
  void draw(
      Canvas canvas, Offset center, double diameter, double animationValue) {
    if (DB().displaySettings.animationDuration == 0.0) {
      return;
    }

    final double rotation = animationValue * 2 * pi;
    final double radius = diameter * 1.0;
    final double opacity = (1.0 - animationValue).clamp(0.0, 1.0);

    final Path path = Path();
    path.moveTo(
        center.dx + radius * cos(rotation), center.dy + radius * sin(rotation));
    for (int i = 1; i <= 6; i++) {
      final double angle = rotation + (2 * pi * i) / 6;
      path.lineTo(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
    }
    path.close();

    final ui.Color boardLineColor = DB().colorSettings.boardLineColor;

    final Paint paint = Paint()
      ..color = boardLineColor.withValues(alpha: opacity * 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawPath(path, paint);
  }
}

/// Sparkle effect animation.
class SparklePieceEffectAnimation extends PieceEffectAnimation {
  @override
  void draw(
      Canvas canvas, Offset center, double diameter, double animationValue) {
    // Draw multiple small circles (sparkles) around the piece.
    const int numSparkles = 10;
    final ui.Color pieceHighlightColor = DB().colorSettings.pieceHighlightColor;

    for (int i = 0; i < numSparkles; i++) {
      final double angle = (i / numSparkles) * pi * 2 + animationValue * pi * 2;
      final double distance =
          diameter / 2 + (sin(animationValue * pi * 2 + i) * diameter / 4);
      final Offset sparkleCenter =
          center + Offset(cos(angle), sin(angle)) * distance;
      final Paint paint = Paint()
        ..color = pieceHighlightColor.withValues(alpha: 1 - animationValue)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(sparkleCenter, diameter / 20, paint);
    }
  }
}

/// Spiral effect for placing a piece.
class SpiralPieceEffectAnimation implements PieceEffectAnimation {
  @override
  void draw(
      Canvas canvas, Offset center, double diameter, double animationValue) {
    if (DB().displaySettings.animationDuration == 0.0) {
      return;
    }

    final double maxRadius = diameter * 1.5;
    final double easedAnimation = Curves.easeInOut.transform(animationValue);
    final double opacity = (1.0 - animationValue).clamp(0.0, 1.0);

    final Path path = Path();
    for (int i = 0; i < 3; i++) {
      final double startAngle = i * 2 * pi / 3;
      final double endAngle = (i + easedAnimation) * 2 * pi / 3;
      final double radius =
          diameter / 2 + (maxRadius - diameter / 2) * easedAnimation;

      path.addArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        endAngle - startAngle,
      );
    }

    final ui.Color boardLineColor = DB().colorSettings.boardLineColor;

    final Paint paint = Paint()
      ..color = boardLineColor.withValues(alpha: opacity * 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawPath(path, paint);
  }
}

////////////////////////////////////////////////////////////////////////////////

/// Fade effect for removing a piece.
class FadePieceEffectAnimation implements PieceEffectAnimation {
  @override
  void draw(
      Canvas canvas, Offset center, double diameter, double animationValue) {
    if (DB().displaySettings.animationDuration == 0.0) {
      return;
    }

    // Calculate opacity based on animation progress.
    final double opacity = (1.0 - animationValue).clamp(0.0, 1.0);
    final ui.Color boardLineColor = DB().colorSettings.boardLineColor;

    // Draw the piece with decreasing opacity.
    final Paint paint = Paint()
      ..color = boardLineColor.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, diameter / 2, paint);
  }
}

/// Shrink effect for removing a piece.
class ShrinkPieceEffectAnimation implements PieceEffectAnimation {
  @override
  void draw(
      Canvas canvas, Offset center, double diameter, double animationValue) {
    if (DB().displaySettings.animationDuration == 0.0) {
      return;
    }

    // Calculate the shrinking size.
    final double scale = (1.0 - animationValue).clamp(0.0, 1.0);
    final ui.Color boardLineColor = DB().colorSettings.boardLineColor;

    // Draw the shrinking piece.
    final Paint paint = Paint()
      ..color = boardLineColor
      ..style = PaintingStyle.fill;

    final double currentDiameter = diameter * scale;
    canvas.drawCircle(center, currentDiameter / 2, paint);
  }
}

/// Shatter effect for removing a piece.
class ShatterPieceEffectAnimation implements PieceEffectAnimation {
  ShatterPieceEffectAnimation()
      : shardDirections = List<Offset>.generate(
          12,
          (int index) {
            final double angle =
                (2 * pi / 12) * index + Random().nextDouble() * 0.2;
            return Offset(cos(angle), sin(angle));
          },
        );
  final int shardCount = 12;
  final List<Offset> shardDirections;

  @override
  void draw(
      Canvas canvas, Offset center, double diameter, double animationValue) {
    if (DB().displaySettings.animationDuration == 0.0) {
      return;
    }

    final double easedAnimation = Curves.easeOut.transform(animationValue);
    final ui.Color boardLineColor = DB().colorSettings.boardLineColor;

    final double maxDistance = diameter * 2.0;

    for (int i = 0; i < shardCount; i++) {
      final Offset direction = shardDirections[i];
      final double distance = maxDistance * easedAnimation;
      final double shardSize = diameter / shardCount;

      final Offset shardCenter = center + direction * distance;

      final Paint paint = Paint()
        ..color = boardLineColor.withValues(alpha: 1.0 - animationValue)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(shardCenter, shardSize / 2, paint);
    }
  }
}

/// Disperse effect for removing a piece.
class DispersePieceEffectAnimation implements PieceEffectAnimation {
  DispersePieceEffectAnimation()
      : particleOffsets = List<Offset>.generate(
          20,
          (int index) {
            final double angle = Random().nextDouble() * 2 * pi;
            final double radius = Random().nextDouble() * 0.5;
            return Offset(radius * cos(angle), radius * sin(angle));
          },
        );
  final int particleCount = 20;
  final List<Offset> particleOffsets;

  @override
  void draw(
      Canvas canvas, Offset center, double diameter, double animationValue) {
    if (DB().displaySettings.animationDuration == 0.0) {
      return;
    }

    final double easedAnimation = Curves.easeOut.transform(animationValue);
    final ui.Color boardLineColor = DB().colorSettings.boardLineColor;

    for (int i = 0; i < particleCount; i++) {
      final Offset offset = particleOffsets[i];
      final double distance = diameter * 1.5 * easedAnimation;
      final double opacity = (1.0 - animationValue).clamp(0.0, 1.0);

      final Offset particlePosition = center + offset * distance;

      final Paint paint = Paint()
        ..color = boardLineColor.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(particlePosition, diameter * 0.05, paint);
    }
  }
}

/// Vanish effect for removing a piece.
class VanishPieceEffectAnimation implements PieceEffectAnimation {
  @override
  void draw(
      Canvas canvas, Offset center, double diameter, double animationValue) {
    // Instantly removes the piece without animation.
    if (DB().displaySettings.animationDuration == 0.0) {
      return;
    }
    // No drawing needed as the piece vanishes.
  }
}

/// Melt effect for removing a piece.
class MeltPieceEffectAnimation implements PieceEffectAnimation {
  @override
  void draw(
      Canvas canvas, Offset center, double diameter, double animationValue) {
    if (DB().displaySettings.animationDuration == 0.0) {
      return;
    }

    final double easedAnimation = Curves.easeIn.transform(animationValue);
    final double scaleY = (1.0 - easedAnimation).clamp(0.0, 1.0);
    final double opacity = (1.0 - easedAnimation).clamp(0.0, 1.0);

    final ui.Color boardLineColor = DB().colorSettings.boardLineColor;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1.0, scaleY);

    final Paint paint = Paint()
      ..color = boardLineColor.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset.zero, diameter / 2, paint);
    canvas.restore();
  }
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
