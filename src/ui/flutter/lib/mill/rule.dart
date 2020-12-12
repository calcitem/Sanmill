/*
  FlutterMill, a mill game playing frontend derived from ChessRoad
  Copyright (C) 2019 He Zhaoyun (ChessRoad author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

  FlutterMill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  FlutterMill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

class Rule {
  String name = "Da San Qi";
  String description;
  int nTotalPiecesEachSide = 12; // 9 or 12
  int nPiecesAtLeast = 3; // Default is 3
  bool hasObliqueLines = true;
  bool hasBannedLocations = true;
  bool isDefenderMoveFirst = true;
  bool allowRemoveMultiPiecesWhenCloseMultiMill = false;
  bool allowRemovePieceInMill = true;
  bool isBlackLoseButNotDrawWhenBoardFull = true;
  bool isLoseButNotChangeSideWhenNoWay = true;
  bool allowFlyWhenRemainThreePieces = false;
  int maxStepsLedToDraw = 0;
}

Rule rule = Rule();

const ruleNumber = 4;
