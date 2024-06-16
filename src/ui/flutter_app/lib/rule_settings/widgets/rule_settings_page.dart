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
import 'package:hive_flutter/hive_flutter.dart' show Box;

import '../../custom_drawer/custom_drawer.dart';
import '../../game_page/services/mill.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/widgets/settings/settings.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../models/rule_settings.dart';

part 'modals/board_full_action_modal.dart';
part 'modals/endgame_n_move_rule_modal.dart';
part 'modals/fly_piece_count_modal.dart';
part 'modals/mill_formation_action_in_placing_phase_modal.dart';
part 'modals/n_move_rule_modal.dart';
part 'modals/piece_count_modal.dart';
part 'modals/stalemate_action_modal.dart';

bool visitedRuleSettingsPage = false;

class RuleSettingsPage extends StatelessWidget {
  const RuleSettingsPage({super.key});

  // General
  void _setNTotalPiecesEachSide(
    BuildContext context,
    RuleSettings ruleSettings,
  ) {
    void callback(int? piecesCount) {
      Navigator.pop(context);

      DB().ruleSettings = ruleSettings.copyWith(piecesCount: piecesCount);

      logger.t("[config] piecesCount = $piecesCount");

      if (DB().generalSettings.usePerfectDatabase) {
        rootScaffoldMessengerKey.currentState!
            .showSnackBarClear(S.of(context).reopenToTakeEffect);
      }
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _PieceCountModal(
        piecesCount: ruleSettings.piecesCount,
        onChanged: callback,
      ),
    );
  }

  void _setNMoveRule(BuildContext context, RuleSettings ruleSettings) {
    void callback(int? nMoveRule) {
      Navigator.pop(context);

      DB().ruleSettings = ruleSettings.copyWith(nMoveRule: nMoveRule);

      logger.t("[config] nMoveRule = $nMoveRule");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _NMoveRuleModal(
        nMoveRule: ruleSettings.nMoveRule,
        onChanged: callback,
      ),
    );
  }

  // TODO: This feature EndgameNMoveRule is not implemented yet
  void _setEndgameNMoveRule(BuildContext context, RuleSettings ruleSettings) {
    void callback(int? endgameNMoveRule) {
      if (endgameNMoveRule == null ||
          endgameNMoveRule < DB().ruleSettings.nMoveRule) {
        rootScaffoldMessengerKey.currentState!
            .showSnackBarClear(S.of(context).experimental);
      }

      Navigator.pop(context);

      DB().ruleSettings =
          ruleSettings.copyWith(endgameNMoveRule: endgameNMoveRule);

      logger.t("[config] endgameNMoveRule = $endgameNMoveRule");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _EndGameNMoveRuleModal(
        endgameNMoveRule: ruleSettings.endgameNMoveRule,
        onChanged: callback,
      ),
    );
  }

  void _setFlyPieceCount(BuildContext context, RuleSettings ruleSettings) {
    void callback(int? flyPieceCount) {
      Navigator.pop(context);

      DB().ruleSettings = ruleSettings.copyWith(flyPieceCount: flyPieceCount);

      logger.t("[config] flyPieceCount = $flyPieceCount");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _FlyPieceCountModal(
        flyPieceCount: ruleSettings.flyPieceCount,
        onChanged: callback,
      ),
    );
  }

  void _setHasDiagonalLines(RuleSettings ruleSettings, bool value) {
    DB().ruleSettings = ruleSettings.copyWith(hasDiagonalLines: value);

    logger.t("[config] hasDiagonalLines: $value");
  }

  void _setAllowFlyingAllowed(RuleSettings ruleSettings, bool value) {
    DB().ruleSettings = ruleSettings.copyWith(mayFly: value);

    logger.t("[config] mayFly: $value");
  }

  void _setThreefoldRepetitionRule(RuleSettings ruleSettings, bool value) {
    DB().ruleSettings = ruleSettings.copyWith(threefoldRepetitionRule: value);

    logger.t("[config] threefoldRepetitionRule: $value");
  }

