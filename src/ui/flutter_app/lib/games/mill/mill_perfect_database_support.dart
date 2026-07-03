// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../rule_settings/models/rule_settings.dart';
import '../../shared/database/database.dart';

/// Rule checks shared by every feature backed by data mined against the
/// legacy Perfect Database (the full downloadable database and the bundled
/// error patch alike): the piece-removal / board-full / stalemate / etc.
/// behavior that database (and everything derived from it) assumes,
/// independent of piece count or board topology.
bool _matchesPerfectDatabaseCommonRules(RuleSettings ruleSettings) {
  return ruleSettings.flyPieceCount == 3 &&
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
      ruleSettings.oneTimeUseMill == false;
}

/// True when the active rule set matches one of the three variant shapes
/// (Standard 9MM, Lasker 10MM, Morabaraba 12MM) that the full, downloadable
/// Perfect Database supports.
bool isRuleSupportingPerfectDatabase() {
  final RuleSettings ruleSettings = DB().ruleSettings;

  final bool matchesAVariantShape =
      (ruleSettings.piecesCount == 9 &&
          !ruleSettings.hasDiagonalLines &&
          ruleSettings.mayMoveInPlacingPhase == false) ||
      (ruleSettings.piecesCount == 10 &&
          !ruleSettings.hasDiagonalLines &&
          ruleSettings.mayMoveInPlacingPhase == true) ||
      (ruleSettings.piecesCount == 12 &&
          ruleSettings.hasDiagonalLines &&
          ruleSettings.mayMoveInPlacingPhase == false);

  return matchesAVariantShape &&
      _matchesPerfectDatabaseCommonRules(ruleSettings);
}

/// True only when the active rule set is exactly "std" (Standard / Nine
/// Men's Morris: 9 pieces, no diagonal lines, no moving while still
/// placing).
///
/// The bundled error-patch asset (`assets/patches/std.mill_patch`) is mined
/// only against this one variant -- `tgf mill patch-pack` currently refuses
/// to build anything else (see its `--variant` flag). Unlike
/// [isRuleSupportingPerfectDatabase], this deliberately excludes the
/// Lasker/Morabaraba shapes that function also accepts: the patch's
/// canonical keys are plain sector/slot indices with no variant tag of
/// their own, so a Lasker or Morabaraba position could otherwise decode to
/// a key that collides with an unrelated std entry and get "corrected"
/// with a move that is not even legal under the rules actually in play.
bool isRuleSupportingErrorPatch() {
  final RuleSettings ruleSettings = DB().ruleSettings;
  return ruleSettings.piecesCount == 9 &&
      !ruleSettings.hasDiagonalLines &&
      ruleSettings.mayMoveInPlacingPhase == false &&
      _matchesPerfectDatabaseCommonRules(ruleSettings);
}
