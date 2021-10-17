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
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/models/rules.dart';
import 'package:sanmill/services/storage/storage.dart';
import 'package:sanmill/shared/settings/settings_card.dart';
import 'package:sanmill/shared/settings/settings_list_tile.dart';
import 'package:sanmill/shared/settings/settings_switch_list_tile.dart';
import 'package:sanmill/shared/snack_bar.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

part 'package:sanmill/screens/rule_settings/fly_piece_count_modal.dart';
part 'package:sanmill/screens/rule_settings/endgame_n_move_rule_modal.dart';
part 'package:sanmill/screens/rule_settings/piece_count_modal.dart';
part 'package:sanmill/screens/rule_settings/n_move_rule_modal.dart';

class RuleSettingsPage extends StatelessWidget {
  const RuleSettingsPage({Key? key}) : super(key: key);

  // General
  void _setNTotalPiecesEachSide(BuildContext context, Rules _rules) {
    void _callback(int? piecesCount) {
      Navigator.pop(context);

      LocalDatabaseService.rules = _rules.copyWith(piecesCount: piecesCount);

      debugPrint("[config] piecesCount = $piecesCount");
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

      LocalDatabaseService.rules = _rules.copyWith(nMoveRule: nMoveRule);

      debugPrint("[config] nMoveRule = $nMoveRule");
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

      LocalDatabaseService.rules =
          _rules.copyWith(endgameNMoveRule: endgameNMoveRule);

      debugPrint("[config] endgameNMoveRule = $endgameNMoveRule");
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

      LocalDatabaseService.rules =
          _rules.copyWith(flyPieceCount: flyPieceCount);

      debugPrint("[config] flyPieceCount = $flyPieceCount");
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
    LocalDatabaseService.rules = _rules.copyWith(hasDiagonalLines: value);

    debugPrint("[config] hasDiagonalLines: $value");
  }

  void _setAllowFlyingAllowed(Rules _rules, bool value) {
    LocalDatabaseService.rules = _rules.copyWith(mayFly: value);

    debugPrint("[config] mayFly: $value");
  }

  void _setThreefoldRepetitionRule(Rules _rules, bool value) {
    LocalDatabaseService.rules =
        _rules.copyWith(threefoldRepetitionRule: value);

    debugPrint("[config] threefoldRepetitionRule: $value");
  }

  // Placing
  void _setHasBannedLocations(Rules _rules, bool value) {
    LocalDatabaseService.rules = _rules.copyWith(hasBannedLocations: value);

    debugPrint("[config] hasBannedLocations: $value");
  }

  void _setIsWhiteLoseButNotDrawWhenBoardFull(Rules _rules, bool value) {
    LocalDatabaseService.rules =
        _rules.copyWith(isWhiteLoseButNotDrawWhenBoardFull: value);

    debugPrint("[config] isWhiteLoseButNotDrawWhenBoardFull: $value");
  }

  void _setMayOnlyRemoveUnplacedPieceInPlacingPhase(Rules _rules, bool value) {
    LocalDatabaseService.rules =
        _rules.copyWith(mayOnlyRemoveUnplacedPieceInPlacingPhase: value);

    debugPrint("[config] mayOnlyRemoveUnplacedPieceInPlacingPhase: $value");
  }

  // Moving
  void _setMayMoveInPlacingPhase(
    BuildContext context,
    Rules _rules,
    bool value,
  ) {
    LocalDatabaseService.rules = _rules.copyWith(mayMoveInPlacingPhase: value);

    debugPrint("[config] mayMoveInPlacingPhase: $value");

    if (value) {
      ScaffoldMessenger.of(context).clearSnackBars();
      showSnackBar(context, S.of(context).experimental);
    }
  }

  void _setIsDefenderMoveFirst(Rules _rules, bool value) {
    LocalDatabaseService.rules = _rules.copyWith(isDefenderMoveFirst: value);

    debugPrint("[config] isDefenderMoveFirst: $value");
  }

  void _setIsLoseButNotChangeSideWhenNoWay(Rules _rules, bool value) {
    LocalDatabaseService.rules =
        _rules.copyWith(isLoseButNotChangeSideWhenNoWay: value);

    debugPrint("[config] isLoseButNotChangeSideWhenNoWay: $value");
  }

  // Removing
  void _setAllowRemovePieceInMill(Rules _rules, bool value) {
    LocalDatabaseService.rules =
        _rules.copyWith(mayRemoveFromMillsAlways: value);

    debugPrint("[config] mayRemoveFromMillsAlways: $value");
  }

  void _setAllowRemoveMultiPiecesWhenCloseMultiMill(Rules _rules, bool value) {
    LocalDatabaseService.rules = _rules.copyWith(mayRemoveMultiple: value);

    debugPrint("[config] mayRemoveMultiple: $value");
  }

  // Unused
  void _setNPiecesAtLeast(Rules _rules, int value) {
    LocalDatabaseService.rules = _rules.copyWith(piecesAtLeastCount: value);

    debugPrint("[config] piecesAtLeastCount: $value");
  }

  Widget _buildRules(BuildContext context, Box<Rules> rulesBox, _) {
    final Rules _rules = rulesBox.get(
      LocalDatabaseService.rulesKey,
      defaultValue: Rules(),
    )!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.of(context).general, style: AppTheme.settingsHeaderStyle),
        SettingsCard(
          children: <Widget>[
            SettingsListTile(
              titleString: S.of(context).piecesCount,
              subtitleString: S.of(context).piecesCount_Detail,
              trailingString: _rules.piecesCount.toString(),
              onTap: () => _setNTotalPiecesEachSide(context, _rules),
            ),
            SettingsSwitchListTile(
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
            SettingsSwitchListTile(
              value: _rules.threefoldRepetitionRule,
              onChanged: (val) => _setThreefoldRepetitionRule(_rules, val),
              titleString: S.of(context).threefoldRepetitionRule,
              subtitleString: S.of(context).threefoldRepetitionRule_Detail,
            ),
          ],
        ),
        const SizedBox(height: AppTheme.sizedBoxHeight),
        Text(S.of(context).placing, style: AppTheme.settingsHeaderStyle),
        SettingsCard(
          children: <Widget>[
            SettingsSwitchListTile(
              value: _rules.hasBannedLocations,
              onChanged: (val) => _setHasBannedLocations(_rules, val),
              titleString: S.of(context).hasBannedLocations,
              subtitleString: S.of(context).hasBannedLocations_Detail,
            ),
            SettingsSwitchListTile(
              value: _rules.isWhiteLoseButNotDrawWhenBoardFull,
              onChanged: (val) =>
                  _setIsWhiteLoseButNotDrawWhenBoardFull(_rules, val),
              titleString: S.of(context).isWhiteLoseButNotDrawWhenBoardFull,
              subtitleString:
                  S.of(context).isWhiteLoseButNotDrawWhenBoardFull_Detail,
            ),
            SettingsSwitchListTile(
              value: _rules.mayOnlyRemoveUnplacedPieceInPlacingPhase,
              onChanged: (val) =>
                  _setMayOnlyRemoveUnplacedPieceInPlacingPhase(_rules, val),
              titleString: S.of(context).removeUnplacedPiece,
              subtitleString: S.of(context).removeUnplacedPiece_Detail,
            ),
          ],
        ),
        const SizedBox(height: AppTheme.sizedBoxHeight),
        Text(S.of(context).moving, style: AppTheme.settingsHeaderStyle),
        SettingsCard(
          children: <Widget>[
            if (LocalDatabaseService.preferences.experimentsEnabled)
              SettingsSwitchListTile(
                value: _rules.mayMoveInPlacingPhase,
                onChanged: (val) =>
                    _setMayMoveInPlacingPhase(context, _rules, val),
                titleString: S.of(context).mayMoveInPlacingPhase,
                subtitleString: S.of(context).mayMoveInPlacingPhase_Detail,
              )
            else
              SettingsSwitchListTile(
                value: _rules.isDefenderMoveFirst,
                onChanged: (val) => _setIsDefenderMoveFirst(_rules, val),
                titleString: S.of(context).isDefenderMoveFirst,
                subtitleString: S.of(context).isDefenderMoveFirst_Detail,
              ),
            SettingsSwitchListTile(
              value: _rules.isLoseButNotChangeSideWhenNoWay,
              onChanged: (val) =>
                  _setIsLoseButNotChangeSideWhenNoWay(_rules, val),
              titleString: S.of(context).isLoseButNotChangeSideWhenNoWay,
              subtitleString:
                  S.of(context).isLoseButNotChangeSideWhenNoWay_Detail,
            ),
          ],
        ),
        const SizedBox(height: AppTheme.sizedBoxHeight),
        Text(S.of(context).mayFly, style: AppTheme.settingsHeaderStyle),
        SettingsCard(
          children: <Widget>[
            SettingsSwitchListTile(
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
        const SizedBox(height: AppTheme.sizedBoxHeight),
        Text(S.of(context).removing, style: AppTheme.settingsHeaderStyle),
        SettingsCard(
          children: <Widget>[
            SettingsSwitchListTile(
              value: _rules.mayRemoveFromMillsAlways,
              onChanged: (val) => _setAllowRemovePieceInMill(_rules, val),
              titleString: S.of(context).mayRemoveFromMillsAlways,
              subtitleString: S.of(context).mayRemoveFromMillsAlways_Detail,
            ),
            SettingsSwitchListTile(
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
      appBar:
          AppBar(centerTitle: true, title: Text(S.of(context).ruleSettings)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ValueListenableBuilder(
          valueListenable: LocalDatabaseService.listenRules,
          builder: _buildRules,
        ),
      ),
    );
  }
}
