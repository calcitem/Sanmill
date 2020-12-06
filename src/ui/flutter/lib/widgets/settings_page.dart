/*
  FlutterMill, a mill game playing frontend derived from ChessRoad
  Copyright (C) 2019 He Zhaoyun (ChessRoad author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

  FlutterMill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  FlutterMill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'package:flutter/material.dart';
import 'package:package_info/package_info.dart';
import 'package:sanmill/common/config.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/mill/game.dart';
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

  changeDifficult() {
    //
    callback(int thinkingTime) async {
      //
      Navigator.of(context).pop();

      setState(() {
        Config.thinkingTime = thinkingTime;
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
            groupValue: Config.thinkingTime,
            value: 5000,
            onChanged: callback,
          ),
          Divider(),
          RadioListTile(
            activeColor: UIColors.primaryColor,
            title: Text('L2'),
            groupValue: Config.thinkingTime,
            value: 15000,
            onChanged: callback,
          ),
          Divider(),
          RadioListTile(
            activeColor: UIColors.primaryColor,
            title: Text('L3'),
            groupValue: Config.thinkingTime,
            value: 30000,
            onChanged: callback,
          ),
          Divider(),
          SizedBox(height: 56),
        ],
      ),
    );
  }

  switchWhoMovesFirst(bool value) async {
    setState(() {
      Config.whoMovesFirst = value == true ? PlayerType.human : PlayerType.AI;
    });

    Config.save();
  }

  switchIsAutoRestart(bool value) async {
    setState(() {
      Config.isAutoRestart = value;
    });

    Config.save();
  }

  switchIsAutoChangeFirstMove(bool value) async {
    setState(() {
      Config.isAutoChangeFirstMove = value;
    });

    Config.save();
  }

  switchResignIfMostLose(bool value) async {
    setState(() {
      Config.resignIfMostLose = value;
    });

    Config.save();
  }

  switchRandomMoveEnabled(bool value) async {
    setState(() {
      Config.randomMoveEnabled = value;
    });

    Config.save();
  }

  switchLearnEndgame(bool value) async {
    setState(() {
      Config.learnEndgame = value;
    });

    Config.save();
  }

  switchIdsEnabled(bool value) async {
    setState(() {
      Config.idsEnabled = value;
    });

    Config.save();
  }

  switchDepthExtension(bool value) async {
    setState(() {
      Config.depthExtension = value;
    });

    Config.save();
  }

  switchOpeningBook(bool value) async {
    setState(() {
      Config.openingBook = value;
    });

    Config.save();
  }

  switchMusic(bool value) async {
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

  switchTone(bool value) async {
    //
    setState(() {
      Config.toneEnabled = value;
    });

    Config.save();
  }

  // Rules

  setNTotalPiecesEachSide() {
    //
    callback(int nTotalPiecesEachSide) async {
      //
      Navigator.of(context).pop();

      setState(() {
        Game.shared.position.rule.nTotalPiecesEachSide =
            Config.nTotalPiecesEachSide = nTotalPiecesEachSide;
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
            groupValue: Config.nTotalPiecesEachSide,
            value: 6,
            onChanged: callback,
          ),
          Divider(),
          RadioListTile(
            activeColor: UIColors.primaryColor,
            title: Text('9'),
            groupValue: Config.nTotalPiecesEachSide,
            value: 9,
            onChanged: callback,
          ),
          Divider(),
          RadioListTile(
            activeColor: UIColors.primaryColor,
            title: Text('12'),
            groupValue: Config.nTotalPiecesEachSide,
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
      Game.shared.position.rule.nPiecesAtLeast = Config.nPiecesAtLeast = value;
    });

    Config.save();
  }

  switchHasObliqueLines(bool value) async {
    //
    setState(() {
      Game.shared.position.rule.hasObliqueLines =
          Config.hasObliqueLines = value;
    });

    Config.save();
  }

  switchHasBannedLocations(bool value) async {
    //
    setState(() {
      Game.shared.position.rule.hasBannedLocations =
          Config.hasBannedLocations = value;
    });

    Config.save();
  }

  switchIsDefenderMoveFirst(bool value) async {
    //
    setState(() {
      Game.shared.position.rule.isDefenderMoveFirst =
          Config.isDefenderMoveFirst = value;
    });

    Config.save();
  }

  switchAllowRemoveMultiPiecesWhenCloseMultiMill(bool value) async {
    //
    setState(() {
      Game.shared.position.rule.allowRemoveMultiPiecesWhenCloseMultiMill =
          Config.allowRemoveMultiPiecesWhenCloseMultiMill = value;
    });

    Config.save();
  }

  switchAllowRemovePieceInMill(bool value) async {
    //
    setState(() {
      Game.shared.position.rule.allowRemovePieceInMill =
          Config.allowRemovePieceInMill = value;
    });

    Config.save();
  }

  switchIsBlackLoseButNotDrawWhenBoardFull(bool value) async {
    //
    setState(() {
      Game.shared.position.rule.isBlackLoseButNotDrawWhenBoardFull =
          Config.isBlackLoseButNotDrawWhenBoardFull = value;
    });

    Config.save();
  }

  switchIsLoseButNotChangeSideWhenNoWay(bool value) async {
    //
    setState(() {
      Game.shared.position.rule.isLoseButNotChangeSideWhenNoWay =
          Config.isLoseButNotChangeSideWhenNoWay = value;
    });

    Config.save();
  }

  switchAllowFlyWhenRemainThreePieces(bool value) async {
    //
    setState(() {
      Game.shared.position.rule.allowFlyWhenRemainThreePieces =
          Config.allowFlyWhenRemainThreePieces = value;
    });

    Config.save();
  }

  setMaxStepsLedToDraw(int value) async {
    //
    setState(() {
      Game.shared.position.rule.maxStepsLedToDraw =
          Config.maxStepsLedToDraw = value;
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
    //
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(S.of(context).about + S.of(context).appName,
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
            Text(S.of(context).level, style: headerStyle),
            const SizedBox(height: 10.0),
            Card(
              color: UIColors.boardBackgroundColor,
              elevation: 0.5,
              margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 0),
              child: Column(
                children: <Widget>[
                  ListTile(
                    title: Text(S.of(context).level, style: itemStyle),
                    trailing:
                        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Text(Config.thinkingTime <= 5000
                          ? 'L1'
                          : Config.thinkingTime <= 15000
                              ? 'L2'
                              : 'L3'),
                      Icon(Icons.keyboard_arrow_right,
                          color: UIColors.secondaryColor),
                    ]),
                    onTap: changeDifficult,
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
                    onChanged: switchMusic,
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.toneEnabled,
                    title: Text(S.of(context).tone, style: itemStyle),
                    onChanged: switchTone,
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
                    value: Config.whoMovesFirst == PlayerType.human,
                    title: Text(
                        Config.whoMovesFirst == PlayerType.human
                            ? S.of(context).human
                            : S.of(context).ai,
                        style: itemStyle),
                    onChanged: switchWhoMovesFirst,
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
                    title: Text(S.of(context).nTotalPiecesEachSide,
                        style: itemStyle),
                    trailing:
                        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Text(Config.nTotalPiecesEachSide == 6
                          ? '6'
                          : Config.nTotalPiecesEachSide == 9
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
                    onChanged: switchHasObliqueLines,
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.hasBannedLocations,
                    title: Text(S.of(context).hasBannedLocations,
                        style: itemStyle),
                    onChanged: switchHasBannedLocations,
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.isDefenderMoveFirst,
                    title: Text(S.of(context).isDefenderMoveFirst,
                        style: itemStyle),
                    onChanged: switchIsDefenderMoveFirst,
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.allowRemoveMultiPiecesWhenCloseMultiMill,
                    title: Text(
                        S.of(context).allowRemoveMultiPiecesWhenCloseMultiMill,
                        style: itemStyle),
                    onChanged: switchAllowRemoveMultiPiecesWhenCloseMultiMill,
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.allowRemovePieceInMill,
                    title: Text(S.of(context).allowRemovePieceInMill,
                        style: itemStyle),
                    onChanged: switchAllowRemovePieceInMill,
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.isBlackLoseButNotDrawWhenBoardFull,
                    title: Text(
                        S.of(context).isBlackLoseButNotDrawWhenBoardFull,
                        style: itemStyle),
                    onChanged: switchIsBlackLoseButNotDrawWhenBoardFull,
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.isLoseButNotChangeSideWhenNoWay,
                    title: Text(S.of(context).isLoseButNotChangeSideWhenNoWay,
                        style: itemStyle),
                    onChanged: switchIsLoseButNotChangeSideWhenNoWay,
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.allowFlyWhenRemainThreePieces,
                    title: Text(S.of(context).allowFlyWhenRemainThreePieces,
                        style: itemStyle),
                    onChanged: switchAllowFlyWhenRemainThreePieces,
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
                    onChanged: switchIsAutoRestart,
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    activeColor: UIColors.primaryColor,
                    value: Config.randomMoveEnabled,
                    title:
                        Text(S.of(context).randomMoveEnabled, style: itemStyle),
                    onChanged: switchRandomMoveEnabled,
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
