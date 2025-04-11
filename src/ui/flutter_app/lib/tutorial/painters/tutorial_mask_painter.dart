// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// tutorial_mask_painter.dart

import 'package:flutter/material.dart';

class TutorialMaskPainter extends CustomPainter {
  TutorialMaskPainter({
    this.background = Colors.black38,
    this.maskOffset,
    this.maskRadius = 56,
  });

  final Color background;
  final Offset? maskOffset;
  final double maskRadius;

  final Paint _paint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(null, _paint);
    canvas.drawColor(background, BlendMode.srcOver);
    if (maskOffset != null) {
      _paint.blendMode = BlendMode.dstOut;
      canvas.drawCircle(maskOffset!, maskRadius, _paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
