// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// vignette_overlay.dart

import 'package:flutter/material.dart';

import '../services/painters/vignette_painter.dart';

class VignetteOverlay extends StatelessWidget {
  const VignetteOverlay({super.key, required this.gameBoardRect});

  final Rect gameBoardRect;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      key: const Key('vignette_overlay_ignore_pointer'),
      child: CustomPaint(
        key: const Key('vignette_overlay_custom_paint'),
        size: Size.infinite,
        painter: VignettePainter(gameBoardRect),
      ),
    );
  }
}
