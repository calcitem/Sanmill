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
import 'package:sanmill/engine/engine.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/main.dart';
import 'package:sanmill/style/colors.dart';

import 'game_page.dart';
import 'settings_page.dart';

class MainMenu extends StatefulWidget {
  @override
  _MainMenuState createState() => _MainMenuState();
}

class _MainMenuState extends State<MainMenu> with TickerProviderStateMixin {
  AnimationController inController, shadowController;
  Animation inAnimation, shadowAnimation;

  @override
  void initState() {
    super.initState();

    inController = AnimationController(
      duration: Duration(milliseconds: 600),
      vsync: this,
    );
    inAnimation = CurvedAnimation(parent: inController, curve: Curves.bounceIn);
    inAnimation = new Tween(begin: 1.6, end: 1.0).animate(inController);

    shadowController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );
    shadowAnimation =
        new Tween(begin: 0.0, end: 12.0).animate(shadowController);

    inController.addStatusListener((status) {
      if (status == AnimationStatus.completed) shadowController.forward();
    });
    shadowController.addStatusListener((status) {
      if (status == AnimationStatus.completed) shadowController.reverse();
    });

    /// use 'try...catch' to avoid exception -
    /// 'setState() or markNeedsBuild() called during build.'
    inAnimation.addListener(() {
      try {
        setState(() {});
      } catch (e) {}
    });
    shadowAnimation.addListener(() {
      try {
        setState(() {});
      } catch (e) {}
    });

    inController.forward();
  }

  navigateTo(Widget page) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => page));

    inController.reset();
    shadowController.reset();
    inController.forward();
  }

  @override
  Widget build(BuildContext context) {
    //
    final appNameShadow = Shadow(
      color: Color.fromARGB(0x99, 66, 0, 0),
      offset: Offset(0, shadowAnimation.value / 2),
      blurRadius: shadowAnimation.value,
    );
    final menuItemShadow = Shadow(
      color: Color.fromARGB(0x7F, 0, 0, 0),
      offset: Offset(0, shadowAnimation.value / 6),
      blurRadius: shadowAnimation.value / 3,
    );

    final appNameStyle = TextStyle(
      fontSize: 48,
      color: Colors.black,
      shadows: [appNameShadow],
    );

    final menuItemStyle = TextStyle(
      fontSize: 28,
      color: UIColors.primaryColor,
      shadows: [menuItemShadow],
    );

    final menuItems = Center(
      child: Column(
        children: <Widget>[
          Expanded(child: SizedBox()),
          Transform.scale(
            scale: inAnimation.value,
            child: Text(S.of(context).appName,
                style: appNameStyle, textAlign: TextAlign.center),
          ),
          Expanded(child: SizedBox()),
          FlatButton(
            child: Text(S.of(context).humanVsAi, style: menuItemStyle),
            onPressed: () => navigateTo(GamePage(EngineType.humanVsAi)),
          ),
          Expanded(child: SizedBox()),
          FlatButton(
            child: Text(S.of(context).humanVsHuman, style: menuItemStyle),
            onPressed: () => navigateTo(GamePage(EngineType.humanVsHuman)),
          ),
          Expanded(child: SizedBox()),
          FlatButton(
            child: Text(S.of(context).aiVsAi, style: menuItemStyle),
            onPressed: () => navigateTo(GamePage(EngineType.aiVsAi)),
          ),
          Expanded(child: SizedBox()),
          FlatButton(
            child: Text(S.of(context).testViaLAN, style: menuItemStyle),
            onPressed: () => navigateTo(GamePage(EngineType.testViaLAN)),
          ),
          Expanded(child: SizedBox()),
          Text(S.of(context).gameWarning,
              style: TextStyle(color: Colors.black54, fontSize: 16)),
          Expanded(child: SizedBox()),
          Text(S.of(context).copyright,
              style: TextStyle(color: Colors.black54, fontSize: 16)),
          Expanded(child: SizedBox()),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: UIColors.lightBackgroundColor,
      body: Stack(
        children: <Widget>[
          menuItems,
          Positioned(
            top: SanmillApp.StatusBarHeight,
            left: 10,
            child: IconButton(
              icon: Icon(Icons.menu, color: UIColors.primaryColor),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => SettingsPage()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    //
    inController.dispose();
    shadowController.dispose();

    super.dispose();
  }
}
