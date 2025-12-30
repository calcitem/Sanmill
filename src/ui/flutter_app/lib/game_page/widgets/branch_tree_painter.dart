// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// branch_tree_painter.dart

import 'package:flutter/material.dart';

/// A widget that renders git-style branch lines for PGN variations
class BranchTreeWidget extends StatelessWidget {
  const BranchTreeWidget({
    required this.branchColumns,
    required this.branchColumn,
    required this.branchLineType,
    required this.isLastSibling,
    required this.siblingIndex,
    required this.color,
    super.key,
  });

  final List<bool> branchColumns;
  final int branchColumn;
  final String branchLineType;
  final bool isLastSibling;
  final int siblingIndex;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(branchColumns.length * 20.0, 40.0),
      painter: BranchTreePainter(
        branchColumns: branchColumns,
        branchColumn: branchColumn,
        branchLineType: branchLineType,
        isLastSibling: isLastSibling,
        siblingIndex: siblingIndex,
        color: color,
      ),
    );
  }
}

/// Custom painter for drawing branch tree lines
class BranchTreePainter extends CustomPainter {
  BranchTreePainter({
    required this.branchColumns,
    required this.branchColumn,
    required this.branchLineType,
    required this.isLastSibling,
    required this.siblingIndex,
    required this.color,
  });

  final List<bool> branchColumns;
  final int branchColumn;
  final String branchLineType;
  final bool isLastSibling;
  final int siblingIndex;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    const double columnWidth = 20.0;
    final double centerY = size.height / 2;

    // Draw vertical lines for active branches in other columns
    for (int i = 0; i < branchColumns.length; i++) {
      if (branchColumns[i] && i != branchColumn) {
        final double x = i * columnWidth + columnWidth / 2;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
      }
    }

    // Draw the branch line for this move
    final double currentX = branchColumn * columnWidth + columnWidth / 2;

    switch (branchLineType) {
      case 'mainline':
        // Just vertical line through the center
        canvas.drawLine(
          Offset(currentX, 0),
          Offset(currentX, size.height),
          linePaint,
        );
        break;

      case 'fork_start':
        // Parent node that has children: draw vertical line and fork symbol
        // Draw vertical line
        canvas.drawLine(
          Offset(currentX, 0),
          Offset(currentX, size.height),
          linePaint,
        );
        break;

      case 'variation_start':
        // First move of a variation: draw ├─ or └─
        if (isLastSibling) {
          // Last sibling: └─
          canvas.drawLine(
            Offset(currentX, 0),
            Offset(currentX, centerY),
            linePaint,
          );
          canvas.drawLine(
            Offset(currentX, centerY),
            Offset(currentX + columnWidth / 2, centerY),
            linePaint,
          );
        } else {
          // Not last sibling: ├─
          canvas.drawLine(
            Offset(currentX, 0),
            Offset(currentX, size.height),
            linePaint,
          );
          canvas.drawLine(
            Offset(currentX, centerY),
            Offset(currentX + columnWidth / 2, centerY),
            linePaint,
          );
        }
        break;

      case 'variation_continue':
        // Continuation of a variation: just vertical line in its column
        if (branchColumn < branchColumns.length &&
            branchColumns[branchColumn]) {
          canvas.drawLine(
            Offset(currentX, 0),
            Offset(currentX, size.height),
            linePaint,
          );
        }
        break;

      case 'variation_end':
        // Last move of a variation before returning to parent
        canvas.drawLine(
          Offset(currentX, 0),
          Offset(currentX, centerY),
          linePaint,
        );
        break;

      default:
        // Default: simple vertical line
        canvas.drawLine(
          Offset(currentX, 0),
          Offset(currentX, size.height),
          linePaint,
        );
    }
  }

  @override
  bool shouldRepaint(BranchTreePainter oldDelegate) {
    return branchColumns != oldDelegate.branchColumns ||
        branchColumn != oldDelegate.branchColumn ||
        branchLineType != oldDelegate.branchLineType ||
        isLastSibling != oldDelegate.isLastSibling ||
        color != oldDelegate.color;
  }
}
