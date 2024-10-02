// ignore_for_file: unnecessary_parenthesis

// ignore: unused_import
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Draws a fade-out animation effect when removing a piece.
void drawRemoveFadeEffect(
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

  // Define paint with decreasing opacity
  final Paint paint = Paint()
    ..color = Colors.red.withOpacity((1.0 - easedValue))
    ..style = PaintingStyle.fill;

  // Draw the fading circle
  canvas.drawCircle(center, diameter / 2 * (1 + easedValue), paint);
}