  // Placing
  void _setBoardFullAction(BuildContext context, RuleSettings ruleSettings) {
    void callback(BoardFullAction? boardFullAction) {
      Navigator.pop(context);

      DB().ruleSettings =
          ruleSettings.copyWith(boardFullAction: boardFullAction);

      logger.t("[config] boardFullAction = $boardFullAction");

      // TODO: BoardFullAction: experimental
      if (boardFullAction != BoardFullAction.firstPlayerLose &&
          boardFullAction != BoardFullAction.agreeToDraw) {
        rootScaffoldMessengerKey.currentState!
            .showSnackBarClear(S.of(context).experimental);
      }
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _BoardFullActionModal(
        boardFullAction: ruleSettings.boardFullAction!,
        onChanged: callback,
      ),
    );
  }

  void _setMillFormationActionInPlacingPhase(
      BuildContext context, RuleSettings ruleSettings) {
    void callback(
        MillFormationActionInPlacingPhase? millFormationActionInPlacingPhase) {
      Navigator.pop(context);

      DB().ruleSettings = ruleSettings.copyWith(
          millFormationActionInPlacingPhase: millFormationActionInPlacingPhase);

      switch (millFormationActionInPlacingPhase) {
        case MillFormationActionInPlacingPhase.removeOpponentsPieceFromBoard:
          rootScaffoldMessengerKey.currentState!.showSnackBarClear(
              S.of(context).removeOpponentsPieceFromBoard_Detail);
          break;
        case MillFormationActionInPlacingPhase
              .removeOpponentsPieceFromHandThenOpponentsTurn:
          rootScaffoldMessengerKey.currentState!.showSnackBarClear(S
              .of(context)
              .removeOpponentsPieceFromHandThenOpponentsTurn_Detail);
          break;
        case MillFormationActionInPlacingPhase
              .removeOpponentsPieceFromHandThenYourTurn:
          rootScaffoldMessengerKey.currentState!.showSnackBarClear(
              S.of(context).removeOpponentsPieceFromHandThenYourTurn_Detail);
          break;
        case MillFormationActionInPlacingPhase.opponentRemovesOwnPiece:
          rootScaffoldMessengerKey.currentState!
              .showSnackBarClear(S.of(context).opponentRemovesOwnPiece_Detail);
          break;
        case MillFormationActionInPlacingPhase.markAndDelayRemovingPieces:
          rootScaffoldMessengerKey.currentState!.showSnackBarClear(
              S.of(context).markAndDelayRemovingPieces_Detail);
          break;
        case null:
          break;
      }

      logger.t(
          "[config] millFormationActionInPlacingPhase = $millFormationActionInPlacingPhase");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _MillFormationActionInPlacingPhaseModal(
        millFormationActionInPlacingPhase:
            ruleSettings.millFormationActionInPlacingPhase!,
        onChanged: callback,
      ),
    );
  }

  // Moving
  void _setMayMoveInPlacingPhase(
    BuildContext context,
    RuleSettings ruleSettings,
    bool value,
  ) {
    DB().ruleSettings = ruleSettings.copyWith(mayMoveInPlacingPhase: value);

    logger.t("[config] mayMoveInPlacingPhase: $value");

    if (DB().generalSettings.usePerfectDatabase) {
      rootScaffoldMessengerKey.currentState!
          .showSnackBarClear(S.of(context).reopenToTakeEffect);
    }
  }

  void _setIsDefenderMoveFirst(RuleSettings ruleSettings, bool value) {
    DB().ruleSettings = ruleSettings.copyWith(isDefenderMoveFirst: value);

    logger.t("[config] isDefenderMoveFirst: $value");
  }

