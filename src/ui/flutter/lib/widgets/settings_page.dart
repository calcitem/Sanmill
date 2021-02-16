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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info/package_info.dart';
import 'package:sanmill/common/config.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/mill/rule.dart';
import 'package:sanmill/services/audios.dart';
import 'package:sanmill/services/player.dart';
import 'package:sanmill/style/colors.dart';
import 'package:url_launcher/url_launcher.dart';

import 'edit_page.dart';

class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _version = "";

  @override
  void initState() {
    super.initState();
    loadVersionInfo();
  }

  loadVersionInfo() async {
    //
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _version = '${packageInfo.version} (${packageInfo.buildNumber})';
    });
  }

  setSkillLevel() async {
    //
    callback(int skillLevel) async {
      //
      Navigator.of(context).pop();

      setState(() {
        Config.skillLevel = skillLevel;
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
            title: Text('L1'),
            groupValue: Config.skillLevel,
            value: 10,
            onChanged: callback,
          ),
          Divider(),
          RadioListTile(
            activeColor: UIColors.primaryColor,
            title: Text('L2'),
            groupValue: Config.skillLevel,
            value: 20,
            onChanged: callback,
          ),
          Divider(),
          RadioListTile(
            activeColor: UIColors.primaryColor,
            title: Text('L3'),
            groupValue: Config.skillLevel,
            value: 30,
            onChanged: callback,
          ),
          Divider(),
          SizedBox(height: 56),
        ],
      ),
    );
  }

  setWhoMovesFirst(bool value) async {
    setState(() {
      Config.aiMovesFirst = !value;
    });

    Config.save();
  }

  setIsAutoRestart(bool value) async {
    setState(() {
      Config.isAutoRestart = value;
    });

    Config.save();
  }

  setIsAutoChangeFirstMove(bool value) async {
    setState(() {
      Config.isAutoChangeFirstMove = value;
    });

    Config.save();
  }

  setResignIfMostLose(bool value) async {
    setState(() {
      Config.resignIfMostLose = value;
    });

    Config.save();
  }

  setShufflingEnabled(bool value) async {
    setState(() {
      Config.shufflingEnabled = value;
    });

    Config.save();
  }

  setLearnEndgame(bool value) async {
    setState(() {
      Config.learnEndgame = value;
    });

    Config.save();
  }

  setIdsEnabled(bool value) async {
    setState(() {
      Config.idsEnabled = value;
    });

    Config.save();
  }

  setDepthExtension(bool value) async {
    setState(() {
      Config.depthExtension = value;
    });

    Config.save();
  }

  setOpeningBook(bool value) async {
    setState(() {
      Config.openingBook = value;
    });

    Config.save();
  }

  setMusic(bool value) async {
    //
    setState(() {
      Config.bgmEnabled = value;
    });

    if (Config.bgmEnabled) {
      //Audios.loopBgm('bg_music.mp3');
    } else {
      Audios.stopBgm();
    }

    Config.save();
  }

  setTone(bool value) async {
    //
    setState(() {
      Config.toneEnabled = value;
    });

    Config.save();
  }

  // Rules

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

  changeName() async {
    //
    final newName = await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (context) => EditPage(S.of(context).playerName,
              initValue: Player.shared.name)),
    );

    if (newName != null) nameChanged(newName);
  }

  nameChanged(String newName) async {
    //
    setState(() {
      Player.shared.name = newName;
    });

    Player.shared.saveAndUpload();
  }

  _launchURL(String url) async {
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw 'Could not launch $url';
    }
  }

  showAbout() {
    String mode;
    if (kDebugMode) {
      mode = "(Debug)";
    } else if (kProfileMode) {
      mode = "Profile";
    } else if (kReleaseMode) {
      mode = "";
    } else {
      mode = "Test";
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(S.of(context).about + S.of(context).appName + " " + mode,
            style: TextStyle(color: UIColors.primaryColor)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(height: 5),
            Text(S.of(context).version + ": $_version",
                style: TextStyle(fontFamily: '')),
            SizedBox(height: 15),
            InkWell(
              child: Text(S.of(context).releaseBaseOn,
                  style: TextStyle(
                      fontFamily: '',
                      color: Colors.blue,
                      decoration: TextDecoration.underline)),
              onTap: () =>
                  _launchURL('https://www.gnu.org/licenses/gpl-3.0.html'),
            ),
            SizedBox(height: 15),
            InkWell(
              child: Text(S.of(context).webSite,
                  style: TextStyle(
                      fontFamily: '',
                      color: Colors.blue,
                      decoration: TextDecoration.underline)),
              onTap: () => _launchURL('https://github.com/calcitem/Sanmill'),
            ),
            InkWell(
              child: Text(S.of(context).whatsNew,
                  style: TextStyle(
                      fontFamily: '',
                      color: Colors.blue,
                      decoration: TextDecoration.underline)),
              onTap: () => _launchURL(
                  'https://github.com/calcitem/Sanmill/commits/master'),
            ),
            InkWell(
              child: Text(S.of(context).fastUpdateChannel,
                  style: TextStyle(
                      fontFamily: '',
                      color: Colors.blue,
                      decoration: TextDecoration.underline)),
              onTap: () => _launchURL(
                  'https://github.com/calcitem/Sanmill/actions?query=workflow%3AFlutter+is%3Asuccess'),
            ),
            SizedBox(height: 15),
            InkWell(
              child: Text(S.of(context).thanks),
            ),
            InkWell(
              child: Text(S.of(context).thankWho),
            ),
            InkWell(
              child: Text(S.of(context).stockfish,
                  style: TextStyle(
                      fontFamily: '',
                      color: Colors.blue,
                      decoration: TextDecoration.underline)),
              onTap: () =>
                  _launchURL('https://github.com/official-stockfish/Stockfish'),
            ),
            InkWell(
              child: Text(S.of(context).chessRoad,
                  style: TextStyle(
                      fontFamily: '',
                      color: Colors.blue,
                      decoration: TextDecoration.underline)),
              onTap: () => _launchURL('https://github.com/hezhaoyun/chessroad'),
            ),
            InkWell(
              child: Text(S.of(context).nineChess,
                  style: TextStyle(
                      fontFamily: '',
                      color: Colors.blue,
                      decoration: TextDecoration.underline)),
              onTap: () => _launchURL('https://github.com/liuweilhy/NineChess'),
            ),
          ],
        ),
        actions: <Widget>[
          FlatButton(
              child: Text(S.of(context).ok),
              onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    //
    final TextStyle headerStyle =
        TextStyle(color: UIColors.secondaryColor, fontSize: 20.0);
    final TextStyle itemStyle = TextStyle(color: UIColors.primaryColor);

    return Scaffold(
      backgroundColor: UIColors.lightBackgroundColor,
      appBar: AppBar(title: Text(S.of(context).settings)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 10.0),
            Text(S.of(context).skillLevel, style: headerStyle),
            const SizedBox(height: 10.0),
            Card(
              color: UIColors.boardBackgroundColor,
              elevation: 0.5,
              margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 0),
              child: Column(
                children: <Widget>[
                  ListTile(
                    title: Text(S.of(context).skillLevel, style: itemStyle),
                    trailing:
                        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Text(Config.skillLevel == 10
                          ? 'L1'
                          : Config.skillLevel == 20
                              ? 'L2'
                              : 'L3'),
                      Icon(Icons.keyboard_arrow_right,
                          color: UIColors.secondaryColor),
                    ]),
                    onTap: setSkillLevel,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(S.of(context).sound, style: headerStyle),
            Card(
              color: UIColors.boardBackgroundColor,
              margin: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: <Widget>[
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.bgmEnabled,
                    title: Text(S.of(context).sound, style: itemStyle),
                    onChanged: setMusic,
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.toneEnabled,
                    title: Text(S.of(context).tone, style: itemStyle),
                    onChanged: setTone,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(S.of(context).whoMovesFirst, style: headerStyle),
            Card(
              color: UIColors.boardBackgroundColor,
              margin: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: <Widget>[
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: !Config.aiMovesFirst,
                    title: Text(
                        Config.aiMovesFirst
                            ? S.of(context).ai
                            : S.of(context).human,
                        style: itemStyle),
                    onChanged: setWhoMovesFirst,
                  ),
                ],
              ),
            ),
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
            Text(S.of(context).misc, style: headerStyle),
            Card(
              color: UIColors.boardBackgroundColor,
              margin: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: <Widget>[
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.isAutoRestart,
                    title: Text(S.of(context).isAutoRestart, style: itemStyle),
                    onChanged: setIsAutoRestart,
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.shufflingEnabled,
                    title:
                        Text(S.of(context).shufflingEnabled, style: itemStyle),
                    onChanged: setShufflingEnabled,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(S.of(context).leaderBoard, style: headerStyle),
            Card(
              color: UIColors.boardBackgroundColor,
              margin: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: <Widget>[
                  ListTile(
                    title: Text(S.of(context).playerName, style: itemStyle),
                    trailing:
                        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Text(Player.shared.name),
                      Icon(Icons.keyboard_arrow_right,
                          color: UIColors.secondaryColor),
                    ]),
                    onTap: changeName,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(S.of(context).about, style: headerStyle),
            Card(
              color: UIColors.boardBackgroundColor,
              margin: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: <Widget>[
                  ListTile(
                    title: Text(S.of(context).about + S.of(context).appName,
                        style: itemStyle),
                    trailing:
                        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Text(_version ?? ''),
                      Icon(Icons.keyboard_arrow_right,
                          color: UIColors.secondaryColor),
                    ]),
                    onTap: showAbout,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 60.0),
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
