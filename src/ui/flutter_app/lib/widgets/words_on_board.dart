/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'package:flutter/material.dart';
import 'package:sanmill/style/colors.dart';

class WordsOnBoard extends StatelessWidget {
  //
  static const digitsFontSize = 18.0;

  @override
  Widget build(BuildContext context) {
    final bChildren = <Widget>[], rChildren = <Widget>[];

    for (var i = 0; i < 7; i++) {
      if (i < 8) {
        bChildren.add(Expanded(child: SizedBox()));
        rChildren.add(Expanded(child: SizedBox()));
      }
    }

    return DefaultTextStyle(
      child: Column(
        children: <Widget>[
          Row(children: bChildren),
          Expanded(child: SizedBox()),
          Expanded(child: SizedBox()),
          Row(children: rChildren),
        ],
      ),
      style: TextStyle(color: UIColors.boardTipsColor),
    );
  }
}
