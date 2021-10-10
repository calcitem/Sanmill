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

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/l10n/resources.dart';
import 'package:sanmill/screens/home_drawer.dart';
import 'package:sanmill/shared/common/config.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

class DrawerUserController extends StatefulWidget {
  const DrawerUserController({
    Key? key,
    this.drawerWidth = AppTheme.drawerWidth,
    required this.onDrawerCall,
    required this.screenView,
    this.animatedIconData = AnimatedIcons.arrow_menu,
    this.menuView,
    this.drawerIsOpen,
    required this.screenIndex,
  }) : super(key: key);

  final double drawerWidth;
  final Function(DrawerIndex) onDrawerCall;
  final Widget screenView;
  final Function(bool)? drawerIsOpen;
  final AnimatedIconData animatedIconData;
  final Widget? menuView;
  final DrawerIndex screenIndex;

  @override
  _DrawerUserControllerState createState() => _DrawerUserControllerState();
}

class _DrawerUserControllerState extends State<DrawerUserController>
    with TickerProviderStateMixin {
  late final ScrollController scrollController;
  late final AnimationController iconAnimationController;
  late final AnimationController animationController;

  double scrollOffset = 0.0;

  @override
  void initState() {
    animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    iconAnimationController =
        AnimationController(vsync: this, duration: Duration.zero);

    iconAnimationController.animateTo(
      1.0,
      duration: Duration.zero,
      curve: Curves.fastOutSlowIn,
    );

    scrollController =
        ScrollController(initialScrollOffset: widget.drawerWidth);

    scrollController.addListener(() {
      if (scrollController.offset <= 0) {
        if (scrollOffset != 1.0) {
          setState(() {
            scrollOffset = 1.0;
            try {
              widget.drawerIsOpen!(true);
            } catch (_) {}
          });
        }
        iconAnimationController.animateTo(
          0.0,
          duration: Duration.zero,
          curve: Curves.fastOutSlowIn,
        );
      } else if (scrollController.offset < widget.drawerWidth.floor()) {
        iconAnimationController.animateTo(
          (scrollController.offset * 100 / (widget.drawerWidth)) / 100,
          duration: Duration.zero,
          curve: Curves.fastOutSlowIn,
        );
      } else {
        if (scrollOffset != 0.0) {
          setState(() {
            scrollOffset = 0.0;
            try {
              widget.drawerIsOpen!(false);
            } catch (_) {}
          });
        }
        iconAnimationController.animateTo(
          1.0,
          duration: Duration.zero,
          curve: Curves.fastOutSlowIn,
        );
      }
    });

    WidgetsBinding.instance!.addPostFrameCallback((_) => getInitState());
    super.initState();
  }

  Future<bool> getInitState() async {
    scrollController.jumpTo(
      widget.drawerWidth,
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final bool ltr =
        getBidirectionality(context) == Bidirectionality.leftToRight;

    // this just menu and arrow icon animation
    final inkWell = InkWell(
      borderRadius: BorderRadius.circular(AppBar().preferredSize.height),
      child: Center(
        // if you use your own menu view UI you add form initialization
        child: widget.menuView ??
            Semantics(
              label: S.of(context).mainMenu,
              child: AnimatedIcon(
                icon: widget.animatedIconData,
                color: AppTheme.drawerAnimationIconColor,
                progress: iconAnimationController,
              ),
            ),
      ),
      onTap: () {
        FocusScope.of(context).requestFocus(FocusNode());
        onDrawerClick();
      },
    );

    final List<DrawerListItem> drawerItems = [
      DrawerListItem(
        index: DrawerIndex.humanVsAi,
        title: S.of(context).humanVsAi,
        icon: const Icon(FluentIcons.person_24_regular),
      ),
      DrawerListItem(
        index: DrawerIndex.humanVsHuman,
        title: S.of(context).humanVsHuman,
        icon: const Icon(FluentIcons.people_24_regular),
      ),
      DrawerListItem(
        index: DrawerIndex.aiVsAi,
        title: S.of(context).aiVsAi,
        icon: const Icon(FluentIcons.bot_24_regular),
      ),
      DrawerListItem(
        index: DrawerIndex.preferences,
        title: S.of(context).preferences,
        icon: const Icon(FluentIcons.options_24_regular),
      ),
      DrawerListItem(
        index: DrawerIndex.ruleSettings,
        title: S.of(context).ruleSettings,
        icon: const Icon(FluentIcons.task_list_ltr_24_regular),
      ),
      DrawerListItem(
        index: DrawerIndex.personalization,
        title: S.of(context).personalization,
        icon: const Icon(FluentIcons.design_ideas_24_regular),
      ),
      DrawerListItem(
        index: DrawerIndex.feedback,
        title: S.of(context).feedback,
        icon: const Icon(FluentIcons.chat_warning_24_regular),
      ),
      DrawerListItem(
        index: DrawerIndex.Help,
        title: S.of(context).help,
        icon: const Icon(FluentIcons.question_circle_24_regular),
      ),
      DrawerListItem(
        index: DrawerIndex.About,
        title: S.of(context).about,
        icon: const Icon(FluentIcons.info_24_regular),
      ),
    ];

    final animatedBuilder = AnimatedBuilder(
      animation: iconAnimationController,
      builder: (BuildContext context, Widget? child) {
        return Transform(
          // transform we use for the stable drawer
          // we not need to move with scroll view
          transform:
              Matrix4.translationValues(scrollController.offset, 0.0, 0.0),
          child: HomeDrawer(
            screenIndex: widget.screenIndex,
            iconAnimationController: iconAnimationController,
            callBackIndex: (DrawerIndex indexType) {
              onDrawerClick();
              try {
                widget.onDrawerCall(indexType);
              } catch (_) {}
            },
            items: drawerItems,
          ),
        );
      },
    );

    var tapOffset = 0;

    if (!ltr) {
      tapOffset = 10; // TODO: WAR
    }

    final stack = Stack(
      children: <Widget>[
        // this IgnorePointer we use as touch(user Interface) widget.screen View,
        // for example scrolloffset == 1
        // means drawer is close we just allow touching all widget.screen View
        IgnorePointer(
          ignoring: scrollOffset == 1 || false,
          child: widget.screenView,
        ),
        // alternative touch(user Interface) for widget.screen,
        // for example, drawer is close we need to
        // tap on a few home screen area and close the drawer
        if (scrollOffset == 1.0)
          InkWell(
            onTap: onDrawerClick,
          ),
        Padding(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + tapOffset,
          ),
          child: SizedBox(
            width: kToolbarHeight,
            height: kToolbarHeight,
            child: Material(
              color: Colors.transparent,
              child: inkWell,
            ),
          ),
        ),
      ],
    );

    final row = Row(
      children: <Widget>[
        SizedBox(
          width: widget.drawerWidth,
          // we divided first drawer Width with HomeDrawer
          // and second full-screen Width with all home screen,
          // we called screen View
          height: MediaQuery.of(context).size.height,
          child: animatedBuilder,
        ),
        SizedBox(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          //full-screen Width with widget.screenView
          child: Container(
            decoration: BoxDecoration(
              color: Color(Config.drawerColor),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppTheme.drawerBoxerShadowColor,
                  blurRadius: 24,
                ),
              ],
            ),
            child: stack,
          ),
        ),
      ],
    );

    return Material(
      color: Color(Config.drawerColor),
      child: SingleChildScrollView(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
        child: SizedBox(
          height: MediaQuery.of(context).size.height,
          width: MediaQuery.of(context).size.width + widget.drawerWidth,
          // we use with as screen width and add drawerWidth
          // (from navigation_home_screen)
          child: row,
        ),
      ),
    );
  }

  void onDrawerClick() {
    // if scrollController.offset != 0.0
    // then we set to closed the drawer(with animation to offset zero position)
    // if is not 1 then open the drawer
    scrollController.animateTo(
      scrollController.offset == 0.0 ? widget.drawerWidth : 0.0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.fastOutSlowIn,
    );
  }
}
