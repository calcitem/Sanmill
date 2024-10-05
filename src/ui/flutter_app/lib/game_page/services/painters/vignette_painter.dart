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
        Colors.black.withOpacity(0.5),
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
