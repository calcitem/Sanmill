// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io' show IOException;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter/widgets.dart';

import '../appearance_settings/widgets/appearance_settings_page.dart';
import '../game_platform/game_registry.dart';
import '../game_shell/shell_route_ids.dart';
import '../general_settings/widgets/general_settings_page.dart';
import '../learn/mill_coordinate_training_page.dart';
import '../misc/about_page.dart';
import '../misc/clock_tool_page.dart';
import '../misc/how_to_play_screen.dart';
import '../misc/mill_variants_page.dart';
import '../shared/services/environment_config.dart';
import 'settings_hub_page.dart';

/// Resolves [ShellRouteIds] for app-level (`app.*`) routes.
Widget? buildAppRouteScreen(BuildContext context, String routeId) {
  if (routeId == ShellRouteIds.appSettingsGroup.value) {
    return const SettingsHubPage();
  }
  if (routeId == ShellRouteIds.appGeneralSettings.value) {
    return const GeneralSettingsPage();
  }
  if (routeId == ShellRouteIds.appRuleSettings.value) {
    return GameRegistry.instance.current.buildRuleSettingsScreen(context);
  }
  if (routeId == ShellRouteIds.appAppearance.value) {
    return const AppearanceSettingsPage();
  }
  if (routeId == ShellRouteIds.appHowToPlay.value) {
    return const HowToPlayScreen();
  }
  if (routeId == ShellRouteIds.appAbout.value) {
    return const AboutPage();
  }
  if (routeId == ShellRouteIds.appCoordinateTraining.value) {
    return const MillCoordinateTrainingPage();
  }
  if (routeId == ShellRouteIds.appClock.value) {
    return const ClockToolPage();
  }
  if (routeId == ShellRouteIds.appVariants.value) {
    return const MillVariantsPage();
  }
  if (routeId == ShellRouteIds.appExit.value) {
    if (EnvironmentConfig.test == false) {
      if (!kIsWeb) {
        try {
          // ignore: avoid_slow_async
          SystemNavigator.pop();
        } on Object catch (e) {
          // Windows/web may not support SystemNavigator; ignore in tests
          if (e is! IOException) {
            rethrow;
          }
        }
      }
    }
    return null;
  }
  return null;
}
