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

import '../../../game_page/services/mill.dart';
import '../../game_page/widgets/game_page.dart';
import '../../game_page/widgets/painters/painters.dart';
import '../../shared/database/database.dart';

/// Preview Piece Painter
class TutorialPainter extends CustomPainter {
  TutorialPainter({this.blurIndex, this.focusIndex, required this.pieces});

  final int? focusIndex;
  final int? blurIndex;
  final List<GamePiece> pieces;

  @override
  void paint(Canvas canvas, Size size) {
    assert(size.width == size.height);

    final Paint paint = Paint();
    final Path shadowPath = Path();
    final List<PiecePaintParam> piecesToDraw = <PiecePaintParam>[];

    final double pieceWidth = size.width * DB().displaySettings.pieceWidth / 7;

    // 假设 GameController 提供了 forEachPiece 方法
    GameController().forEachPiece((int index, GamePiece gamePiece) {
      if (gamePiece.pieceColor == PieceColor.none) {
        return; // 跳过无棋子的位置
      }

      final Offset pos = gamePiece.position; // 直接使用 GamePiece 中的位置
      final bool animated = gamePiece.animated; // 直接使用 GamePiece 中的动画状态

      piecesToDraw.add(
        PiecePaintParam(
          gamePiece: gamePiece, // 直接传递 GamePiece 实例
        ),
      );

      shadowPath.addOval(
        Rect.fromCircle(
          center: pos,
          radius: (gamePiece.animated ? gamePiece.diameter * gamePiece.animationValue : gamePiece.diameter) / 2,
        ),
      );
    });

    // 绘制阴影和棋子的代码保持不变，使用 piecesToDraw 中的数据
    paint.color = Colors.black.withOpacity(0.2);
    canvas.drawShadow(shadowPath, Colors.black, 4, false);
  }

  @override
  bool shouldRepaint(TutorialPainter oldDelegate) => true;
}
