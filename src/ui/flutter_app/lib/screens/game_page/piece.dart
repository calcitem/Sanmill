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

class Piece extends StatefulWidget {
  const Piece({super.key, required this.color});

  final PieceColor color;

  @override
  PieceState createState() => PieceState();
}

class PieceState extends State<Piece> {
  @override
  Widget build(BuildContext context) {
    // 这里返回一个表示棋子的小部件，根据color属性确定棋子的颜色
    // 可以根据需要自定义棋子的外观
    return Container(
      decoration: BoxDecoration(
        color: widget.color == PieceColor.white
            ? Colors.white
            : widget.color == PieceColor.black
                ? Colors.black
                : Colors.transparent,
        shape: BoxShape.circle,
      ),
    );
  }
}
