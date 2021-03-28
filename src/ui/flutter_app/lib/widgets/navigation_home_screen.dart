import 'package:flutter/material.dart';
import 'package:sanmill/engine/engine.dart';
import 'package:sanmill/mill/game.dart';
import 'package:sanmill/style/app_theme.dart';
import 'package:sanmill/widgets/about_page.dart';
import 'package:sanmill/widgets/drawer_user_controller.dart';
import 'package:sanmill/widgets/help_screen.dart';
import 'package:sanmill/widgets/home_drawer.dart';

import 'game_page.dart';
import 'game_settings_page.dart';
import 'rule_settings_page.dart';

class NavigationHomeScreen extends StatefulWidget {
  @override
  _NavigationHomeScreenState createState() => _NavigationHomeScreenState();
}

class _NavigationHomeScreenState extends State<NavigationHomeScreen> {
  Widget? screenView;
  DrawerIndex? drawerIndex;

  @override
  void initState() {
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

    var engineType = drawerMap[drawerIndex!];
    if (engineType != null) {
      setState(() {
        Game.instance.setWhoIsAi(engineType);
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
        screenView = AboutPage();
      });
    } else {
      //do in your way......
    }
  }
}
