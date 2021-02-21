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

class RuleSettingsPage extends StatefulWidget {
  @override
  _RuleSettingsPageState createState() => _RuleSettingsPageState();
}

class _RuleSettingsPageState extends State<RuleSettingsPage> {
  String _version = "";

  @override
  void initState() {
    super.initState();
  }

  setNTotalPiecesEachSide() {
    //
    callback(int piecesCount) async {
      //
      Navigator.of(context).pop();

      setState(() {
        rule.piecesCount = Config.piecesCount = piecesCount;
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
          Divider(),
          RadioListTile(
            activeColor: UIColors.primaryColor,
            title: Text('9'),
            groupValue: Config.piecesCount,
            value: 9,
            onChanged: callback,
          ),
          Divider(),
          RadioListTile(
            activeColor: UIColors.primaryColor,
            title: Text('12'),
            groupValue: Config.piecesCount,
            value: 12,
            onChanged: callback,
          ),
          Divider(),
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

  setHasObliqueLines(bool value) async {
    //
    setState(() {
      rule.hasObliqueLines = Config.hasObliqueLines = value;
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
    //
    final TextStyle headerStyle =
        TextStyle(color: UIColors.secondaryColor, fontSize: 20.0);
    final TextStyle itemStyle = TextStyle(color: UIColors.primaryColor);

    return Scaffold(
      backgroundColor: UIColors.lightBackgroundColor,
      appBar: AppBar(centerTitle: true, title: Text(S.of(context).settings)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 16),
            Text(S.of(context).rules, style: headerStyle),
            Card(
              color: UIColors.boardBackgroundColor,
              margin: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: <Widget>[
                  ListTile(
                    title: Text(S.of(context).piecesCount, style: itemStyle),
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
                  _buildDivider(),
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.hasObliqueLines,
                    title:
                        Text(S.of(context).hasObliqueLines, style: itemStyle),
                    onChanged: setHasObliqueLines,
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.hasBannedLocations,
                    title: Text(S.of(context).hasBannedLocations,
                        style: itemStyle),
                    onChanged: setHasBannedLocations,
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.isDefenderMoveFirst,
                    title: Text(S.of(context).isDefenderMoveFirst,
                        style: itemStyle),
                    onChanged: setIsDefenderMoveFirst,
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.mayRemoveMultiple,
                    title:
                        Text(S.of(context).mayRemoveMultiple, style: itemStyle),
                    onChanged: setAllowRemoveMultiPiecesWhenCloseMultiMill,
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.mayRemoveFromMillsAlways,
                    title: Text(S.of(context).mayRemoveFromMillsAlways,
                        style: itemStyle),
                    onChanged: setAllowRemovePieceInMill,
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.isBlackLoseButNotDrawWhenBoardFull,
                    title: Text(
                        S.of(context).isBlackLoseButNotDrawWhenBoardFull,
                        style: itemStyle),
                    onChanged: setIsBlackLoseButNotDrawWhenBoardFull,
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.isLoseButNotChangeSideWhenNoWay,
                    title: Text(S.of(context).isLoseButNotChangeSideWhenNoWay,
                        style: itemStyle),
                    onChanged: setIsLoseButNotChangeSideWhenNoWay,
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.mayFly,
                    title: Text(S.of(context).mayFly, style: itemStyle),
                    onChanged: setAllowFlyingAllowed,
                  ),
                  _buildDivider(),
                  /*
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.maxStepsLedToDraw,
                    title:
                    Text(S.of(context).maxStepsLedToDraw, style: itemStyle),
                    onChanged: setMaxStepsLedToDraw,
                  ),
                  _buildDivider(),
                  */
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Container _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      width: double.infinity,
      height: 1.0,
      color: UIColors.lightLineColor,
    );
  }
}
