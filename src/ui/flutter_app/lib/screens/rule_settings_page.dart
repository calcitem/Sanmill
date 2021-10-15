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
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/l10n/resources.dart';
import 'package:sanmill/mill/rule.dart';
import 'package:sanmill/services/storage/storage.dart';
import 'package:sanmill/shared/settings/settings_card.dart';
import 'package:sanmill/shared/settings/settings_list_tile.dart';
import 'package:sanmill/shared/settings/settings_switch_list_tile.dart';
import 'package:sanmill/shared/snack_bar.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

class RuleSettingsPage extends StatefulWidget {
  @override
  _RuleSettingsPageState createState() => _RuleSettingsPageState();
}

class _RuleSettingsPageState extends State<RuleSettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightBackgroundColor,
      appBar:
          AppBar(centerTitle: true, title: Text(S.of(context).ruleSettings)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children(context),
        ),
      ),
    );
  }

  List<Widget> children(BuildContext context) {
    return <Widget>[
      Text(S.of(context).general, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        children: <Widget>[
          SettingsListTile(
            titleString: S.of(context).piecesCount,
            subtitleString: S.of(context).piecesCount_Detail,
            trailingString: LocalDatabaseService.rules.piecesCount.toString(),
            onTap: setNTotalPiecesEachSide,
          ),
          SettingsSwitchListTile(
            value: LocalDatabaseService.rules.hasDiagonalLines,
            onChanged: setHasDiagonalLines,
            titleString: S.of(context).hasDiagonalLines,
            subtitleString: S.of(context).hasDiagonalLines_Detail,
          ),
          SettingsListTile(
            titleString: S.of(context).nMoveRule,
            subtitleString: S.of(context).nMoveRule_Detail,
            trailingString: LocalDatabaseService.rules.nMoveRule.toString(),
            onTap: setNMoveRule,
          ),
          SettingsListTile(
            titleString: S.of(context).endgameNMoveRule,
            subtitleString: S.of(context).endgameNMoveRule_Detail,
            trailingString:
                LocalDatabaseService.rules.endgameNMoveRule.toString(),
            onTap: setEndgameNMoveRule,
          ),
          SettingsSwitchListTile(
            value: LocalDatabaseService.rules.threefoldRepetitionRule,
            onChanged: setThreefoldRepetitionRule,
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
            value: LocalDatabaseService.rules.hasBannedLocations,
            onChanged: setHasBannedLocations,
            titleString: S.of(context).hasBannedLocations,
            subtitleString: S.of(context).hasBannedLocations_Detail,
          ),
          SettingsSwitchListTile(
            value:
                LocalDatabaseService.rules.isWhiteLoseButNotDrawWhenBoardFull,
            onChanged: setIsWhiteLoseButNotDrawWhenBoardFull,
            titleString: S.of(context).isWhiteLoseButNotDrawWhenBoardFull,
            subtitleString:
                S.of(context).isWhiteLoseButNotDrawWhenBoardFull_Detail,
          ),
          SettingsSwitchListTile(
            value: LocalDatabaseService
                .rules.mayOnlyRemoveUnplacedPieceInPlacingPhase,
            onChanged: setMayOnlyRemoveUnplacedPieceInPlacingPhase,
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
              value: LocalDatabaseService.rules.mayMoveInPlacingPhase,
              onChanged: setMayMoveInPlacingPhase,
              titleString: S.of(context).mayMoveInPlacingPhase,
              subtitleString: S.of(context).mayMoveInPlacingPhase_Detail,
            )
          else
            SettingsSwitchListTile(
              value: LocalDatabaseService.rules.isDefenderMoveFirst,
              onChanged: setIsDefenderMoveFirst,
              titleString: S.of(context).isDefenderMoveFirst,
              subtitleString: S.of(context).isDefenderMoveFirst_Detail,
            ),
          SettingsSwitchListTile(
            value: LocalDatabaseService.rules.isLoseButNotChangeSideWhenNoWay,
            onChanged: setIsLoseButNotChangeSideWhenNoWay,
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
            value: LocalDatabaseService.rules.mayFly,
            onChanged: setAllowFlyingAllowed,
            titleString: S.of(context).mayFly,
            subtitleString: S.of(context).mayFly_Detail,
          ),
          SettingsListTile(
            titleString: S.of(context).flyPieceCount,
            subtitleString: S.of(context).flyPieceCount_Detail,
            trailingString: LocalDatabaseService.rules.flyPieceCount.toString(),
            onTap: setFlyPieceCount,
          ),
        ],
      ),
      const SizedBox(height: AppTheme.sizedBoxHeight),
      Text(S.of(context).removing, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        children: <Widget>[
          SettingsSwitchListTile(
            value: LocalDatabaseService.rules.mayRemoveFromMillsAlways,
            onChanged: setAllowRemovePieceInMill,
            titleString: S.of(context).mayRemoveFromMillsAlways,
            subtitleString: S.of(context).mayRemoveFromMillsAlways_Detail,
          ),
          SettingsSwitchListTile(
            value: LocalDatabaseService.rules.mayRemoveMultiple,
            onChanged: setAllowRemoveMultiPiecesWhenCloseMultiMill,
            titleString: S.of(context).mayRemoveMultiple,
            subtitleString: S.of(context).mayRemoveMultiple_Detail,
          ),
        ],
      ),
    ];
  }

  // General

  void setNTotalPiecesEachSide() {
    Future<void> callback(int? piecesCount) async {
      debugPrint("[config] piecesCount = $piecesCount");

      Navigator.pop(context);

      setState(
        () => rule.piecesCount = LocalDatabaseService.rules.piecesCount =
            piecesCount ?? (specialCountryAndRegion == "Iran" ? 12 : 9),
      );

      debugPrint("[config] rule.piecesCount: ${rule.piecesCount}");
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) => Semantics(
        label: S.of(context).piecesCount,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('9'),
              groupValue: LocalDatabaseService.rules.piecesCount,
              value: 9,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('10'),
              groupValue: LocalDatabaseService.rules.piecesCount,
              value: 10,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('11'),
              groupValue: LocalDatabaseService.rules.piecesCount,
              value: 11,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('12'),
              groupValue: LocalDatabaseService.rules.piecesCount,
              value: 12,
              onChanged: callback,
            ),
          ],
        ),
      ),
    );
  }

  void setNMoveRule() {
    Future<void> callback(int? nMoveRule) async {
      debugPrint("[config] nMoveRule = $nMoveRule");

      Navigator.pop(context);

      setState(
        () => rule.nMoveRule =
            LocalDatabaseService.rules.nMoveRule = nMoveRule ?? 100,
      );

      debugPrint("[config] rule.nMoveRule: ${rule.nMoveRule}");
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) => Semantics(
        label: S.of(context).nMoveRule,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('30'),
              groupValue: LocalDatabaseService.rules.nMoveRule,
              value: 30,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('50'),
              groupValue: LocalDatabaseService.rules.nMoveRule,
              value: 50,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('60'),
              groupValue: LocalDatabaseService.rules.nMoveRule,
              value: 60,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('100'),
              groupValue: LocalDatabaseService.rules.nMoveRule,
              value: 100,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('200'),
              groupValue: LocalDatabaseService.rules.nMoveRule,
              value: 200,
              onChanged: callback,
            ),
          ],
        ),
      ),
    );
  }

  void setEndgameNMoveRule() {
    Future<void> callback(int? endgameNMoveRule) async {
      debugPrint("[config] endgameNMoveRule = $endgameNMoveRule");

      Navigator.pop(context);

      setState(
        () => rule.endgameNMoveRule = LocalDatabaseService
            .rules.endgameNMoveRule = endgameNMoveRule ?? 100,
      );

      debugPrint("[config] rule.endgameNMoveRule: ${rule.endgameNMoveRule}");
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) => Semantics(
        label: S.of(context).endgameNMoveRule,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('5'),
              groupValue: LocalDatabaseService.rules.endgameNMoveRule,
              value: 5,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('10'),
              groupValue: LocalDatabaseService.rules.endgameNMoveRule,
              value: 10,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('20'),
              groupValue: LocalDatabaseService.rules.endgameNMoveRule,
              value: 20,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('30'),
              groupValue: LocalDatabaseService.rules.endgameNMoveRule,
              value: 30,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('50'),
              groupValue: LocalDatabaseService.rules.endgameNMoveRule,
              value: 50,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('60'),
              groupValue: LocalDatabaseService.rules.endgameNMoveRule,
              value: 60,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('100'),
              groupValue: LocalDatabaseService.rules.endgameNMoveRule,
              value: 100,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('200'),
              groupValue: LocalDatabaseService.rules.endgameNMoveRule,
              value: 200,
              onChanged: callback,
            ),
          ],
        ),
      ),
    );
  }

  void setFlyPieceCount() {
    Future<void> callback(int? flyPieceCount) async {
      debugPrint("[config] flyPieceCount = $flyPieceCount");

      Navigator.pop(context);

      setState(
        () => rule.flyPieceCount =
            LocalDatabaseService.rules.flyPieceCount = flyPieceCount ?? 3,
      );

      debugPrint("[config] rule.flyPieceCount: ${rule.flyPieceCount}");
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) => Semantics(
        label: S.of(context).flyPieceCount,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('3'),
              groupValue: LocalDatabaseService.rules.flyPieceCount,
              value: 3,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('4'),
              groupValue: LocalDatabaseService.rules.flyPieceCount,
              value: 4,
              onChanged: callback,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> setHasDiagonalLines(bool value) async {
    setState(
      () => rule.hasDiagonalLines =
          LocalDatabaseService.rules.hasDiagonalLines = value,
    );

    debugPrint("[config] rule.hasDiagonalLines: $value");
  }

  Future<void> setAllowFlyingAllowed(bool value) async {
    setState(() => rule.mayFly = LocalDatabaseService.rules.mayFly = value);

    debugPrint("[config] rule.mayFly: $value");
  }

  Future<void> setThreefoldRepetitionRule(bool value) async {
    setState(
      () => rule.threefoldRepetitionRule =
          LocalDatabaseService.rules.threefoldRepetitionRule = value,
    );

    debugPrint("[config] rule.threefoldRepetitionRule: $value");
  }

  // Placing

  Future<void> setHasBannedLocations(bool value) async {
    setState(
      () => rule.hasBannedLocations =
          LocalDatabaseService.rules.hasBannedLocations = value,
    );

    debugPrint("[config] rule.hasBannedLocations: $value");
  }

  Future<void> setIsWhiteLoseButNotDrawWhenBoardFull(bool value) async {
    setState(
      () => rule.isWhiteLoseButNotDrawWhenBoardFull =
          LocalDatabaseService.rules.isWhiteLoseButNotDrawWhenBoardFull = value,
    );

    debugPrint("[config] rule.isWhiteLoseButNotDrawWhenBoardFull: $value");
  }

  Future<void> setMayOnlyRemoveUnplacedPieceInPlacingPhase(bool value) async {
    setState(
      () => rule.mayOnlyRemoveUnplacedPieceInPlacingPhase = LocalDatabaseService
          .rules.mayOnlyRemoveUnplacedPieceInPlacingPhase = value,
    );

    debugPrint(
      "[config] rule.mayOnlyRemoveUnplacedPieceInPlacingPhase: $value",
    );
  }

  // Moving

  Future<void> setMayMoveInPlacingPhase(bool value) async {
    setState(
      () => rule.mayMoveInPlacingPhase =
          LocalDatabaseService.rules.mayMoveInPlacingPhase = value,
    );

    debugPrint("[config] rule.mayMoveInPlacingPhase: $value");

    if (value) {
      ScaffoldMessenger.of(context).clearSnackBars();
      showSnackBar(context, S.of(context).experimental);
    }
  }

  Future<void> setIsDefenderMoveFirst(bool value) async {
    setState(
      () => rule.isDefenderMoveFirst =
          LocalDatabaseService.rules.isDefenderMoveFirst = value,
    );

    debugPrint("[config] rule.isDefenderMoveFirst: $value");
  }

  Future<void> setIsLoseButNotChangeSideWhenNoWay(bool value) async {
    setState(
      () => rule.isLoseButNotChangeSideWhenNoWay =
          LocalDatabaseService.rules.isLoseButNotChangeSideWhenNoWay = value,
    );

    debugPrint("[config] rule.isLoseButNotChangeSideWhenNoWay: $value");
  }

  // Removing

  Future<void> setAllowRemovePieceInMill(bool value) async {
    setState(
      () => rule.mayRemoveFromMillsAlways =
          LocalDatabaseService.rules.mayRemoveFromMillsAlways = value,
    );

    debugPrint("[config] rule.mayRemoveFromMillsAlways: $value");
  }

  Future<void> setAllowRemoveMultiPiecesWhenCloseMultiMill(bool value) async {
    setState(
      () => rule.mayRemoveMultiple =
          LocalDatabaseService.rules.mayRemoveMultiple = value,
    );

    debugPrint("[config] rule.mayRemoveMultiple: $value");
  }

  // Unused

  Future<void> setNPiecesAtLeast(int value) async {
    setState(
      () => rule.piecesAtLeastCount =
          LocalDatabaseService.rules.piecesAtLeastCount = value,
    );

    debugPrint("[config] rule.piecesAtLeastCount: $value");
  }
}
