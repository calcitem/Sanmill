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
import 'package:hive_flutter/hive_flutter.dart' show Box;
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/models/rules.dart';
import 'package:sanmill/services/environment_config.dart';
import 'package:sanmill/services/logger.dart';
import 'package:sanmill/services/storage/storage.dart';
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
  void _setNTotalPiecesEachSide(BuildContext context, Rules _rules) {
    void _callback(int? piecesCount) {
      Navigator.pop(context);

      DB().rules = _rules.copyWith(piecesCount: piecesCount);

      logger.v("[config] piecesCount = $piecesCount");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _PieceCountModal(
        piecesCount: _rules.piecesCount,
        onChanged: _callback,
      ),
    );
  }

  void _setNMoveRule(BuildContext context, Rules _rules) {
    void _callback(int? nMoveRule) {
      Navigator.pop(context);

      DB().rules = _rules.copyWith(nMoveRule: nMoveRule);

      logger.v("[config] nMoveRule = $nMoveRule");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _NMoveRuleModal(
        nMoveRule: _rules.nMoveRule,
        onChanged: _callback,
      ),
    );
  }

  void _setEndgameNMoveRule(BuildContext context, Rules _rules) {
    void _callback(int? endgameNMoveRule) {
      Navigator.pop(context);

      DB().rules = _rules.copyWith(endgameNMoveRule: endgameNMoveRule);

      logger.v("[config] endgameNMoveRule = $endgameNMoveRule");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _EndGameNMoveRuleModal(
        endgameNMoveRule: _rules.endgameNMoveRule,
        onChanged: _callback,
      ),
    );
  }

  void _setFlyPieceCount(BuildContext context, Rules _rules) {
    void _callback(int? flyPieceCount) {
      Navigator.pop(context);

      DB().rules = _rules.copyWith(flyPieceCount: flyPieceCount);

      logger.v("[config] flyPieceCount = $flyPieceCount");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _FlyPieceCountModal(
        flyPieceCount: _rules.flyPieceCount,
        onChanged: _callback,
      ),
    );
  }

  void _setHasDiagonalLines(Rules _rules, bool value) {
    DB().rules = _rules.copyWith(hasDiagonalLines: value);

    logger.v("[config] hasDiagonalLines: $value");
  }

  void _setAllowFlyingAllowed(Rules _rules, bool value) {
    DB().rules = _rules.copyWith(mayFly: value);

    logger.v("[config] mayFly: $value");
  }

  void _setThreefoldRepetitionRule(Rules _rules, bool value) {
    DB().rules = _rules.copyWith(threefoldRepetitionRule: value);

    logger.v("[config] threefoldRepetitionRule: $value");
  }

  // Placing
  void _setHasBannedLocations(Rules _rules, bool value) {
    DB().rules = _rules.copyWith(hasBannedLocations: value);

    logger.v("[config] hasBannedLocations: $value");
  }

  void _setIsWhiteLoseButNotDrawWhenBoardFull(Rules _rules, bool value) {
    DB().rules = _rules.copyWith(isWhiteLoseButNotDrawWhenBoardFull: value);

    logger.v("[config] isWhiteLoseButNotDrawWhenBoardFull: $value");
  }

  void _setMayOnlyRemoveUnplacedPieceInPlacingPhase(Rules _rules, bool value) {
    DB().rules =
        _rules.copyWith(mayOnlyRemoveUnplacedPieceInPlacingPhase: value);

    logger.v("[config] mayOnlyRemoveUnplacedPieceInPlacingPhase: $value");
  }

  // Moving
  void _setMayMoveInPlacingPhase(
    BuildContext context,
    Rules _rules,
    bool value,
  ) {
    DB().rules = _rules.copyWith(mayMoveInPlacingPhase: value);

    logger.v("[config] mayMoveInPlacingPhase: $value");

    if (value) {
      ScaffoldMessenger.of(context)
          .showSnackBarClear(S.of(context).experimental);
    }
  }

  void _setIsDefenderMoveFirst(Rules _rules, bool value) {
    DB().rules = _rules.copyWith(isDefenderMoveFirst: value);

    logger.v("[config] isDefenderMoveFirst: $value");
  }

  void _setIsLoseButNotChangeSideWhenNoWay(Rules _rules, bool value) {
    DB().rules = _rules.copyWith(isLoseButNotChangeSideWhenNoWay: value);

    logger.v("[config] isLoseButNotChangeSideWhenNoWay: $value");
  }

  // Removing
  void _setAllowRemovePieceInMill(Rules _rules, bool value) {
    DB().rules = _rules.copyWith(mayRemoveFromMillsAlways: value);

    logger.v("[config] mayRemoveFromMillsAlways: $value");
  }

  void _setAllowRemoveMultiPiecesWhenCloseMultiMill(Rules _rules, bool value) {
    DB().rules = _rules.copyWith(mayRemoveMultiple: value);

    logger.v("[config] mayRemoveMultiple: $value");
  }

  Widget _buildRules(BuildContext context, Box<Rules> rulesBox, _) {
    final locale = DB().display.languageCode;

    final Rules _rules = rulesBox.get(
      DB.rulesKey,
      defaultValue: Rules.fromLocale(locale),
    )!;
    return SettingsList(
      children: [
        SettingsCard(
          title: Text(S.of(context).general),
          children: <Widget>[
            SettingsListTile(
              titleString: S.of(context).piecesCount,
              subtitleString: S.of(context).piecesCount_Detail,
              trailingString: _rules.piecesCount.toString(),
              onTap: () => _setNTotalPiecesEachSide(context, _rules),
            ),
            SettingsListTile.switchTile(
              value: _rules.hasDiagonalLines,
              onChanged: (val) => _setHasDiagonalLines(_rules, val),
              titleString: S.of(context).hasDiagonalLines,
              subtitleString: S.of(context).hasDiagonalLines_Detail,
            ),
            SettingsListTile(
              titleString: S.of(context).nMoveRule,
              subtitleString: S.of(context).nMoveRule_Detail,
              trailingString: _rules.nMoveRule.toString(),
              onTap: () => _setNMoveRule(context, _rules),
            ),
            SettingsListTile(
              titleString: S.of(context).endgameNMoveRule,
              subtitleString: S.of(context).endgameNMoveRule_Detail,
              trailingString: _rules.endgameNMoveRule.toString(),
              onTap: () => _setEndgameNMoveRule(context, _rules),
            ),
            SettingsListTile.switchTile(
              value: _rules.threefoldRepetitionRule,
              onChanged: (val) => _setThreefoldRepetitionRule(_rules, val),
              titleString: S.of(context).threefoldRepetitionRule,
              subtitleString: S.of(context).threefoldRepetitionRule_Detail,
            ),
          ],
        ),
        SettingsCard(
          title: Text(S.of(context).placing),
          children: <Widget>[
            SettingsListTile.switchTile(
              value: _rules.hasBannedLocations,
              onChanged: (val) => _setHasBannedLocations(_rules, val),
              titleString: S.of(context).hasBannedLocations,
              subtitleString: S.of(context).hasBannedLocations_Detail,
            ),
            SettingsListTile.switchTile(
              value: _rules.isWhiteLoseButNotDrawWhenBoardFull,
              onChanged: (val) =>
                  _setIsWhiteLoseButNotDrawWhenBoardFull(_rules, val),
              titleString: S.of(context).isWhiteLoseButNotDrawWhenBoardFull,
              subtitleString:
                  S.of(context).isWhiteLoseButNotDrawWhenBoardFull_Detail,
            ),
            SettingsListTile.switchTile(
              value: _rules.mayOnlyRemoveUnplacedPieceInPlacingPhase,
              onChanged: (val) =>
                  _setMayOnlyRemoveUnplacedPieceInPlacingPhase(_rules, val),
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
                value: _rules.mayMoveInPlacingPhase,
                onChanged: (val) =>
                    _setMayMoveInPlacingPhase(context, _rules, val),
                titleString: S.of(context).mayMoveInPlacingPhase,
                subtitleString: S.of(context).mayMoveInPlacingPhase_Detail,
              ),
            SettingsListTile.switchTile(
              value: _rules.isDefenderMoveFirst,
              onChanged: (val) => _setIsDefenderMoveFirst(_rules, val),
              titleString: S.of(context).isDefenderMoveFirst,
              subtitleString: S.of(context).isDefenderMoveFirst_Detail,
            ),
            SettingsListTile.switchTile(
              value: _rules.isLoseButNotChangeSideWhenNoWay,
              onChanged: (val) =>
                  _setIsLoseButNotChangeSideWhenNoWay(_rules, val),
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
              value: _rules.mayFly,
              onChanged: (val) => _setAllowFlyingAllowed(_rules, val),
              titleString: S.of(context).mayFly,
              subtitleString: S.of(context).mayFly_Detail,
            ),
            SettingsListTile(
              titleString: S.of(context).flyPieceCount,
              subtitleString: S.of(context).flyPieceCount_Detail,
              trailingString: _rules.flyPieceCount.toString(),
              onTap: () => _setFlyPieceCount(context, _rules),
            ),
          ],
        ),
        SettingsCard(
          title: Text(S.of(context).removing),
          children: <Widget>[
            SettingsListTile.switchTile(
              value: _rules.mayRemoveFromMillsAlways,
              onChanged: (val) => _setAllowRemovePieceInMill(_rules, val),
              titleString: S.of(context).mayRemoveFromMillsAlways,
              subtitleString: S.of(context).mayRemoveFromMillsAlways_Detail,
            ),
            SettingsListTile.switchTile(
              value: _rules.mayRemoveMultiple,
              onChanged: (val) =>
                  _setAllowRemoveMultiPiecesWhenCloseMultiMill(_rules, val),
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
        valueListenable: DB().listenRules,
        builder: _buildRules,
      ),
    );
  }
}
