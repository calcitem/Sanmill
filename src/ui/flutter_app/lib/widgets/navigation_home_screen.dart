import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info/package_info.dart';
import 'package:sanmill/engine/engine.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/mill/game.dart';
import 'package:sanmill/style/app_theme.dart';
import 'package:sanmill/style/colors.dart';
import 'package:sanmill/widgets/drawer_user_controller.dart';
import 'package:sanmill/widgets/help_screen.dart';
import 'package:sanmill/widgets/home_drawer.dart';
import 'package:url_launcher/url_launcher.dart';

import 'game_page.dart';
import 'game_settings_page.dart';
import 'rule_settings_page.dart';

class NavigationHomeScreen extends StatefulWidget {
  @override
  _NavigationHomeScreenState createState() => _NavigationHomeScreenState();
}

class _NavigationHomeScreenState extends State<NavigationHomeScreen> {
  Widget screenView;
  DrawerIndex drawerIndex;
  String _version = "";

  @override
  void initState() {
    loadVersionInfo();
    drawerIndex = DrawerIndex.humanVsAi;
    screenView = GamePage(EngineType.humanVsAi);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.nearlyWhite,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Scaffold(
          backgroundColor: AppTheme.nearlyWhite,
          body: DrawerUserController(
            screenIndex: drawerIndex,
            drawerWidth: MediaQuery.of(context).size.width * 0.75,
            onDrawerCall: (DrawerIndex drawerIndexData) {
              changeIndex(drawerIndexData);
              //callback from drawer for replace screen as user need with passing DrawerIndex(Enum index)
            },
            screenView: screenView,
            //we replace screen view as we need on navigate starting screens like MyHomePage, HelpScreen, FeedbackScreen, etc...
          ),
        ),
      ),
    );
  }

  void changeIndex(DrawerIndex drawerIndexdata) {
    if (drawerIndex == drawerIndexdata) {
      return;
    }

    var drawerMap = {
      DrawerIndex.humanVsAi: EngineType.humanVsAi,
      DrawerIndex.humanVsHuman: EngineType.humanVsHuman,
      DrawerIndex.aiVsAi: EngineType.aiVsAi,
    };

    drawerIndex = drawerIndexdata;

    var engineType = drawerMap[drawerIndex];
    if (engineType != null) {
      setState(() {
        Game.shared.setWhoIsAi(engineType);
        screenView = GamePage(engineType);
      });
    } else if (drawerIndex == DrawerIndex.settings) {
      setState(() {
        screenView = GameSettingsPage();
      });
    } else if (drawerIndex == DrawerIndex.ruleSettings) {
      setState(() {
        screenView = RuleSettingsPage();
      });
    } else if (drawerIndex == DrawerIndex.Help) {
      setState(() {
        screenView = HelpScreen();
      });
    } else if (drawerIndex == DrawerIndex.About) {
      setState(() {
        showAbout();
      });
    } else {
      //do in your way......
    }
  }

  loadVersionInfo() async {
    if (Platform.isWindows) {
      setState(() {
        _version = 'Unknown version';
      });
    } else {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _version = '${packageInfo.version} (${packageInfo.buildNumber})';
      });
    }
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
          TextButton(
              child: Text(S.of(context).ok),
              onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}
