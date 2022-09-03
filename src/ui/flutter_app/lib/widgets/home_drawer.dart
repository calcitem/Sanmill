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

import 'dart:async';

import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:sanmill/common/config.dart';
import 'package:sanmill/common/constants.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/l10n/resources.dart';
import 'package:sanmill/style/app_theme.dart';
import 'package:sanmill/widgets/game_settings_page.dart';

enum DrawerIndex {
  humanVsAi,
  humanVsHuman,
  aiVsAi,
  preferences,
  ruleSettings,
  personalization,
  feedback,
  Help,
  About
}

class DrawerListItem {
  DrawerListItem({this.index, this.title = '', this.icon});

  DrawerIndex? index;
  String title;
  Icon? icon;
}

class HomeDrawer extends StatefulWidget {
  const HomeDrawer(
      {Key? key,
      this.screenIndex,
      this.iconAnimationController,
      this.callBackIndex})
      : super(key: key);

  final AnimationController? iconAnimationController;
  final DrawerIndex? screenIndex;
  final Function(DrawerIndex?)? callBackIndex;

  @override
  _HomeDrawerState createState() => _HomeDrawerState();
}

class _HomeDrawerState extends State<HomeDrawer> {
  DateTime? lastTapTime;

  final String tag = "[home_drawer]";

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    List<DrawerListItem> drawerList = <DrawerListItem>[
      DrawerListItem(
        index: DrawerIndex.humanVsAi,
        title: S.of(context).humanVsAi,
        icon: Icon(FluentIcons.person_24_regular),
      ),
      DrawerListItem(
        index: DrawerIndex.humanVsHuman,
        title: S.of(context).humanVsHuman,
        icon: Icon(FluentIcons.people_24_regular),
      ),
      DrawerListItem(
        index: DrawerIndex.aiVsAi,
        title: S.of(context).aiVsAi,
        icon: Icon(FluentIcons.bot_24_regular),
      ),
      DrawerListItem(
        index: DrawerIndex.preferences,
        title: S.of(context).generalSettings,
        icon: Icon(FluentIcons.options_24_regular),
      ),
      DrawerListItem(
        index: DrawerIndex.ruleSettings,
        title: S.of(context).ruleSettings,
        icon: Icon(FluentIcons.task_list_ltr_24_regular),
      ),
      DrawerListItem(
        index: DrawerIndex.personalization,
        title: S.of(context).appearance,
        icon: Icon(FluentIcons.design_ideas_24_regular),
      ),
      DrawerListItem(
        index: DrawerIndex.feedback,
        title: S.of(context).feedback,
        icon: Icon(FluentIcons.chat_warning_24_regular),
      ),
      DrawerListItem(
        index: DrawerIndex.Help,
        title: S.of(context).help,
        icon: Icon(FluentIcons.question_circle_24_regular),
      ),
      DrawerListItem(
        index: DrawerIndex.About,
        title: S.of(context).about,
        icon: Icon(FluentIcons.info_24_regular),
      ),
    ];

    var rotationTransition = RotationTransition(
      turns: AlwaysStoppedAnimation<double>(Tween<double>(begin: 0.0, end: 24.0)
              .animate(CurvedAnimation(
                  parent: widget.iconAnimationController!,
                  curve: Curves.fastOutSlowIn))
              .value /
          360),
    );

    var scaleTransition = ScaleTransition(
      scale: AlwaysStoppedAnimation<double>(
          1.0 - (widget.iconAnimationController!.value) * 0.2),
      child: rotationTransition,
    );

    var animatedBuilder = AnimatedBuilder(
      animation: widget.iconAnimationController!,
      builder: (BuildContext context, Widget? child) {
        return scaleTransition;
      },
    );

    var animatedTextsColors = [
      Color(Config.drawerTextColor),
      Colors.black,
      Colors.blue,
      Colors.yellow,
      Colors.red,
      Color(Config.darkBackgroundColor),
      Color(Config.boardBackgroundColor),
      Color(Config.drawerHighlightItemColor),
    ];

    var animatedTextKit = AnimatedTextKit(
        animatedTexts: [
          ColorizeAnimatedText(
            S.of(context).appName,
            textStyle: TextStyle(
              fontSize: Config.fontSize + 16,
              fontWeight: FontWeight.w600,
            ),
            colors: animatedTextsColors,
            textAlign: TextAlign.start,
            speed: const Duration(milliseconds: 3000),
          ),
        ],
        pause: const Duration(milliseconds: 30000),
        repeatForever: true,
        stopPauseOnTap: true,
        onTap: () {
          if (lastTapTime == null ||
              DateTime.now().difference(lastTapTime!) > Duration(seconds: 1)) {
            lastTapTime = DateTime.now();
            print("$tag Tap again in one second to enable developer mode.");
          } else {
            lastTapTime = DateTime.now();
            Developer.developerModeEnabled = true;
            print("$tag Developer mode enabled.");
          }
        });

