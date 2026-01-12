// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

/// Paints a minimal "branch gutter" for the move list (Active Line view).
///
/// Design goals:
/// - Keep the main content readable (industry-standard mainline + variation chips)
/// - Still provide structural cues:
///   - Where a branch point exists (alternatives at this ply)
///   - Where the current line diverges (variation start)
///   - Whether we are currently on a variation branch
///   - Which move is the current active node
///
/// This is intentionally not a full PGN tree visualization. It is a compact,
/// always-on helper that lives alongside the standard list layout.
class ActiveLineGutterPainter extends CustomPainter {
  const ActiveLineGutterPainter({
    required this.gutterWidth,
    required this.baseColor,
    required this.highlightColor,
    required this.hasAlternatives,
    required this.isVariationStart,
    required this.isOnVariationBranch,
    required this.isActiveNode,
  });

  final double gutterWidth;
  final Color baseColor;
  final Color highlightColor;
  final bool hasAlternatives;
  final bool isVariationStart;
  final bool isOnVariationBranch;
  final bool isActiveNode;

  @override
  void paint(Canvas canvas, Size size) {
    if (gutterWidth <= 0) {
      return;
    }

    final double x = gutterWidth / 2;

    // Anchor around the first-line text height.
    // Using a fixed anchor is more stable than size.height / 2 when chips wrap.
    final double y = size.height < 24 ? size.height / 2 : 14.0;

    final Paint faintLine = Paint()
      ..color = baseColor.withValues(alpha: 0.25)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Paint strongLine = Paint()
      ..color = highlightColor.withValues(alpha: 0.85)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Draw a faint baseline only when we need any structure.
    final bool needsAnyCue =
        hasAlternatives ||
        isVariationStart ||
        isOnVariationBranch ||
        isActiveNode;
    if (needsAnyCue) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), faintLine);
    }

    // If the current node is on a variation branch, emphasize the vertical line.
    if (isOnVariationBranch) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), strongLine);
    }

    // Variation start: draw an elbow/tick so users can see the divergence point.
    if (isVariationStart) {
      final double right = gutterWidth - 1.0;
      canvas.drawLine(Offset(x, y), Offset(right, y), strongLine);
      canvas.drawLine(Offset(x, y), Offset(x, size.height), strongLine);
    }

    // Branch point: indicate there are alternative moves at this ply.
    if (hasAlternatives) {
      final Paint dotStroke = Paint()
        ..color = baseColor.withValues(alpha: 0.75)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(Offset(x, y), 3.0, dotStroke);
    }

    // Active node: render a filled marker.
    if (isActiveNode) {
      final Paint dotFill = Paint()
        ..color = highlightColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), 3.2, dotFill);
    }
  }

  @override
  bool shouldRepaint(covariant ActiveLineGutterPainter oldDelegate) {
    return gutterWidth != oldDelegate.gutterWidth ||
        baseColor != oldDelegate.baseColor ||
        highlightColor != oldDelegate.highlightColor ||
        hasAlternatives != oldDelegate.hasAlternatives ||
        isVariationStart != oldDelegate.isVariationStart ||
        isOnVariationBranch != oldDelegate.isOnVariationBranch ||
        isActiveNode != oldDelegate.isActiveNode;
  }
}
