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

part of 'game_page.dart';

@immutable
class PieceWidget extends StatelessWidget {
  const PieceWidget({
    super.key,
    required this.color,
    required this.selected,
    required this.diameter,
    required this.squareSide,
  });
  final bool selected;
  final double diameter, squareSide;
  final PieceColor color;

  @override
  Widget build(BuildContext context) {
    final Color borderColor = color == PieceColor.white
        ? AppTheme.whitePieceBorderColor
        : AppTheme.blackPieceBorderColor;
    final Color pieceColor = color == PieceColor.white
        ? DB().colorSettings.whitePieceColor
        : DB().colorSettings.blackPieceColor;

    if (selected) {
      return Container(
        width: squareSide,
        height: squareSide,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(squareSide / 2),
          color: pieceColor,
          border: Border.all(
            color: borderColor,
            width: squareSide - diameter + 2,
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Colors.black54,
              offset: Offset(1, 1),
              blurRadius: 2,
            )
          ],
        ),
      );
    }

    return Container(
      margin: EdgeInsets.all((squareSide - diameter) / 2),
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(diameter / 2),
        color: pieceColor,
        border: Border.all(color: borderColor, width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Colors.black54,
            offset: Offset(1, 1),
            blurRadius: 2,
          ),
        ],
      ),
    );
  }
}
