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

import '../../game_page/services/mill.dart';
import '../../game_page/widgets/game_page.dart';
import '../../game_page/widgets/painters/painters.dart';
import '../painters/tutorial_painter.dart';

class TutorialBoard extends StatelessWidget {
  const TutorialBoard({
    super.key,
    required this.pieces,
    this.focusIndex,
    this.blurIndex,
  });

  final int? focusIndex;
  final int? blurIndex;
  final List<GamePiece> pieces;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constrains) {
        final double dimension = constrains.maxWidth;

        return SizedBox.square(
          dimension: dimension,
          child: CustomPaint(
            painter: BoardPainter(context),
            foregroundPainter: TutorialPainter(
              focusIndex: focusIndex,
              blurIndex: blurIndex,
              pieces: pieces,
            ),
          ),
        );
      },
    );
  }
}
