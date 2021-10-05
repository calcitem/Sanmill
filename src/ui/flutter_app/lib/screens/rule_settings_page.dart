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
import 'package:sanmill/screens/settings/settings_card.dart';
import 'package:sanmill/screens/settings/settings_list_tile.dart';
import 'package:sanmill/screens/settings/settings_switch_list_tile.dart';
import 'package:sanmill/shared/common/config.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

import '../shared/snack_bar.dart';

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
        context: context,
        children: <Widget>[
          SettingsListTile(
            titleString: S.of(context).piecesCount,
            subtitleString: S.of(context).piecesCount_Detail,
            trailingString: Config.piecesCount.toString(),
            onTap: setNTotalPiecesEachSide,
          ),
          SettingsSwitchListTile(
            context: context,
            value: Config.hasDiagonalLines,
            onChanged: setHasDiagonalLines,
            titleString: S.of(context).hasDiagonalLines,
            subtitleString: S.of(context).hasDiagonalLines_Detail,
          ),
          SettingsListTile(
            titleString: S.of(context).nMoveRule,
            subtitleString: S.of(context).nMoveRule_Detail,
            trailingString: Config.nMoveRule.toString(),
            onTap: setNMoveRule,
          ),
          SettingsListTile(
            titleString: S.of(context).endgameNMoveRule,
            subtitleString: S.of(context).endgameNMoveRule_Detail,
            trailingString: Config.endgameNMoveRule.toString(),
            onTap: setEndgameNMoveRule,
          ),
          SettingsSwitchListTile(
            context: context,
            value: Config.threefoldRepetitionRule,
            onChanged: setThreefoldRepetitionRule,
            titleString: S.of(context).threefoldRepetitionRule,
            subtitleString: S.of(context).threefoldRepetitionRule_Detail,
          ),
        ],
      ),
      const SizedBox(height: AppTheme.sizedBoxHeight),
      Text(S.of(context).placing, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        context: context,
        children: <Widget>[
          SettingsSwitchListTile(
            context: context,
            value: Config.hasBannedLocations,
            onChanged: setHasBannedLocations,
            titleString: S.of(context).hasBannedLocations,
            subtitleString: S.of(context).hasBannedLocations_Detail,
          ),
          SettingsSwitchListTile(
            context: context,
            value: Config.isWhiteLoseButNotDrawWhenBoardFull,
            onChanged: setIsWhiteLoseButNotDrawWhenBoardFull,
            titleString: S.of(context).isWhiteLoseButNotDrawWhenBoardFull,
            subtitleString:
                S.of(context).isWhiteLoseButNotDrawWhenBoardFull_Detail,
          ),
          SettingsSwitchListTile(
            context: context,
            value: Config.mayOnlyRemoveUnplacedPieceInPlacingPhase,
            onChanged: setMayOnlyRemoveUnplacedPieceInPlacingPhase,
            titleString: S.of(context).removeUnplacedPiece,
            subtitleString: S.of(context).removeUnplacedPiece_Detail,
          ),
        ],
      ),
      const SizedBox(height: AppTheme.sizedBoxHeight),
      Text(S.of(context).moving, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        context: context,
        children: <Widget>[
          if (Config.experimentsEnabled)
            SettingsSwitchListTile(
              context: context,
              value: Config.mayMoveInPlacingPhase,
              onChanged: setMayMoveInPlacingPhase,
              titleString: S.of(context).mayMoveInPlacingPhase,
              subtitleString: S.of(context).mayMoveInPlacingPhase_Detail,
            )
          else
            SettingsSwitchListTile(
              context: context,
              value: Config.isDefenderMoveFirst,
              onChanged: setIsDefenderMoveFirst,
              titleString: S.of(context).isDefenderMoveFirst,
              subtitleString: S.of(context).isDefenderMoveFirst_Detail,
            ),
          SettingsSwitchListTile(
            context: context,
            value: Config.isLoseButNotChangeSideWhenNoWay,
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
        context: context,
        children: <Widget>[
          SettingsSwitchListTile(
            context: context,
            value: Config.mayFly,
            onChanged: setAllowFlyingAllowed,
            titleString: S.of(context).mayFly,
            subtitleString: S.of(context).mayFly_Detail,
          ),
          SettingsListTile(
            titleString: S.of(context).flyPieceCount,
            subtitleString: S.of(context).flyPieceCount_Detail,
            trailingString: Config.flyPieceCount.toString(),
            onTap: setFlyPieceCount,
          ),
        ],
      ),
      const SizedBox(height: AppTheme.sizedBoxHeight),
      Text(S.of(context).removing, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        context: context,
        children: <Widget>[
          SettingsSwitchListTile(
            context: context,
            value: Config.mayRemoveFromMillsAlways,
            onChanged: setAllowRemovePieceInMill,
            titleString: S.of(context).mayRemoveFromMillsAlways,
            subtitleString: S.of(context).mayRemoveFromMillsAlways_Detail,
          ),
          SettingsSwitchListTile(
            context: context,
            value: Config.mayRemoveMultiple,
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
        () => rule.piecesCount = Config.piecesCount =
            piecesCount ?? (specialCountryAndRegion == "Iran" ? 12 : 9),
      );

      debugPrint("[config] rule.piecesCount: ${rule.piecesCount}");

      Config.save();
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
              groupValue: Config.piecesCount,
              value: 9,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('10'),
              groupValue: Config.piecesCount,
              value: 10,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('11'),
              groupValue: Config.piecesCount,
              value: 11,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('12'),
              groupValue: Config.piecesCount,
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

      setState(() => rule.nMoveRule = Config.nMoveRule = nMoveRule ?? 100);

      debugPrint("[config] rule.nMoveRule: ${rule.nMoveRule}");

      Config.save();
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
              groupValue: Config.nMoveRule,
              value: 30,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('50'),
              groupValue: Config.nMoveRule,
              value: 50,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('60'),
              groupValue: Config.nMoveRule,
              value: 60,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('100'),
              groupValue: Config.nMoveRule,
              value: 100,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('200'),
              groupValue: Config.nMoveRule,
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
        () => rule.endgameNMoveRule =
            Config.endgameNMoveRule = endgameNMoveRule ?? 100,
      );

      debugPrint("[config] rule.endgameNMoveRule: ${rule.endgameNMoveRule}");

      Config.save();
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
              groupValue: Config.endgameNMoveRule,
              value: 5,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('10'),
              groupValue: Config.endgameNMoveRule,
              value: 10,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('20'),
              groupValue: Config.endgameNMoveRule,
              value: 20,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('30'),
              groupValue: Config.endgameNMoveRule,
              value: 30,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('50'),
              groupValue: Config.endgameNMoveRule,
              value: 50,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('60'),
              groupValue: Config.endgameNMoveRule,
              value: 60,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('100'),
              groupValue: Config.endgameNMoveRule,
              value: 100,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('200'),
              groupValue: Config.endgameNMoveRule,
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
        () => rule.flyPieceCount = Config.flyPieceCount = flyPieceCount ?? 3,
      );

      debugPrint("[config] rule.flyPieceCount: ${rule.flyPieceCount}");

      Config.save();
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
              groupValue: Config.flyPieceCount,
              value: 3,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('4'),
              groupValue: Config.flyPieceCount,
              value: 4,
              onChanged: callback,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> setHasDiagonalLines(bool value) async {
    setState(() => rule.hasDiagonalLines = Config.hasDiagonalLines = value);

    debugPrint("[config] rule.hasDiagonalLines: $value");

    Config.save();
  }

  Future<void> setAllowFlyingAllowed(bool value) async {
    setState(() => rule.mayFly = Config.mayFly = value);

    debugPrint("[config] rule.mayFly: $value");

    Config.save();
  }

  Future<void> setThreefoldRepetitionRule(bool value) async {
    setState(
      () =>
          rule.threefoldRepetitionRule = Config.threefoldRepetitionRule = value,
    );

    debugPrint("[config] rule.threefoldRepetitionRule: $value");

    Config.save();
  }

  // Placing

  Future<void> setHasBannedLocations(bool value) async {
    setState(() => rule.hasBannedLocations = Config.hasBannedLocations = value);

    debugPrint("[config] rule.hasBannedLocations: $value");

    Config.save();
  }

  Future<void> setIsWhiteLoseButNotDrawWhenBoardFull(bool value) async {
    setState(
      () => rule.isWhiteLoseButNotDrawWhenBoardFull =
          Config.isWhiteLoseButNotDrawWhenBoardFull = value,
    );

    debugPrint("[config] rule.isWhiteLoseButNotDrawWhenBoardFull: $value");

    Config.save();
  }

  Future<void> setMayOnlyRemoveUnplacedPieceInPlacingPhase(bool value) async {
    setState(
      () => rule.mayOnlyRemoveUnplacedPieceInPlacingPhase =
          Config.mayOnlyRemoveUnplacedPieceInPlacingPhase = value,
    );

    debugPrint(
      "[config] rule.mayOnlyRemoveUnplacedPieceInPlacingPhase: $value",
    );

    Config.save();
  }

  // Moving

  Future<void> setMayMoveInPlacingPhase(bool value) async {
    setState(
      () => rule.mayMoveInPlacingPhase = Config.mayMoveInPlacingPhase = value,
    );

    debugPrint("[config] rule.mayMoveInPlacingPhase: $value");

    Config.save();

    if (value) {
      ScaffoldMessenger.of(context).clearSnackBars();
      showSnackBar(context, S.of(context).experimental);
    }
  }

  Future<void> setIsDefenderMoveFirst(bool value) async {
    setState(
      () => rule.isDefenderMoveFirst = Config.isDefenderMoveFirst = value,
    );

    debugPrint("[config] rule.isDefenderMoveFirst: $value");

    Config.save();
  }

  Future<void> setIsLoseButNotChangeSideWhenNoWay(bool value) async {
    setState(
      () => rule.isLoseButNotChangeSideWhenNoWay =
          Config.isLoseButNotChangeSideWhenNoWay = value,
    );

    debugPrint("[config] rule.isLoseButNotChangeSideWhenNoWay: $value");

    Config.save();
  }

  // Removing

  Future<void> setAllowRemovePieceInMill(bool value) async {
    setState(
      () => rule.mayRemoveFromMillsAlways =
          Config.mayRemoveFromMillsAlways = value,
    );

    debugPrint("[config] rule.mayRemoveFromMillsAlways: $value");

    Config.save();
  }

  Future<void> setAllowRemoveMultiPiecesWhenCloseMultiMill(bool value) async {
    setState(
      () => rule.mayRemoveMultiple = Config.mayRemoveMultiple = value,
    );

    debugPrint("[config] rule.mayRemoveMultiple: $value");

    Config.save();
  }

  // Unused

  Future<void> setNPiecesAtLeast(int value) async {
    setState(() => rule.piecesAtLeastCount = Config.piecesAtLeastCount = value);

    debugPrint("[config] rule.piecesAtLeastCount: $value");

    Config.save();
  }
}
