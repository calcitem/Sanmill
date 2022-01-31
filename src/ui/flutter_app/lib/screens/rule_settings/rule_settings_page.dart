// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/models/rule_settings.dart';
import 'package:sanmill/services/database/database.dart';
import 'package:sanmill/services/environment_config.dart';
import 'package:sanmill/services/logger.dart';
import 'package:sanmill/shared/custom_drawer/custom_drawer.dart';
import 'package:sanmill/shared/scaffold_messenger.dart';
import 'package:sanmill/shared/settings/settings.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

part 'package:sanmill/screens/rule_settings/endgame_n_move_rule_modal.dart';
part 'package:sanmill/screens/rule_settings/fly_piece_count_modal.dart';
part 'package:sanmill/screens/rule_settings/n_move_rule_modal.dart';
part 'package:sanmill/screens/rule_settings/piece_count_modal.dart';

class RuleSettingsPage extends StatelessWidget {
  const RuleSettingsPage({Key? key}) : super(key: key);

  // General
  void _setNTotalPiecesEachSide(
    BuildContext context,
    RuleSettings _ruleSettings,
  ) {
    void _callback(int? piecesCount) {
      Navigator.pop(context);

      DB().ruleSettings = _ruleSettings.copyWith(piecesCount: piecesCount);

      logger.v("[config] piecesCount = $piecesCount");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _PieceCountModal(
        piecesCount: _ruleSettings.piecesCount,
        onChanged: _callback,
      ),
    );
  }

  void _setNMoveRule(BuildContext context, RuleSettings _ruleSettings) {
    void _callback(int? nMoveRule) {
      Navigator.pop(context);

      DB().ruleSettings = _ruleSettings.copyWith(nMoveRule: nMoveRule);

      logger.v("[config] nMoveRule = $nMoveRule");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _NMoveRuleModal(
        nMoveRule: _ruleSettings.nMoveRule,
        onChanged: _callback,
      ),
    );
  }

  void _setEndgameNMoveRule(BuildContext context, RuleSettings _ruleSettings) {
    void _callback(int? endgameNMoveRule) {
      Navigator.pop(context);

      DB().ruleSettings =
          _ruleSettings.copyWith(endgameNMoveRule: endgameNMoveRule);

      logger.v("[config] endgameNMoveRule = $endgameNMoveRule");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _EndGameNMoveRuleModal(
        endgameNMoveRule: _ruleSettings.endgameNMoveRule,
        onChanged: _callback,
      ),
    );
  }

  void _setFlyPieceCount(BuildContext context, RuleSettings _ruleSettings) {
    void _callback(int? flyPieceCount) {
      Navigator.pop(context);

      DB().ruleSettings = _ruleSettings.copyWith(flyPieceCount: flyPieceCount);

      logger.v("[config] flyPieceCount = $flyPieceCount");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _FlyPieceCountModal(
        flyPieceCount: _ruleSettings.flyPieceCount,
        onChanged: _callback,
      ),
    );
  }

  void _setHasDiagonalLines(RuleSettings _ruleSettings, bool value) {
    DB().ruleSettings = _ruleSettings.copyWith(hasDiagonalLines: value);

    logger.v("[config] hasDiagonalLines: $value");
  }

  void _setAllowFlyingAllowed(RuleSettings _ruleSettings, bool value) {
    DB().ruleSettings = _ruleSettings.copyWith(mayFly: value);

    logger.v("[config] mayFly: $value");
  }

  void _setThreefoldRepetitionRule(RuleSettings _ruleSettings, bool value) {
    DB().ruleSettings = _ruleSettings.copyWith(threefoldRepetitionRule: value);

    logger.v("[config] threefoldRepetitionRule: $value");
  }

  // Placing
  void _setHasBannedLocations(RuleSettings _ruleSettings, bool value) {
    DB().ruleSettings = _ruleSettings.copyWith(hasBannedLocations: value);

    logger.v("[config] hasBannedLocations: $value");
  }

  void _setIsWhiteLoseButNotDrawWhenBoardFull(
    RuleSettings _ruleSettings,
    bool value,
  ) {
    DB().ruleSettings =
        _ruleSettings.copyWith(isWhiteLoseButNotDrawWhenBoardFull: value);

    logger.v("[config] isWhiteLoseButNotDrawWhenBoardFull: $value");
  }

