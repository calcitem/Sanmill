// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// tutorial_board.dart

import 'package:flutter/material.dart';

import '../../game_page/services/mill.dart';
import '../../game_page/services/painters/painters.dart';
import '../painters/tutorial_painter.dart';

class TutorialBoard extends StatelessWidget {
  const TutorialBoard({
    super.key,
    required this.pieceList,
    this.focusIndex,
    this.blurIndex,
  });

  final int? focusIndex;
  final int? blurIndex;
  final List<PieceColor> pieceList;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: const Key('layout_builder'),
      builder: (BuildContext context, BoxConstraints constrains) {
        final double dimension = constrains.maxWidth;

        return SizedBox.square(
          key: const Key('sized_box'),
          dimension: dimension,
          child: CustomPaint(
            key: const Key('custom_paint'),
            painter: BoardPainter(context, null),
            foregroundPainter: TutorialPainter(
              focusIndex: focusIndex,
              blurIndex: blurIndex,
              pieceList: pieceList,
            ),
          ),
        );
      },
    );
  }
}
