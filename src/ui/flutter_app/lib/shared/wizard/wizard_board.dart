// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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

import '../../services/mill/mill.dart';
import '../painters/painters.dart';
import 'wizard_painter.dart';

class WizardBoard extends StatelessWidget {
  const WizardBoard({
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
      builder: (BuildContext context, BoxConstraints constrains) {
        final double dimension = constrains.maxWidth;

        return SizedBox.square(
          dimension: dimension,
          child: CustomPaint(
            painter: BoardPainter(context),
            foregroundPainter: WizardPainter(
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
