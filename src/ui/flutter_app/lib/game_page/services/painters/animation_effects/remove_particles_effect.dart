import 'dart:math';
import 'package:flutter/material.dart';

/// Draws a particle animation effect when removing a piece.
void drawRemoveParticleEffect(
  Canvas canvas,
  Offset center,
  double diameter,
  double animationValue,
) {
  if (animationValue >= 1.0) {
    return;
  }

  const int numParticles = 20;
  final double maxDistance = diameter * 2;
  final double particleMaxSize = diameter * 0.12;
  final double particleMinSize = diameter * 0.05;

  final double easedValue = Curves.easeOut.transform(animationValue);

  final Random random = Random();

  for (int i = 0; i < numParticles; i++) {
    final double angle =
        (i / numParticles) * 2 * pi + random.nextDouble() * 0.2;
    final double speed = 0.5 + random.nextDouble() * 0.4;

    final double distance = speed * easedValue * maxDistance;
    final Offset offset = Offset(cos(angle), sin(angle)) * distance;
    final Offset particlePos = center + offset;

    final double opacity = (1.0 - easedValue).clamp(0.0, 1.0);

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
            (1.0 - easedValue) *
            (0.8 + random.nextDouble() * 0.4);

    canvas.drawCircle(particlePos, particleSize, particlePaint);
  }
}