  void _setStalemateAction(BuildContext context, RuleSettings ruleSettings) {
    void callback(StalemateAction? stalemateAction) {
      Navigator.pop(context);

      DB().ruleSettings =
          ruleSettings.copyWith(stalemateAction: stalemateAction);

      logger.t("[config] stalemateAction = $stalemateAction");

      // TODO: StalemateAction: experimental
      if (stalemateAction != StalemateAction.endWithStalemateLoss &&
          stalemateAction != StalemateAction.changeSideToMove) {
        rootScaffoldMessengerKey.currentState!
            .showSnackBarClear(S.of(context).experimental);
      }
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _StalemateActionModal(
        stalemateAction: ruleSettings.stalemateAction!,
        onChanged: callback,
      ),
    );
  }

  // Removing
  void _setAllowRemovePieceInMill(RuleSettings ruleSettings, bool value) {
    DB().ruleSettings = ruleSettings.copyWith(mayRemoveFromMillsAlways: value);

    logger.t("[config] mayRemoveFromMillsAlways: $value");
  }

  void _setAllowRemoveMultiPiecesWhenCloseMultiMill(
    RuleSettings ruleSettings,
    bool value,
  ) {
    DB().ruleSettings = ruleSettings.copyWith(mayRemoveMultiple: value);

    logger.t("[config] mayRemoveMultiple: $value");
  }

  void _setRestrictRepeatedMillsFormation(
    RuleSettings ruleSettings,
    bool value,
  ) {
    DB().ruleSettings =
        ruleSettings.copyWith(restrictRepeatedMillsFormation: value);

    logger.t("[config] restrictRepeatedMillsFormation: $value");
  }

