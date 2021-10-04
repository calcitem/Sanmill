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

import 'package:sanmill/l10n/resources.dart';

class Rule {
  String name = "Default Rule";
  String description = "";
  int piecesCount = specialCountryAndRegion == "Iran" ? 12 : 9;
  int flyPieceCount = 3;
  int piecesAtLeastCount = 3;
  bool hasDiagonalLines = specialCountryAndRegion == "Iran" ? true : false;
  bool hasBannedLocations = false;
  bool mayMoveInPlacingPhase = false;
  bool isDefenderMoveFirst = false;
  bool mayRemoveMultiple = false;
  bool mayRemoveFromMillsAlways = false;
  bool mayOnlyRemoveUnplacedPieceInPlacingPhase = false;
  bool isWhiteLoseButNotDrawWhenBoardFull = true;
  bool isLoseButNotChangeSideWhenNoWay = true;
  bool mayFly = true;
  int nMoveRule = 100;
  int endgameNMoveRule = 100;
  bool threefoldRepetitionRule = true;
}

Rule rule = Rule();

const ruleNumber = 4;
