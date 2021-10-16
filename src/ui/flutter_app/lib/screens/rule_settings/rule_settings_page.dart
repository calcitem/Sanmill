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
import 'package:sanmill/mill/rule.dart';
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
          builder: (context, Box<Rules> rulesBox, _) {
            final Rules _rules = rulesBox.get(
              LocalDatabaseService.rulesKey,
              defaultValue: Rules(),
            )!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.of(context).general,
                  style: AppTheme.settingsHeaderStyle,
                ),
                SettingsCard(
                  children: <Widget>[
                    SettingsListTile(
                      titleString: S.of(context).piecesCount,
                      subtitleString: S.of(context).piecesCount_Detail,
                      trailingString: _rules.piecesCount.toString(),
                      onTap: () => setNTotalPiecesEachSide(context, _rules),
                    ),
                    SettingsSwitchListTile(
                      value: _rules.hasDiagonalLines,
                      onChanged: (val) => setHasDiagonalLines(_rules, val),
                      titleString: S.of(context).hasDiagonalLines,
                      subtitleString: S.of(context).hasDiagonalLines_Detail,
                    ),
                    SettingsListTile(
                      titleString: S.of(context).nMoveRule,
                      subtitleString: S.of(context).nMoveRule_Detail,
                      trailingString: _rules.nMoveRule.toString(),
                      onTap: () => setNMoveRule(context, _rules),
                    ),
                    SettingsListTile(
                      titleString: S.of(context).endgameNMoveRule,
                      subtitleString: S.of(context).endgameNMoveRule_Detail,
                      trailingString: _rules.endgameNMoveRule.toString(),
                      onTap: () => setEndgameNMoveRule(context, _rules),
                    ),
                    SettingsSwitchListTile(
                      value: _rules.threefoldRepetitionRule,
                      onChanged: (val) =>
                          setThreefoldRepetitionRule(_rules, val),
                      titleString: S.of(context).threefoldRepetitionRule,
                      subtitleString:
                          S.of(context).threefoldRepetitionRule_Detail,
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.sizedBoxHeight),
                Text(
                  S.of(context).placing,
                  style: AppTheme.settingsHeaderStyle,
                ),
                SettingsCard(
                  children: <Widget>[
                    SettingsSwitchListTile(
                      value: _rules.hasBannedLocations,
                      onChanged: (val) => setHasBannedLocations(_rules, val),
                      titleString: S.of(context).hasBannedLocations,
                      subtitleString: S.of(context).hasBannedLocations_Detail,
                    ),
                    SettingsSwitchListTile(
                      value: _rules.isWhiteLoseButNotDrawWhenBoardFull,
                      onChanged: (val) => setIsWhiteLoseButNotDrawWhenBoardFull(
                        _rules,
                        val,
                      ),
                      titleString:
                          S.of(context).isWhiteLoseButNotDrawWhenBoardFull,
                      subtitleString: S
                          .of(context)
                          .isWhiteLoseButNotDrawWhenBoardFull_Detail,
                    ),
                    SettingsSwitchListTile(
                      value: _rules.mayOnlyRemoveUnplacedPieceInPlacingPhase,
                      onChanged: (val) =>
                          setMayOnlyRemoveUnplacedPieceInPlacingPhase(
                        _rules,
                        val,
                      ),
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
                            setMayMoveInPlacingPhase(context, _rules, val),
                        titleString: S.of(context).mayMoveInPlacingPhase,
                        subtitleString:
                            S.of(context).mayMoveInPlacingPhase_Detail,
                      )
                    else
                      SettingsSwitchListTile(
                        value: _rules.isDefenderMoveFirst,
                        onChanged: (val) => setIsDefenderMoveFirst(_rules, val),
                        titleString: S.of(context).isDefenderMoveFirst,
                        subtitleString:
                            S.of(context).isDefenderMoveFirst_Detail,
                      ),
                    SettingsSwitchListTile(
                      value: _rules.isLoseButNotChangeSideWhenNoWay,
                      onChanged: (val) => setIsLoseButNotChangeSideWhenNoWay(
                        _rules,
                        val,
                      ),
                      titleString:
                          S.of(context).isLoseButNotChangeSideWhenNoWay,
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
                      onChanged: (val) => setAllowFlyingAllowed(_rules, val),
                      titleString: S.of(context).mayFly,
                      subtitleString: S.of(context).mayFly_Detail,
                    ),
                    SettingsListTile(
                      titleString: S.of(context).flyPieceCount,
                      subtitleString: S.of(context).flyPieceCount_Detail,
                      trailingString: _rules.flyPieceCount.toString(),
                      onTap: () => setFlyPieceCount(context, _rules),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.sizedBoxHeight),
                Text(
                  S.of(context).removing,
                  style: AppTheme.settingsHeaderStyle,
                ),
                SettingsCard(
                  children: <Widget>[
                    SettingsSwitchListTile(
                      value: _rules.mayRemoveFromMillsAlways,
                      onChanged: (val) =>
                          setAllowRemovePieceInMill(_rules, val),
                      titleString: S.of(context).mayRemoveFromMillsAlways,
                      subtitleString:
                          S.of(context).mayRemoveFromMillsAlways_Detail,
                    ),
                    SettingsSwitchListTile(
                      value: _rules.mayRemoveMultiple,
                      onChanged: (val) =>
                          setAllowRemoveMultiPiecesWhenCloseMultiMill(
                        _rules,
                        val,
                      ),
                      titleString: S.of(context).mayRemoveMultiple,
                      subtitleString: S.of(context).mayRemoveMultiple_Detail,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // General

  void setNTotalPiecesEachSide(BuildContext context, Rules _rules) {
    void callback(int? piecesCount) {
      debugPrint("[config] piecesCount = $piecesCount");

      Navigator.pop(context);

      LocalDatabaseService.rules = _rules.copyWith(piecesCount: piecesCount);
      if (piecesCount != null) {
        rule.nMoveRule = piecesCount;
      }

      debugPrint("[config] rule.piecesCount: ${rule.piecesCount}");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _PieceCountModal(
        piecesCount: _rules.piecesCount,
        onChanged: callback,
      ),
    );
  }

  void setNMoveRule(BuildContext context, Rules _rules) {
    void callback(int? nMoveRule) {
      debugPrint("[config] nMoveRule = $nMoveRule");

      Navigator.pop(context);

      LocalDatabaseService.rules = _rules.copyWith(nMoveRule: nMoveRule);
      if (nMoveRule != null) {
        rule.nMoveRule = nMoveRule;
      }

      debugPrint("[config] rule.nMoveRule: ${rule.nMoveRule}");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _NMoveRuleModal(
        nMoveRule: _rules.nMoveRule,
        onChanged: callback,
      ),
    );
  }

  void setEndgameNMoveRule(BuildContext context, Rules _rules) {
    void callback(int? endgameNMoveRule) {
      debugPrint("[config] endgameNMoveRule = $endgameNMoveRule");

      Navigator.pop(context);

      LocalDatabaseService.rules =
          _rules.copyWith(endgameNMoveRule: endgameNMoveRule);
      if (endgameNMoveRule != null) {
        rule.endgameNMoveRule = endgameNMoveRule;
      }

      debugPrint("[config] rule.endgameNMoveRule: ${rule.endgameNMoveRule}");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _EndGameNMoveRuleModal(
        endgameNMoveRule: _rules.endgameNMoveRule,
        onChanged: callback,
      ),
    );
  }

  void setFlyPieceCount(BuildContext context, Rules _rules) {
    void _callback(int? flyPieceCount) {
      debugPrint("[config] flyPieceCount = $flyPieceCount");

      Navigator.pop(context);

      LocalDatabaseService.rules =
          _rules.copyWith(flyPieceCount: flyPieceCount);
      if (flyPieceCount != null) {
        rule.flyPieceCount = flyPieceCount;
      }

      debugPrint("[config] rule.flyPieceCount: ${rule.flyPieceCount}");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _FlyPieceCountModal(
        flyPieceCount: _rules.flyPieceCount,
        onChanged: _callback,
      ),
    );
  }

  void setHasDiagonalLines(Rules _rules, bool value) {
    LocalDatabaseService.rules = _rules.copyWith(
      hasDiagonalLines: value,
    );
    rule.hasDiagonalLines = value;

    debugPrint("[config] rule.hasDiagonalLines: $value");
  }

  void setAllowFlyingAllowed(Rules _rules, bool value) {
    LocalDatabaseService.rules = _rules.copyWith(
      mayFly: value,
    );
    rule.mayFly = value;

    debugPrint("[config] rule.mayFly: $value");
  }

  void setThreefoldRepetitionRule(Rules _rules, bool value) {
    LocalDatabaseService.rules = _rules.copyWith(
      threefoldRepetitionRule: value,
    );
    rule.threefoldRepetitionRule = value;

    debugPrint("[config] rule.threefoldRepetitionRule: $value");
  }

  // Placing

  void setHasBannedLocations(Rules _rules, bool value) {
    LocalDatabaseService.rules = _rules.copyWith(
      hasBannedLocations: value,
    );
    rule.hasBannedLocations = value;

    debugPrint("[config] rule.hasBannedLocations: $value");
  }

  void setIsWhiteLoseButNotDrawWhenBoardFull(Rules _rules, bool value) {
    LocalDatabaseService.rules = _rules.copyWith(
      isWhiteLoseButNotDrawWhenBoardFull: value,
    );
    rule.isWhiteLoseButNotDrawWhenBoardFull = value;

    debugPrint("[config] rule.isWhiteLoseButNotDrawWhenBoardFull: $value");
  }

  void setMayOnlyRemoveUnplacedPieceInPlacingPhase(Rules _rules, bool value) {
    LocalDatabaseService.rules = _rules.copyWith(
      mayOnlyRemoveUnplacedPieceInPlacingPhase: value,
    );
    rule.mayOnlyRemoveUnplacedPieceInPlacingPhase = value;

    debugPrint(
      "[config] rule.mayOnlyRemoveUnplacedPieceInPlacingPhase: $value",
    );
  }

  // Moving

  void setMayMoveInPlacingPhase(
    BuildContext context,
    Rules _rules,
    bool value,
  ) {
    LocalDatabaseService.rules = _rules.copyWith(
      mayMoveInPlacingPhase: value,
    );
    rule.mayMoveInPlacingPhase = value;

    debugPrint("[config] rule.mayMoveInPlacingPhase: $value");

    if (value) {
      ScaffoldMessenger.of(context).clearSnackBars();
      showSnackBar(context, S.of(context).experimental);
    }
  }

  void setIsDefenderMoveFirst(Rules _rules, bool value) {
    LocalDatabaseService.rules = _rules.copyWith(
      isDefenderMoveFirst: value,
    );
    rule.isDefenderMoveFirst = value;

    debugPrint("[config] rule.isDefenderMoveFirst: $value");
  }

  void setIsLoseButNotChangeSideWhenNoWay(Rules _rules, bool value) {
    LocalDatabaseService.rules = _rules.copyWith(
      isLoseButNotChangeSideWhenNoWay: value,
    );
    rule.isLoseButNotChangeSideWhenNoWay = value;

    debugPrint("[config] rule.isLoseButNotChangeSideWhenNoWay: $value");
  }

  // Removing

  void setAllowRemovePieceInMill(Rules _rules, bool value) {
    LocalDatabaseService.rules = _rules.copyWith(
      mayRemoveFromMillsAlways: value,
    );
    rule.mayRemoveFromMillsAlways = value;

    debugPrint("[config] rule.mayRemoveFromMillsAlways: $value");
  }

  void setAllowRemoveMultiPiecesWhenCloseMultiMill(Rules _rules, bool value) {
    LocalDatabaseService.rules = _rules.copyWith(
      mayRemoveMultiple: value,
    );
    rule.mayRemoveMultiple = value;

    debugPrint("[config] rule.mayRemoveMultiple: $value");
  }

  // Unused

  void setNPiecesAtLeast(Rules _rules, int value) {
    LocalDatabaseService.rules = _rules.copyWith(
      piecesAtLeastCount: value,
    );
    rule.piecesAtLeastCount = value;

    debugPrint("[config] rule.piecesAtLeastCount: $value");
  }
}