  void _setMayOnlyRemoveUnplacedPieceInPlacingPhase(
    RuleSettings _ruleSettings,
    bool value,
  ) {
    DB().ruleSettings =
        _ruleSettings.copyWith(mayOnlyRemoveUnplacedPieceInPlacingPhase: value);

    logger.v("[config] mayOnlyRemoveUnplacedPieceInPlacingPhase: $value");
  }

  // Moving
  void _setMayMoveInPlacingPhase(
    BuildContext context,
    RuleSettings _ruleSettings,
    bool value,
  ) {
    DB().ruleSettings = _ruleSettings.copyWith(mayMoveInPlacingPhase: value);

    logger.v("[config] mayMoveInPlacingPhase: $value");

    if (value) {
      ScaffoldMessenger.of(context)
          .showSnackBarClear(S.of(context).experimental);
    }
  }

  void _setIsDefenderMoveFirst(RuleSettings _ruleSettings, bool value) {
    DB().ruleSettings = _ruleSettings.copyWith(isDefenderMoveFirst: value);

    logger.v("[config] isDefenderMoveFirst: $value");
  }

  void _setIsLoseButNotChangeSideWhenNoWay(
    RuleSettings _ruleSettings,
    bool value,
  ) {
    DB().ruleSettings =
        _ruleSettings.copyWith(isLoseButNotChangeSideWhenNoWay: value);

    logger.v("[config] isLoseButNotChangeSideWhenNoWay: $value");
  }

  // Removing
  void _setAllowRemovePieceInMill(RuleSettings _ruleSettings, bool value) {
    DB().ruleSettings = _ruleSettings.copyWith(mayRemoveFromMillsAlways: value);

    logger.v("[config] mayRemoveFromMillsAlways: $value");
  }

  void _setAllowRemoveMultiPiecesWhenCloseMultiMill(
    RuleSettings _ruleSettings,
    bool value,
  ) {
    DB().ruleSettings = _ruleSettings.copyWith(mayRemoveMultiple: value);

    logger.v("[config] mayRemoveMultiple: $value");
  }

