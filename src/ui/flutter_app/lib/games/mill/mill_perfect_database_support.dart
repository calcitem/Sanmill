// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../rule_settings/models/rule_settings.dart';
import '../../shared/database/database.dart';

bool isRuleSupportingPerfectDatabase() {
  final RuleSettings ruleSettings = DB().ruleSettings;

  if (((ruleSettings.piecesCount == 9 &&
              !ruleSettings.hasDiagonalLines &&
              ruleSettings.mayMoveInPlacingPhase == false) ||
          (ruleSettings.piecesCount == 10 &&
              !ruleSettings.hasDiagonalLines &&
              ruleSettings.mayMoveInPlacingPhase == true) ||
          (ruleSettings.piecesCount == 12 &&
              ruleSettings.hasDiagonalLines &&
              ruleSettings.mayMoveInPlacingPhase == false)) &&
      ruleSettings.flyPieceCount == 3 &&
      ruleSettings.piecesAtLeastCount == 3 &&
      ruleSettings.millFormationActionInPlacingPhase ==
          MillFormationActionInPlacingPhase.removeOpponentsPieceFromBoard &&
      ruleSettings.boardFullAction == BoardFullAction.firstPlayerLose &&
      ruleSettings.restrictRepeatedMillsFormation == false &&
      ruleSettings.stalemateAction == StalemateAction.endWithStalemateLoss &&
      ruleSettings.mayFly == true &&
      ruleSettings.mayRemoveFromMillsAlways == false &&
      ruleSettings.mayRemoveMultiple == false &&
      ruleSettings.enableCustodianCapture == false &&
      ruleSettings.enableInterventionCapture == false &&
      ruleSettings.enableLeapCapture == false &&
      ruleSettings.oneTimeUseMill == false) {
    return true;
  } else {
    return false;
  }
}
