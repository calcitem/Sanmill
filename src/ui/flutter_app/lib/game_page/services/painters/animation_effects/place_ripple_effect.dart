import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Draws a ripple animation effect when placing a piece.
void drawPlaceRippleEffect(
  Canvas canvas,
  Offset center,
  double diameter,
  double animationValue,
) {
  if (animationValue >= 1.0) {
    return;
  }

  // Apply easing to the animation value
  final double easedValue = Curves.easeOut.transform(animationValue);

  // Calculate current radius based on animation progress
  final double currentRadius = diameter / 2 * easedValue;

  // Define paint with radial gradient
  final Paint paint = Paint()
    ..shader = RadialGradient(
      colors: <ui.Color>[
        Colors.blue.withOpacity(0.5 * (1.0 - easedValue)),
        Colors.blue.withOpacity(0.0),
      ],
      stops: const <double>[0.0, 1.0],
    ).createShader(Rect.fromCircle(center: center, radius: currentRadius))
    ..style = PaintingStyle.fill;

  // Draw the ripple circle
  canvas.drawCircle(center, currentRadius, paint);
}
