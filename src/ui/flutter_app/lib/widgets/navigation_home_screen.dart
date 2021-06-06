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
import 'package:sanmill/engine/engine.dart';
import 'package:sanmill/mill/game.dart';
import 'package:sanmill/style/app_theme.dart';
import 'package:sanmill/style/colors.dart';
import 'package:sanmill/widgets/about_page.dart';
import 'package:sanmill/widgets/drawer_user_controller.dart';
import 'package:sanmill/widgets/help_screen.dart';
import 'package:sanmill/widgets/home_drawer.dart';

import 'game_page.dart';
import 'game_settings_page.dart';
import 'personalization_settings_page.dart';
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
      color: UIColors.nearlyWhite,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Scaffold(
          backgroundColor: AppTheme.navigationHomeScreenBackgroundColor,
          body: DrawerUserController(
            screenIndex: drawerIndex,
            drawerWidth: MediaQuery.of(context).size.width * 0.75,
            onDrawerCall: (DrawerIndex index) {
              // callback from drawer for replace screen
              // as user need with passing DrawerIndex (Enum index)
              changeIndex(index);
            },
            // we replace screen view as
            // we need on navigate starting screens
            screenView: screenView,
          ),
        ),
      ),
    );
  }

  void changeIndex(DrawerIndex index) {
    if (drawerIndex == index) {
      return;
    }

    var drawerMap = {
      DrawerIndex.humanVsAi: EngineType.humanVsAi,
      DrawerIndex.humanVsHuman: EngineType.humanVsHuman,
      DrawerIndex.aiVsAi: EngineType.aiVsAi,
      DrawerIndex.setPosition: EngineType.setPosition,
    };

    drawerIndex = index;

    var engineType = drawerMap[drawerIndex!];
    if (engineType != null) {
      setState(() {
        Game.instance.setWhoIsAi(engineType);
        screenView = GamePage(engineType);
      });
    } else if (drawerIndex == DrawerIndex.preferences) {
      setState(() {
        screenView = GameSettingsPage();
      });
    } else if (drawerIndex == DrawerIndex.ruleSettings) {
      setState(() {
        screenView = RuleSettingsPage();
      });
    } else if (drawerIndex == DrawerIndex.personalization) {
      setState(() {
        screenView = PersonalizationSettingsPage();
      });
    } else if (drawerIndex == DrawerIndex.Help && !Config.developerMode) {
      setState(() {
        screenView = HelpScreen();
      });
    } else if (drawerIndex == DrawerIndex.About && !Config.developerMode) {
      setState(() {
        screenView = AboutPage();
      });
    } else {
      //do in your way......
    }
  }
}
