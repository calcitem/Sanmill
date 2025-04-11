// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// vignette_painter.dart

import 'package:flutter/material.dart';

class VignettePainter extends CustomPainter {
  VignettePainter(this.gameBoardRect);

  final Rect gameBoardRect;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;

    final double visibleHeight = size.height;
    final Offset visibleCenter = Offset(size.width / 2, visibleHeight / 2);

    final double alignmentY = (visibleCenter.dy / size.height) * 2 - 1;
    final Alignment gradientCenter = Alignment(0, alignmentY);

    const double gradientRadius = 1.4;

    final Gradient gradient = RadialGradient(
      center: gradientCenter,
      radius: gradientRadius,
      colors: <Color>[
        Colors.transparent,
        Colors.black.withValues(alpha: 0.5),
      ],
      stops: const <double>[0.5, 1.0],
    );

    final Paint paint = Paint()
      ..shader = gradient.createShader(rect)
      ..blendMode = BlendMode.darken;

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
