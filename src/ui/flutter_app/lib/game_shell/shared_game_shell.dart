// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../custom_drawer/custom_drawer.dart';
import '../game_page/services/gif_share/gif_share.dart';
import '../game_page/services/gif_share/widgets_to_image.dart';
import '../shared/widgets/double_back_to_close_app.dart';

/// Shared [CustomDrawer] + main content layout used for every [GameId] in
/// [Home]. Game-specific behaviour stays in [GameModule] hooks.
class SharedGameShell extends StatelessWidget {
  const SharedGameShell({
    super.key,
    required this.drawerController,
    required this.drawerHeaderTitle,
    required this.drawerItems,
    required this.mainScreen,
    required this.onWillPopStackEntry,
    required this.isDrawerGestureDisabled,
    required this.doubleBackSnackBar,
  });

  final CustomDrawerController drawerController;
  final String drawerHeaderTitle;
  final List<CustomDrawerItem<String>> drawerItems;
  final Widget mainScreen;

  /// Android back: return true if the in-app route stack consumed the event.
  final bool Function() onWillPopStackEntry;

  /// When true, swipe-to-open drawer is disabled (desktop play surfaces).
  final bool Function(BuildContext context, CustomDrawerValue drawerValue)
  isDrawerGestureDisabled;

  final SnackBar doubleBackSnackBar;

  @override
  Widget build(BuildContext context) {
    return DoubleBackToCloseApp(
      snackBar: doubleBackSnackBar,
      willBack: onWillPopStackEntry,
      child: WidgetsToImage(
        controller: GifShare().controller,
        child: ValueListenableBuilder<CustomDrawerValue>(
          valueListenable: drawerController,
          builder: (_, CustomDrawerValue drawerValue, Widget? child) =>
              CustomDrawer(
                key: CustomDrawer.drawerMainKey,
                controller: drawerController,
                drawerHeader: CustomDrawerHeader(
                  headerTitle: drawerHeaderTitle,
                  key: const Key('custom_drawer_header'),
                ),
                drawerItems: drawerItems,
                disabledGestures: isDrawerGestureDisabled(context, drawerValue),
                orientation: MediaQuery.of(context).orientation,
                mainScreenWidget: mainScreen,
              ),
        ),
      ),
    );
  }
}
