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
import 'package:sanmill/style/colors.dart';

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

  setNTotalPiecesEachSide() {
    //
    callback(int? piecesCount) async {
      print("piecesCount = $piecesCount");

      Navigator.of(context).pop();

      setState(() {
        rule.piecesCount = Config.piecesCount = piecesCount ?? 9;
      });

      Config.save();
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(height: 10),
          RadioListTile(
            activeColor: UIColors.primaryColor,
            title: Text('6'),
            groupValue: Config.piecesCount,
            value: 6,
            onChanged: callback,
          ),
          ListItemDivider(),
          RadioListTile(
            activeColor: UIColors.primaryColor,
            title: Text('9'),
            groupValue: Config.piecesCount,
            value: 9,
            onChanged: callback,
          ),
          ListItemDivider(),
          RadioListTile(
            activeColor: UIColors.primaryColor,
            title: Text('12'),
            groupValue: Config.piecesCount,
            value: 12,
            onChanged: callback,
          ),
          ListItemDivider(),
          SizedBox(height: 56),
        ],
      ),
    );
  }

  setNPiecesAtLeast(int value) async {
    //
    setState(() {
      rule.piecesAtLeastCount = Config.piecesAtLeastCount = value;
    });

    Config.save();
  }

  setHasDiagonalLines(bool value) async {
    //
    setState(() {
      rule.hasDiagonalLines = Config.hasDiagonalLines = value;
    });

    Config.save();
  }

  setHasBannedLocations(bool value) async {
    //
    setState(() {
      rule.hasBannedLocations = Config.hasBannedLocations = value;
    });

    Config.save();
  }

  setIsDefenderMoveFirst(bool value) async {
    //
    setState(() {
      rule.isDefenderMoveFirst = Config.isDefenderMoveFirst = value;
    });

    Config.save();
  }

  setAllowRemoveMultiPiecesWhenCloseMultiMill(bool value) async {
    //
    setState(() {
      rule.mayRemoveMultiple = Config.mayRemoveMultiple = value;
    });

    Config.save();
  }

  setAllowRemovePieceInMill(bool value) async {
    //
    setState(() {
      rule.mayRemoveFromMillsAlways = Config.mayRemoveFromMillsAlways = value;
    });

    Config.save();
  }

  setIsBlackLoseButNotDrawWhenBoardFull(bool value) async {
    //
    setState(() {
      rule.isBlackLoseButNotDrawWhenBoardFull =
          Config.isBlackLoseButNotDrawWhenBoardFull = value;
    });

    Config.save();
  }

  setIsLoseButNotChangeSideWhenNoWay(bool value) async {
    //
    setState(() {
      rule.isLoseButNotChangeSideWhenNoWay =
          Config.isLoseButNotChangeSideWhenNoWay = value;
    });

    Config.save();
  }

  setAllowFlyingAllowed(bool value) async {
    //
    setState(() {
      rule.mayFly = Config.mayFly = value;
    });

    Config.save();
  }

  setMaxStepsLedToDraw(int value) async {
    //
    setState(() {
      rule.maxStepsLedToDraw = Config.maxStepsLedToDraw = value;
    });

    Config.save();
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle headerStyle =
        TextStyle(color: UIColors.crusoeColor, fontSize: 20.0);
    final TextStyle itemStyle = TextStyle(color: UIColors.crusoeColor);
    final cardColor = UIColors.floralWhiteColor;

    return Scaffold(
      backgroundColor: UIColors.lightBackgroundColor,
      appBar:
          AppBar(centerTitle: true, title: Text(S.of(context).ruleSettings)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(S.of(context).general, style: headerStyle),
            Card(
              color: cardColor,
              margin: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: <Widget>[
                  ListTile(
                    title: Text(S.of(context).piecesCount, style: itemStyle),
                    subtitle: Text(S.of(context).piecesCount_Detail,
                        style: TextStyle(color: UIColors.secondaryColor)),
                    trailing:
                        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Text(Config.piecesCount == 6
                          ? '6'
                          : Config.piecesCount == 9
                              ? '9'
                              : '12'),
                      Icon(Icons.keyboard_arrow_right,
                          color: UIColors.secondaryColor),
                    ]),
                    onTap: setNTotalPiecesEachSide,
                  ),
                  ListItemDivider(),
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.hasDiagonalLines,
                    title:
                        Text(S.of(context).hasDiagonalLines, style: itemStyle),
                    subtitle: Text(S.of(context).hasDiagonalLines_Detail,
                        style: TextStyle(color: UIColors.secondaryColor)),
                    onChanged: setHasDiagonalLines,
                  ),
                  ListItemDivider(),
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.mayFly,
                    title: Text(S.of(context).mayFly, style: itemStyle),
                    subtitle: Text(S.of(context).mayFly_Detail,
                        style: TextStyle(color: UIColors.secondaryColor)),
                    onChanged: setAllowFlyingAllowed,
                  ),
                  ListItemDivider(),

                  /*
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.maxStepsLedToDraw,
                    title:
                    Text(S.of(context).maxStepsLedToDraw, style: itemStyle),
                    onChanged: setMaxStepsLedToDraw,
                  ),
                  ListItemDivider(),
                  */
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(S.of(context).placing, style: headerStyle),
            Card(
              color: cardColor,
              margin: const EdgeInsets.symmetric(vertical: 10),
              child: Column(children: <Widget>[
                SwitchListTile(
                  activeColor: UIColors.primaryColor,
                  value: Config.hasBannedLocations,
                  title:
                      Text(S.of(context).hasBannedLocations, style: itemStyle),
                  subtitle: Text(S.of(context).hasBannedLocations_Detail,
                      style: TextStyle(color: UIColors.secondaryColor)),
                  onChanged: setHasBannedLocations,
                ),
                ListItemDivider(),
                SwitchListTile(
                  activeColor: UIColors.primaryColor,
                  value: Config.isBlackLoseButNotDrawWhenBoardFull,
                  title: Text(S.of(context).isBlackLoseButNotDrawWhenBoardFull,
                      style: itemStyle),
                  subtitle: Text(
                      S.of(context).isBlackLoseButNotDrawWhenBoardFull_Detail,
                      style: TextStyle(color: UIColors.secondaryColor)),
                  onChanged: setIsBlackLoseButNotDrawWhenBoardFull,
                ),
              ]),
            ),
            Text(S.of(context).moving, style: headerStyle),
            Card(
              color: cardColor,
              margin: const EdgeInsets.symmetric(vertical: 10),
              child: Column(children: <Widget>[
                SwitchListTile(
                  activeColor: UIColors.primaryColor,
                  value: Config.isDefenderMoveFirst,
                  title:
                      Text(S.of(context).isDefenderMoveFirst, style: itemStyle),
                  subtitle: Text(S.of(context).isDefenderMoveFirst_Detail,
                      style: TextStyle(color: UIColors.secondaryColor)),
                  onChanged: setIsDefenderMoveFirst,
                ),
                ListItemDivider(),
                SwitchListTile(
                  activeColor: UIColors.primaryColor,
                  value: Config.isLoseButNotChangeSideWhenNoWay,
                  title: Text(S.of(context).isLoseButNotChangeSideWhenNoWay,
                      style: itemStyle),
                  subtitle: Text(
                      S.of(context).isLoseButNotChangeSideWhenNoWay_Detail,
                      style: TextStyle(color: UIColors.secondaryColor)),
                  onChanged: setIsLoseButNotChangeSideWhenNoWay,
                ),
              ]),
            ),
            Text(S.of(context).removing, style: headerStyle),
            Card(
              color: cardColor,
              margin: const EdgeInsets.symmetric(vertical: 10),
              child: Column(children: <Widget>[
                SwitchListTile(
                  activeColor: UIColors.primaryColor,
                  value: Config.mayRemoveFromMillsAlways,
                  title: Text(S.of(context).mayRemoveFromMillsAlways,
                      style: itemStyle),
                  subtitle: Text(S.of(context).mayRemoveFromMillsAlways_Detail,
                      style: TextStyle(color: UIColors.secondaryColor)),
                  onChanged: setAllowRemovePieceInMill,
                ),
                ListItemDivider(),
                SwitchListTile(
                  activeColor: UIColors.primaryColor,
                  value: Config.mayRemoveMultiple,
                  title:
                      Text(S.of(context).mayRemoveMultiple, style: itemStyle),
                  subtitle: Text(S.of(context).mayRemoveMultiple_Detail,
                      style: TextStyle(color: UIColors.secondaryColor)),
                  onChanged: setAllowRemoveMultiPiecesWhenCloseMultiMill,
                ),
                ListItemDivider(),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
