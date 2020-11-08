class Rule {
  String name = "打三棋";
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

const ruleNumber = 4;
Rule rule;
