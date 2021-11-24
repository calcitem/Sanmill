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

import 'package:feedback/feedback.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/mill/game.dart';
import 'package:sanmill/screens/about_page.dart';
import 'package:sanmill/screens/game_page/game_page.dart';
import 'package:sanmill/screens/game_settings/game_settings_page.dart';
import 'package:sanmill/screens/help_screen.dart';
import 'package:sanmill/screens/personalization_settings/personalization_settings_page.dart';
import 'package:sanmill/screens/rule_settings/rule_settings_page.dart';
import 'package:sanmill/services/engine/engine.dart';
import 'package:sanmill/services/environment_config.dart';
import 'package:sanmill/shared/constants.dart';
import 'package:sanmill/shared/custom_drawer/custom_drawer.dart';

enum _DrawerIndex {
  humanVsAi,
  humanVsHuman,
  aiVsAi,
  preferences,
  ruleSettings,
  personalization,
  feedback,
  Help,
  About,
}

/// Home View
///
/// this widget implements the home view of our app.
class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> with TickerProviderStateMixin {
  final _controller = CustomDrawerController();

  Widget _screenView = const GamePage(EngineType.humanVsAi);
  _DrawerIndex _drawerIndex = _DrawerIndex.humanVsAi;

  static const Map<_DrawerIndex, Widget> _gamePages = {
    _DrawerIndex.humanVsAi: GamePage(EngineType.humanVsAi),
    _DrawerIndex.humanVsHuman: GamePage(EngineType.humanVsHuman),
    _DrawerIndex.aiVsAi: GamePage(EngineType.aiVsAi),
  };

  /// callback from drawer for replace screen
  /// as user need with passing DrawerIndex (Enum index)
  void _changeIndex(_DrawerIndex index) {
    _controller.hideDrawer();
    if (_drawerIndex == index && _drawerIndex != _DrawerIndex.feedback) {
      return;
    }

    setState(() {
      _drawerIndex = index;
      switch (_drawerIndex) {
        case _DrawerIndex.humanVsAi:
          gameInstance.setWhoIsAi(EngineType.humanVsAi);
          _screenView = _gamePages[_DrawerIndex.humanVsAi]!;
          break;
        case _DrawerIndex.humanVsHuman:
          gameInstance.setWhoIsAi(EngineType.humanVsHuman);
          _screenView = _gamePages[_DrawerIndex.humanVsHuman]!;
          break;
        case _DrawerIndex.aiVsAi:
          gameInstance.setWhoIsAi(EngineType.aiVsAi);
          _screenView = _gamePages[_DrawerIndex.aiVsAi]!;
          break;
        case _DrawerIndex.preferences:
          _screenView = const GameSettingsPage();
          break;
        case _DrawerIndex.ruleSettings:
          _screenView = const RuleSettingsPage();
          break;
        case _DrawerIndex.personalization:
          _screenView = const PersonalizationSettingsPage();
          break;
        case _DrawerIndex.feedback:
          if (!EnvironmentConfig.devMode) {
            if (Platform.isWindows) {
              debugPrint("flutter_email_sender does not support Windows.");
            } else {
              BetterFeedback.of(context).show(_launchFeedback);
            }
          }
          break;
        case _DrawerIndex.Help:
          if (!EnvironmentConfig.devMode) {
            _screenView = const HelpScreen();
          }
          break;

        case _DrawerIndex.About:
          if (!EnvironmentConfig.devMode) {
            _screenView = const AboutPage();
          }
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<CustomDrawerItem> drawerItems = [
      CustomDrawerItem<_DrawerIndex>(
        value: _DrawerIndex.humanVsAi,
        title: S.of(context).humanVsAi,
        icon: const Icon(FluentIcons.person_24_regular),
        groupValue: _drawerIndex,
        onChanged: _changeIndex,
      ),
      CustomDrawerItem<_DrawerIndex>(
        value: _DrawerIndex.humanVsHuman,
        title: S.of(context).humanVsHuman,
        icon: const Icon(FluentIcons.people_24_regular),
        groupValue: _drawerIndex,
        onChanged: _changeIndex,
      ),
      CustomDrawerItem<_DrawerIndex>(
        value: _DrawerIndex.aiVsAi,
        title: S.of(context).aiVsAi,
        icon: const Icon(FluentIcons.bot_24_regular),
        groupValue: _drawerIndex,
        onChanged: _changeIndex,
      ),
      CustomDrawerItem<_DrawerIndex>(
        value: _DrawerIndex.preferences,
        title: S.of(context).preferences,
        icon: const Icon(FluentIcons.options_24_regular),
        groupValue: _drawerIndex,
        onChanged: _changeIndex,
      ),
      CustomDrawerItem<_DrawerIndex>(
        value: _DrawerIndex.ruleSettings,
        title: S.of(context).ruleSettings,
        icon: const Icon(FluentIcons.task_list_ltr_24_regular),
        groupValue: _drawerIndex,
        onChanged: _changeIndex,
      ),
      CustomDrawerItem<_DrawerIndex>(
        value: _DrawerIndex.personalization,
        title: S.of(context).personalization,
        icon: const Icon(FluentIcons.design_ideas_24_regular),
        groupValue: _drawerIndex,
        onChanged: _changeIndex,
      ),
      if (Platform.isAndroid || Platform.isIOS)
        CustomDrawerItem<_DrawerIndex>(
          value: _DrawerIndex.feedback,
          title: S.of(context).feedback,
          icon: const Icon(FluentIcons.chat_warning_24_regular),
          groupValue: _drawerIndex,
          onChanged: _changeIndex,
        ),
      CustomDrawerItem<_DrawerIndex>(
        value: _DrawerIndex.Help,
        title: S.of(context).help,
        icon: const Icon(FluentIcons.question_circle_24_regular),
        groupValue: _drawerIndex,
        onChanged: _changeIndex,
      ),
      CustomDrawerItem<_DrawerIndex>(
        value: _DrawerIndex.About,
        title: S.of(context).about,
        icon: const Icon(FluentIcons.info_24_regular),
        groupValue: _drawerIndex,
        onChanged: _changeIndex,
      ),
    ];

    return CustomDrawer(
      controller: _controller,
      header: CustomDrawerHeader(
        title: S.of(context).appName,
      ),
      items: drawerItems,
      child: _screenView,
    );
  }
}

/// drafts an email and sends it to the developer
Future<void> _launchFeedback(UserFeedback feedback) async {
  final screenshotFilePath = await _writeImageToStorage(feedback.screenshot);
  final packageInfo = await PackageInfo.fromPlatform();
  final _version = '${packageInfo.version} (${packageInfo.buildNumber})';

  final Email email = Email(
    body: feedback.text,
    subject: Constants.feedbackSubjectPrefix +
        _version +
        Constants.feedbackSubjectSuffix,
    recipients: [Constants.recipients],
    attachmentPaths: [screenshotFilePath],
  );
  await FlutterEmailSender.send(email);
}

Future<String> _writeImageToStorage(Uint8List feedbackScreenshot) async {
  final Directory output = await getTemporaryDirectory();
  final String screenshotFilePath = '${output.path}/sanmill-feedback.png';
  final File screenshotFile = File(screenshotFilePath);
  await screenshotFile.writeAsBytes(feedbackScreenshot);
  return screenshotFilePath;
}
