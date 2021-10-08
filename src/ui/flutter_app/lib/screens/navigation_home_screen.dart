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

import 'dart:io';
import 'dart:typed_data';

import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:feedback/feedback.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/l10n/resources.dart';
import 'package:sanmill/mill/game.dart';
import 'package:sanmill/screens/about_page.dart';
import 'package:sanmill/screens/game_page/game_page.dart';
import 'package:sanmill/screens/game_settings_page.dart';
import 'package:sanmill/screens/help_screen.dart';
import 'package:sanmill/screens/personalization_settings_page.dart';
import 'package:sanmill/screens/rule_settings_page.dart';
import 'package:sanmill/services/engine/engine.dart';
import 'package:sanmill/shared/common/config.dart';
import 'package:sanmill/shared/common/constants.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

part 'package:sanmill/screens/home_drawer.dart';
part 'package:sanmill/shared/drawer_controller.dart';

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
    screenView = const GamePage(EngineType.humanVsAi);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navigationHomeScreenBackgroundColor,
      body: DrawerController(
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
    );
  }

  void changeIndex(DrawerIndex index) {
    if (drawerIndex == index && drawerIndex != DrawerIndex.feedback) {
      return;
    }

    final drawerMap = {
      DrawerIndex.humanVsAi: EngineType.humanVsAi,
      DrawerIndex.humanVsHuman: EngineType.humanVsHuman,
      DrawerIndex.aiVsAi: EngineType.aiVsAi,
    };

    drawerIndex = index;

    // TODO: use switch case
    final engineType = drawerMap[drawerIndex!];
    setState(() {
      if (engineType != null) {
        gameInstance.setWhoIsAi(engineType);
        screenView = GamePage(engineType);
      } else if (drawerIndex == DrawerIndex.preferences) {
        screenView = GameSettingsPage();
      } else if (drawerIndex == DrawerIndex.ruleSettings) {
        screenView = RuleSettingsPage();
      } else if (drawerIndex == DrawerIndex.personalization) {
        screenView = PersonalizationSettingsPage();
      } else if (drawerIndex == DrawerIndex.feedback && !Config.developerMode) {
        if (Platform.isWindows) {
          debugPrint("flutter_email_sender does not support Windows.");
          //_launchFeedback();
        } else {
          BetterFeedback.of(context).show((feedback) async {
            // draft an email and send to developer
            final screenshotFilePath =
                await writeImageToStorage(feedback.screenshot);
            final packageInfo = await PackageInfo.fromPlatform();
            final _version =
                '${packageInfo.version} (${packageInfo.buildNumber})';

            final Email email = Email(
              body: feedback.text,
              subject: Constants.feedbackSubjectPrefix +
                  _version +
                  Constants.feedbackSubjectSuffix,
              recipients: [Constants.recipients],
              attachmentPaths: [screenshotFilePath],
            );
            await FlutterEmailSender.send(email);
          });
        }
      } else if (drawerIndex == DrawerIndex.Help && !Config.developerMode) {
        screenView = HelpScreen();
      } else if (drawerIndex == DrawerIndex.About && !Config.developerMode) {
        screenView = AboutPage();
      } else {
        //do in your way......
      }
    });
  }

  Future<String> writeImageToStorage(Uint8List feedbackScreenshot) async {
    final Directory output = await getTemporaryDirectory();
    final String screenshotFilePath = '${output.path}/sanmill-feedback.png';
    final File screenshotFile = File(screenshotFilePath);
    await screenshotFile.writeAsBytes(feedbackScreenshot);
    return screenshotFilePath;
  }
}