    var drawerHeader = Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 0.0),
      child: Container(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            animatedBuilder,
            Padding(
              padding:
                  EdgeInsets.only(top: (isLargeScreen() ? 30 : 8), left: 4),
              child: ExcludeSemantics(child: animatedTextKit),
            ),
          ],
        ),
      ),
    );

    /*
    var exitListTile = ListTile(
      title: Text(
        S.of(context).exit,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 16,
          color: AppTheme.exitTextColor,
        ),
        textAlign: TextAlign.left,
      ),
      trailing: Icon(
        FluentIcons.power_24_regular,
        color: AppTheme.exitIconColor,
      ),
      onTap: () async {
        if (Config.developerMode) {
          return;
        }

        await SystemChannels.platform.invokeMethod<void>('SystemNavigator.pop');
      },
    );
    */

    /*
    var drawFooter = Column(
      children: <Widget>[
        exitListTile,
        SizedBox(height: MediaQuery.of(context).padding.bottom)
      ],
    );
    */

    var scaffold = Scaffold(
      backgroundColor: Color(Config.drawerBackgroundColor),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.start,
        children: <Widget>[
          drawerHeader,
          const SizedBox(height: 4),
          Divider(height: 1, color: AppTheme.drawerDividerColor),
          Expanded(
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(0.0),
              itemCount: drawerList.length,
              itemBuilder: (BuildContext context, int index) {
                return buildInkwell(drawerList[index]);
              },
            ),
          ),
          Divider(height: 1, color: AppTheme.drawerDividerColor),
          //drawFooter,
        ],
      ),
    );

    return scaffold;
  }

  Future<void> navigationToScreen(DrawerIndex? index) async {
    widget.callBackIndex!(index);
  }

  Widget buildInkwell(DrawerListItem listItem) {
    bool ltr = getBidirectionality(context) == Bidirectionality.leftToRight;
    double radius = 28.0;
    var animatedBuilder = AnimatedBuilder(
      animation: widget.iconAnimationController!,
      builder: (BuildContext context, Widget? child) {
        return Transform(
          transform: Matrix4.translationValues(
              (MediaQuery.of(context).size.width * 0.75 - 64) *
                  (1.0 - widget.iconAnimationController!.value - 1.0),
              0.0,
              0.0),
          child: Padding(
            padding: EdgeInsets.only(top: 8, bottom: 8),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.75 - 64,
              height: 46,
              decoration: BoxDecoration(
                color: Color(Config.drawerHighlightItemColor),
                borderRadius: new BorderRadius.only(
                  topLeft: Radius.circular(ltr ? 0 : radius),
                  topRight: Radius.circular(ltr ? radius : 0),
                  bottomLeft: Radius.circular(ltr ? 0 : radius),
                  bottomRight: Radius.circular(ltr ? radius : 0),
                ),
              ),
            ),
          ),
        );
      },
    );

    var listItemIcon = Icon(listItem.icon!.icon,
        color: widget.screenIndex == listItem.index
            ? Color(Config.drawerTextColor) // TODO: drawerHighlightTextColor
            : Color(Config.drawerTextColor));

    var stack = Stack(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
          child: Row(
            children: <Widget>[
              Container(
                width: 6.0,
                height: 46.0,
              ),
              const Padding(
                padding: EdgeInsets.all(4.0),
              ),
              listItemIcon,
              const Padding(
                padding: EdgeInsets.all(4.0),
              ),
              Text(
                listItem.title,
                style: TextStyle(
                  fontWeight: widget.screenIndex == listItem.index
                      ? FontWeight.w700
                      : FontWeight.w500,
                  fontSize: Config.fontSize,
                  color: widget.screenIndex == listItem.index
                      ? Color(Config
                          .drawerTextColor) // TODO: drawerHighlightTextColor
                      : Color(Config.drawerTextColor),
                ),
              ),
            ],
          ),
        ),
        widget.screenIndex == listItem.index
            ? animatedBuilder
            : const SizedBox()
      ],
    );

    return Material(
      // Semantics: Main menu item
      color: Colors.transparent,
      child: InkWell(
        splashColor: AppTheme.drawerSplashColor,
        highlightColor: AppTheme.drawerHighlightColor,
        onTap: () {
          navigationToScreen(listItem.index);
        },
        child: stack,
      ),
    );
  }
}
