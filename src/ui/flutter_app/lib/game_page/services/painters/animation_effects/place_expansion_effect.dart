// ignore: unused_import
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Draws an expansion animation effect when placing a piece.
void drawPlaceExpansionEffect(
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

  // Calculate current radius and opacity based on animation progress
  final double currentRadius = diameter / 2 * (1 + easedValue);
  final double opacity = (1.0 - easedValue).clamp(0.0, 1.0);

  // Define paint with adjusted opacity
  final Paint paint = Paint()
    ..color = Colors.green.withOpacity(0.6 * opacity)
    ..style = PaintingStyle.fill;

  // Draw the expanding circle
  canvas.drawCircle(center, currentRadius, paint);
}
