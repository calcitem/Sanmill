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
import 'package:sanmill/common/config.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/mill/rule.dart';
import 'package:sanmill/style/app_theme.dart';
import 'package:sanmill/widgets/settings_card.dart';
import 'package:sanmill/widgets/settings_list_tile.dart';
import 'package:sanmill/widgets/settings_switch_list_tile.dart';

import 'list_item_divider.dart';

class RuleSettingsPage extends StatefulWidget {
  @override
  _RuleSettingsPageState createState() => _RuleSettingsPageState();
}

class _RuleSettingsPageState extends State<RuleSettingsPage> {
  @override
  void initState() {
    super.initState();
  }

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
            context: context,
            titleString: S.of(context).piecesCount,
            subtitleString: S.of(context).piecesCount_Detail,
            trailingString: Config.piecesCount.toString(),
            onTap: setNTotalPiecesEachSide,
          ),
          ListItemDivider(),
          SettingsSwitchListTile(
            context: context,
            value: Config.hasDiagonalLines,
            onChanged: setHasDiagonalLines,
            titleString: S.of(context).hasDiagonalLines,
            subtitleString: S.of(context).hasDiagonalLines_Detail,
          ),
          ListItemDivider(),
          SettingsListTile(
            context: context,
            titleString: S.of(context).maxStepsLedToDraw,
            subtitleString: S.of(context).maxStepsLedToDraw_Detail,
            trailingString: Config.maxStepsLedToDraw.toString(),
            onTap: setMaxStepsLedToDraw,
          ),
          ListItemDivider(),
        ],
      ),
      SizedBox(height: AppTheme.sizedBoxHeight),
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
          ListItemDivider(),
          SettingsSwitchListTile(
            context: context,
            value: Config.isWhiteLoseButNotDrawWhenBoardFull,
            onChanged: setIsWhiteLoseButNotDrawWhenBoardFull,
            titleString: S.of(context).isWhiteLoseButNotDrawWhenBoardFull,
            subtitleString:
                S.of(context).isWhiteLoseButNotDrawWhenBoardFull_Detail,
          ),
        ],
      ),
      SizedBox(height: AppTheme.sizedBoxHeight),
      Text(S.of(context).moving, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        context: context,
        children: <Widget>[
          SettingsSwitchListTile(
            context: context,
            value: Config.isDefenderMoveFirst,
            onChanged: setIsDefenderMoveFirst,
            titleString: S.of(context).isDefenderMoveFirst,
            subtitleString: S.of(context).isDefenderMoveFirst_Detail,
          ),
          ListItemDivider(),
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
      SizedBox(height: AppTheme.sizedBoxHeight),
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
          ListItemDivider(),
          SettingsListTile(
            context: context,
            titleString: S.of(context).flyPieceCount,
            subtitleString: S.of(context).flyPieceCount_Detail,
            trailingString: Config.flyPieceCount.toString(),
            onTap: setFlyPieceCount,
          ),
        ],
      ),
      SizedBox(height: AppTheme.sizedBoxHeight),
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
          ListItemDivider(),
          SettingsSwitchListTile(
            context: context,
            value: Config.mayRemoveMultiple,
            onChanged: setAllowRemoveMultiPiecesWhenCloseMultiMill,
            titleString: S.of(context).mayRemoveMultiple,
            subtitleString: S.of(context).mayRemoveMultiple_Detail,
          ),
          ListItemDivider(),
        ],
      ),
    ];
  }

  // General

  setNTotalPiecesEachSide() {
    callback(int? piecesCount) async {
      print("[config] piecesCount = $piecesCount");

      Navigator.of(context).pop();

      setState(() {
        rule.piecesCount = Config.piecesCount = piecesCount ?? 9;
      });

      print("[config] rule.piecesCount: ${rule.piecesCount}");

      Config.save();
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          RadioListTile(
            activeColor: AppTheme.switchListTileActiveColor,
            title: Text('9'),
            groupValue: Config.piecesCount,
            value: 9,
            onChanged: callback,
          ),
          ListItemDivider(),
          RadioListTile(
            activeColor: AppTheme.switchListTileActiveColor,
            title: Text('10'),
            groupValue: Config.piecesCount,
            value: 10,
            onChanged: callback,
          ),
          ListItemDivider(),
          RadioListTile(
            activeColor: AppTheme.switchListTileActiveColor,
            title: Text('11'),
            groupValue: Config.piecesCount,
            value: 11,
            onChanged: callback,
          ),
          ListItemDivider(),
          RadioListTile(
            activeColor: AppTheme.switchListTileActiveColor,
            title: Text('12'),
            groupValue: Config.piecesCount,
            value: 12,
            onChanged: callback,
          ),
          ListItemDivider(),
        ],
      ),
    );
  }

  setMaxStepsLedToDraw() {
    callback(int? maxStepsLedToDraw) async {
      print("[config] maxStepsLedToDraw = $maxStepsLedToDraw");

      Navigator.of(context).pop();

      setState(() {
        rule.maxStepsLedToDraw =
            Config.maxStepsLedToDraw = maxStepsLedToDraw ?? 100;
      });

      print("[config] rule.maxStepsLedToDraw: ${rule.maxStepsLedToDraw}");

      Config.save();
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          RadioListTile(
            activeColor: AppTheme.switchListTileActiveColor,
            title: Text('30'),
            groupValue: Config.maxStepsLedToDraw,
            value: 30,
            onChanged: callback,
          ),
          ListItemDivider(),
          RadioListTile(
            activeColor: AppTheme.switchListTileActiveColor,
            title: Text('50'),
            groupValue: Config.maxStepsLedToDraw,
            value: 50,
            onChanged: callback,
          ),
          ListItemDivider(),
          RadioListTile(
            activeColor: AppTheme.switchListTileActiveColor,
            title: Text('100'),
            groupValue: Config.maxStepsLedToDraw,
            value: 100,
            onChanged: callback,
          ),
          ListItemDivider(),
          RadioListTile(
            activeColor: AppTheme.switchListTileActiveColor,
            title: Text('200'),
            groupValue: Config.maxStepsLedToDraw,
            value: 200,
            onChanged: callback,
          ),
          ListItemDivider(),
        ],
      ),
    );
  }

  setFlyPieceCount() {
    callback(int? flyPieceCount) async {
      print("[config] flyPieceCount = $flyPieceCount");

      Navigator.of(context).pop();

      setState(() {
        rule.flyPieceCount = Config.flyPieceCount = flyPieceCount ?? 3;
      });

      print("[config] rule.flyPieceCount: ${rule.flyPieceCount}");

      Config.save();
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          RadioListTile(
            activeColor: AppTheme.switchListTileActiveColor,
            title: Text('3'),
            groupValue: Config.flyPieceCount,
            value: 3,
            onChanged: callback,
          ),
          ListItemDivider(),
          RadioListTile(
            activeColor: AppTheme.switchListTileActiveColor,
            title: Text('4'),
            groupValue: Config.flyPieceCount,
            value: 4,
            onChanged: callback,
          ),
          ListItemDivider(),
        ],
      ),
    );
  }

  setHasDiagonalLines(bool value) async {
    setState(() {
      rule.hasDiagonalLines = Config.hasDiagonalLines = value;
    });

    print("[config] rule.hasDiagonalLines: $value");

    Config.save();
  }

  setAllowFlyingAllowed(bool value) async {
    setState(() {
      rule.mayFly = Config.mayFly = value;
    });

    print("[config] rule.mayFly: $value");

    Config.save();
  }

  // Placing

  setHasBannedLocations(bool value) async {
    setState(() {
      rule.hasBannedLocations = Config.hasBannedLocations = value;
    });

    print("[config] rule.hasBannedLocations: $value");

    Config.save();
  }

  setIsWhiteLoseButNotDrawWhenBoardFull(bool value) async {
    setState(() {
      rule.isWhiteLoseButNotDrawWhenBoardFull =
          Config.isWhiteLoseButNotDrawWhenBoardFull = value;
    });

    print("[config] rule.isWhiteLoseButNotDrawWhenBoardFull: $value");

    Config.save();
  }

  // Moving

  setIsDefenderMoveFirst(bool value) async {
    setState(() {
      rule.isDefenderMoveFirst = Config.isDefenderMoveFirst = value;
    });

    print("[config] rule.isDefenderMoveFirst: $value");

    Config.save();
  }

  setIsLoseButNotChangeSideWhenNoWay(bool value) async {
    setState(() {
      rule.isLoseButNotChangeSideWhenNoWay =
          Config.isLoseButNotChangeSideWhenNoWay = value;
    });

    print("[config] rule.isLoseButNotChangeSideWhenNoWay: $value");

    Config.save();
  }

  // Removing

  setAllowRemovePieceInMill(bool value) async {
    setState(() {
      rule.mayRemoveFromMillsAlways = Config.mayRemoveFromMillsAlways = value;
    });

    print("[config] rule.mayRemoveFromMillsAlways: $value");

    Config.save();
  }

  setAllowRemoveMultiPiecesWhenCloseMultiMill(bool value) async {
    setState(() {
      rule.mayRemoveMultiple = Config.mayRemoveMultiple = value;
    });

    print("[config] rule.mayRemoveMultiple: $value");

    Config.save();
  }

  // Unused

  setNPiecesAtLeast(int value) async {
    setState(() {
      rule.piecesAtLeastCount = Config.piecesAtLeastCount = value;
    });

    print("[config] rule.piecesAtLeastCount: $value");

    Config.save();
  }
}
