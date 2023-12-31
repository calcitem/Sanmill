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