  Widget _buildRuleSettings(BuildContext context, Box<RuleSettings> box, _) {
    final Locale? locale = DB().displaySettings.locale;

    final RuleSettings ruleSettings = box.get(
      DB.ruleSettingsKey,
      defaultValue: RuleSettings.fromLocale(locale),
    )!;
    return SettingsList(
      children: <Widget>[
        SettingsCard(
          title: Text(S.of(context).general),
          children: <Widget>[
            SettingsListTile(
              titleString: S.of(context).piecesCount,
              subtitleString: S.of(context).piecesCount_Detail,
              trailingString: ruleSettings.piecesCount.toString(),
              onTap: () => _setNTotalPiecesEachSide(context, ruleSettings),
            ),
            SettingsListTile.switchTile(
              value: ruleSettings.hasDiagonalLines,
              onChanged: (bool val) => _setHasDiagonalLines(ruleSettings, val),
              titleString: S.of(context).hasDiagonalLines,
              subtitleString: S.of(context).hasDiagonalLines_Detail,
            ),
            SettingsListTile(
              titleString: S.of(context).nMoveRule,
              subtitleString: S.of(context).nMoveRule_Detail,
              trailingString: ruleSettings.nMoveRule.toString(),
              onTap: () => _setNMoveRule(context, ruleSettings),
            ),
            SettingsListTile(
              titleString: S.of(context).endgameNMoveRule,
              subtitleString: S.of(context).endgameNMoveRule_Detail,
              trailingString: ruleSettings.endgameNMoveRule.toString(),
              onTap: () => _setEndgameNMoveRule(context, ruleSettings),
            ),
            SettingsListTile.switchTile(
              value: ruleSettings.threefoldRepetitionRule,
              onChanged: (bool val) =>
                  _setThreefoldRepetitionRule(ruleSettings, val),
              titleString: S.of(context).threefoldRepetitionRule,
              subtitleString: S.of(context).threefoldRepetitionRule_Detail,
            ),
          ],
        ),
        SettingsCard(
          title: Text(S.of(context).placing),
          children: <Widget>[
            SettingsListTile(
              onTap: () =>
                  _setMillFormationActionInPlacingPhase(context, ruleSettings),
              titleString: S.of(context).whenFormingMillsDuringPlacingPhase,
              subtitleString:
                  S.of(context).whenFormingMillsDuringPlacingPhase_Detail,
            ),
            SettingsListTile(
              onTap: () => _setBoardFullAction(context, ruleSettings),
              titleString: S.of(context).whenBoardIsFull,
              subtitleString: S.of(context).whenBoardIsFull_Detail,
            ),
          ],
        ),
        SettingsCard(
          title: Text(S.of(context).moving),
          children: <Widget>[
            SettingsListTile.switchTile(
              value: ruleSettings.mayMoveInPlacingPhase,
              onChanged: (bool val) =>
                  _setMayMoveInPlacingPhase(context, ruleSettings, val),
              titleString: S.of(context).mayMoveInPlacingPhase,
              subtitleString: S.of(context).mayMoveInPlacingPhase_Detail,
            ),
            SettingsListTile.switchTile(
              value: ruleSettings.isDefenderMoveFirst,
              onChanged: (bool val) =>
                  _setIsDefenderMoveFirst(ruleSettings, val),
              titleString: S.of(context).isDefenderMoveFirst,
              subtitleString: S.of(context).isDefenderMoveFirst_Detail,
            ),
            SettingsListTile(
              onTap: () => _setStalemateAction(context, ruleSettings),
              titleString: S.of(context).whenStalemate,
              subtitleString: S.of(context).whenStalemate_Detail,
            ),
          ],
        ),
        SettingsCard(
          title: Text(S.of(context).mayFly),
          children: <Widget>[
            SettingsListTile.switchTile(
              value: ruleSettings.mayFly,
              onChanged: (bool val) =>
                  _setAllowFlyingAllowed(ruleSettings, val),
              titleString: S.of(context).mayFly,
              subtitleString: S.of(context).mayFly_Detail,
            ),
            SettingsListTile(
              titleString: S.of(context).flyPieceCount,
              subtitleString: S.of(context).flyPieceCount_Detail,
              trailingString: ruleSettings.flyPieceCount.toString(),
              onTap: () => _setFlyPieceCount(context, ruleSettings),
            ),
          ],
        ),
        SettingsCard(
          title: Text(S.of(context).removing),
          children: <Widget>[
            SettingsListTile.switchTile(
              value: ruleSettings.mayRemoveFromMillsAlways,
              onChanged: (bool val) =>
                  _setAllowRemovePieceInMill(ruleSettings, val),
              titleString: S.of(context).mayRemoveFromMillsAlways,
              subtitleString: S.of(context).mayRemoveFromMillsAlways_Detail,
            ),
            SettingsListTile.switchTile(
              value: ruleSettings.mayRemoveMultiple,
              onChanged: (bool val) =>
                  _setAllowRemoveMultiPiecesWhenCloseMultiMill(
                ruleSettings,
                val,
              ),
              titleString: S.of(context).mayRemoveMultiple,
              subtitleString: S.of(context).mayRemoveMultiple_Detail,
            ),
            SettingsListTile.switchTile(
              value: ruleSettings.restrictRepeatedMillsFormation,
              onChanged: (bool val) =>
                  _setRestrictRepeatedMillsFormation(ruleSettings, val),
              titleString: S.of(context).restrictRepeatedMillsFormation,
              subtitleString:
                  S.of(context).restrictRepeatedMillsFormation_Detail,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    visitedRuleSettingsPage = true;

    GameController().isControllerActive = false;
    GameController().reset();

    //MillController().engine.shutdown();

    return BlockSemantics(
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: AppTheme.lightBackgroundColor,
        appBar: AppBar(
          leading: CustomDrawerIcon.of(context)?.drawerIcon,
          title: Text(
            S.of(context).ruleSettings,
            style: AppTheme.appBarTheme.titleTextStyle,
          ),
        ),
        body: ValueListenableBuilder<Box<RuleSettings>>(
          valueListenable: DB().listenRuleSettings,
          builder: _buildRuleSettings,
        ),
      ),
    );
  }
}
