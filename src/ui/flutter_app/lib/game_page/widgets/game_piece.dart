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

part of 'game_page.dart';

class GamePiece {
  GamePiece({
    required this.pieceColor,
    required this.position,
    required this.diameter,
    this.animated = false,
    this.animationValue = 1.0, // 1.0 means no animation
  });

  late final PieceColor pieceColor;
  late final Offset position;
  late final double diameter;
  bool animated;
  double animationValue;

  // Border color
  Color get borderColor => pieceColor.borderColor;

  Color get fillColor => pieceColor.pieceColor;

  // Draw the piece
  void updateAnimation(double value) {
    animationValue = value;
    animated = true;
  }

  // Reset the animation
  void resetAnimation() {
    animationValue = 1.0;
    animated = false;
  }
}