  Widget _buildRuleSettings(BuildContext context, Box<RuleSettings> box, _) {
    final locale = DB().displaySettings.languageCode;

    final RuleSettings _ruleSettings = box.get(
      DB.ruleSettingsKey,
      defaultValue: RuleSettings.fromLocale(locale),
    )!;
    return SettingsList(
      children: [
        SettingsCard(
          title: Text(S.of(context).general),
          children: <Widget>[
            SettingsListTile(
              titleString: S.of(context).piecesCount,
              subtitleString: S.of(context).piecesCount_Detail,
              trailingString: _ruleSettings.piecesCount.toString(),
              onTap: () => _setNTotalPiecesEachSide(context, _ruleSettings),
            ),
            SettingsListTile.switchTile(
              value: _ruleSettings.hasDiagonalLines,
              onChanged: (val) => _setHasDiagonalLines(_ruleSettings, val),
              titleString: S.of(context).hasDiagonalLines,
              subtitleString: S.of(context).hasDiagonalLines_Detail,
            ),
            SettingsListTile(
              titleString: S.of(context).nMoveRule,
              subtitleString: S.of(context).nMoveRule_Detail,
              trailingString: _ruleSettings.nMoveRule.toString(),
              onTap: () => _setNMoveRule(context, _ruleSettings),
            ),
            SettingsListTile(
              titleString: S.of(context).endgameNMoveRule,
              subtitleString: S.of(context).endgameNMoveRule_Detail,
              trailingString: _ruleSettings.endgameNMoveRule.toString(),
              onTap: () => _setEndgameNMoveRule(context, _ruleSettings),
            ),
            SettingsListTile.switchTile(
              value: _ruleSettings.threefoldRepetitionRule,
              onChanged: (val) =>
                  _setThreefoldRepetitionRule(_ruleSettings, val),
              titleString: S.of(context).threefoldRepetitionRule,
              subtitleString: S.of(context).threefoldRepetitionRule_Detail,
            ),
          ],
        ),
        SettingsCard(
          title: Text(S.of(context).placing),
          children: <Widget>[
            SettingsListTile.switchTile(
              value: _ruleSettings.hasBannedLocations,
              onChanged: (val) => _setHasBannedLocations(_ruleSettings, val),
              titleString: S.of(context).hasBannedLocations,
              subtitleString: S.of(context).hasBannedLocations_Detail,
            ),
            SettingsListTile.switchTile(
              value: _ruleSettings.isWhiteLoseButNotDrawWhenBoardFull,
              onChanged: (val) =>
                  _setIsWhiteLoseButNotDrawWhenBoardFull(_ruleSettings, val),
              titleString: S.of(context).isWhiteLoseButNotDrawWhenBoardFull,
              subtitleString:
                  S.of(context).isWhiteLoseButNotDrawWhenBoardFull_Detail,
            ),
            SettingsListTile.switchTile(
              value: _ruleSettings.mayOnlyRemoveUnplacedPieceInPlacingPhase,
              onChanged: (val) => _setMayOnlyRemoveUnplacedPieceInPlacingPhase(
                _ruleSettings,
                val,
              ),
              titleString: S.of(context).removeUnplacedPiece,
              subtitleString: S.of(context).removeUnplacedPiece_Detail,
            ),
          ],
        ),
        SettingsCard(
          title: Text(S.of(context).moving),
          children: <Widget>[
            if (EnvironmentConfig.devMode)
              SettingsListTile.switchTile(
                value: _ruleSettings.mayMoveInPlacingPhase,
                onChanged: (val) =>
                    _setMayMoveInPlacingPhase(context, _ruleSettings, val),
                titleString: S.of(context).mayMoveInPlacingPhase,
                subtitleString: S.of(context).mayMoveInPlacingPhase_Detail,
              ),
            SettingsListTile.switchTile(
              value: _ruleSettings.isDefenderMoveFirst,
              onChanged: (val) => _setIsDefenderMoveFirst(_ruleSettings, val),
              titleString: S.of(context).isDefenderMoveFirst,
              subtitleString: S.of(context).isDefenderMoveFirst_Detail,
            ),
            SettingsListTile.switchTile(
              value: _ruleSettings.isLoseButNotChangeSideWhenNoWay,
              onChanged: (val) =>
                  _setIsLoseButNotChangeSideWhenNoWay(_ruleSettings, val),
              titleString: S.of(context).isLoseButNotChangeSideWhenNoWay,
              subtitleString:
                  S.of(context).isLoseButNotChangeSideWhenNoWay_Detail,
            ),
          ],
        ),
        SettingsCard(
          title: Text(S.of(context).mayFly),
          children: <Widget>[
            SettingsListTile.switchTile(
              value: _ruleSettings.mayFly,
              onChanged: (val) => _setAllowFlyingAllowed(_ruleSettings, val),
              titleString: S.of(context).mayFly,
              subtitleString: S.of(context).mayFly_Detail,
            ),
            SettingsListTile(
              titleString: S.of(context).flyPieceCount,
              subtitleString: S.of(context).flyPieceCount_Detail,
              trailingString: _ruleSettings.flyPieceCount.toString(),
              onTap: () => _setFlyPieceCount(context, _ruleSettings),
            ),
          ],
        ),
        SettingsCard(
          title: Text(S.of(context).removing),
          children: <Widget>[
            SettingsListTile.switchTile(
              value: _ruleSettings.mayRemoveFromMillsAlways,
              onChanged: (val) =>
                  _setAllowRemovePieceInMill(_ruleSettings, val),
              titleString: S.of(context).mayRemoveFromMillsAlways,
              subtitleString: S.of(context).mayRemoveFromMillsAlways_Detail,
            ),
            SettingsListTile.switchTile(
              value: _ruleSettings.mayRemoveMultiple,
              onChanged: (val) => _setAllowRemoveMultiPiecesWhenCloseMultiMill(
                _ruleSettings,
                val,
              ),
              titleString: S.of(context).mayRemoveMultiple,
              subtitleString: S.of(context).mayRemoveMultiple_Detail,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightBackgroundColor,
      appBar: AppBar(
        leading: DrawerIcon.of(context)?.icon,
        title: Text(S.of(context).ruleSettings),
      ),
      body: ValueListenableBuilder(
        valueListenable: DB().listenRuleSettings,
        builder: _buildRuleSettings,
      ),
    );
  }
}
