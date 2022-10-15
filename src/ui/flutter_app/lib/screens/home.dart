// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import 'dart:io';

import 'package:feedback/feedback.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/screens/about_page.dart';
import 'package:sanmill/screens/appearance_settings/appearance_settings_page.dart';
import 'package:sanmill/screens/game_page/game_page.dart';
import 'package:sanmill/screens/general_settings/general_settings_page.dart';
import 'package:sanmill/screens/help_screen.dart';
import 'package:sanmill/screens/rule_settings/rule_settings_page.dart';
import 'package:sanmill/services/database/database.dart';
import 'package:sanmill/services/environment_config.dart';
import 'package:sanmill/services/logger.dart';
import 'package:sanmill/services/mill/mill.dart';
import 'package:sanmill/shared/constants.dart';
import 'package:sanmill/shared/custom_drawer/custom_drawer.dart';
import 'package:sanmill/shared/privacy_dialog.dart';

enum _DrawerIndex {
  humanVsAi,
  humanVsHuman,
  aiVsAi,
  setupPosition,
  generalSettings,
  ruleSettings,
  appearance,
  howToPlay,
  feedback,
  about,
  exit,
}

extension _DrawerScreen on _DrawerIndex {
  Widget? get screen {
    switch (this) {
      case _DrawerIndex.humanVsAi:
        return GamePage(
          GameMode.humanVsAi,
          key: const Key("Human-Ai"),
        );
      case _DrawerIndex.humanVsHuman:
        return GamePage(
          GameMode.humanVsHuman,
          key: const Key("Human-Human"),
        );
      case _DrawerIndex.aiVsAi:
        return GamePage(
          GameMode.aiVsAi,
          key: const Key("Ai-Ai"),
        );
      case _DrawerIndex.setupPosition:
        return GamePage(
          GameMode.setupPosition,
          key: const Key("SetupPosition"),
        );
      case _DrawerIndex.generalSettings:
        return const GeneralSettingsPage();
      case _DrawerIndex.ruleSettings:
        return const RuleSettingsPage();
      case _DrawerIndex.appearance:
        return const AppearanceSettingsPage();
      case _DrawerIndex.howToPlay:
        return const HowToPlayScreen();
      case _DrawerIndex.feedback:
        throw ErrorDescription(
          "Feedback screen is not a widget and should be called separately",
        );
      case _DrawerIndex.about:
        return const AboutPage();
      case _DrawerIndex.exit:
        if (EnvironmentConfig.test == false) {
          SystemChannels.platform.invokeMethod<void>('SystemNavigator.pop');
        }
        return null;
    }
  }
}

/// Home View
///
/// This widget implements the home view of our app.
class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  HomeState createState() => HomeState();
}

class HomeState extends State<Home> with TickerProviderStateMixin {
  final _controller = CustomDrawerController();

  Widget _screenView = _DrawerIndex.humanVsAi.screen!;
  _DrawerIndex _drawerIndex = _DrawerIndex.humanVsAi;

  /// Callback from drawer for replace screen
  /// as user need with passing DrawerIndex (Enum index)
  void _changeIndex(_DrawerIndex index) {
    _controller.hideDrawer();
    if (_drawerIndex == index && _drawerIndex != _DrawerIndex.feedback) return;

    if ((index == _DrawerIndex.howToPlay ||
            index == _DrawerIndex.about ||
            index == _DrawerIndex.feedback) &&
        EnvironmentConfig.test == true) {
      return logger.w("Do not test HowToPlay/Feedback/About page.");
    }

    if (index == _DrawerIndex.feedback) {
      if (kIsWeb) {
        return logger.w("flutter_email_sender does not support Web.");
      } else if (Platform.isWindows) {
        return logger.w("flutter_email_sender does not support Windows.");
      } else {
        return BetterFeedback.of(context).show(_launchFeedback);
      }
    }

    setState(() {
      assert(index != _DrawerIndex.feedback);
      _drawerIndex = index;
      if (index.screen != null) {
        _screenView = index.screen!;
      }
    });
  }

  @override
  void didChangeDependencies() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPrivacyDialog());
    super.didChangeDependencies();
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
        value: _DrawerIndex.setupPosition,
        title: S.of(context).setupPosition,
        icon: const Icon(FluentIcons.drafts_24_regular),
        groupValue: _drawerIndex,
        onChanged: _changeIndex,
      ),
      CustomDrawerItem<_DrawerIndex>(
        value: _DrawerIndex.generalSettings,
        title: S.of(context).generalSettings,
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
        value: _DrawerIndex.appearance,
        title: S.of(context).appearance,
        icon: const Icon(FluentIcons.design_ideas_24_regular),
        groupValue: _drawerIndex,
        onChanged: _changeIndex,
      ),
      CustomDrawerItem<_DrawerIndex>(
        value: _DrawerIndex.howToPlay,
        title: S.of(context).howToPlay,
        icon: const Icon(FluentIcons.question_circle_24_regular),
        groupValue: _drawerIndex,
        onChanged: _changeIndex,
      ),
      if (kIsWeb || Platform.isAndroid || Platform.isIOS)
        CustomDrawerItem<_DrawerIndex>(
          value: _DrawerIndex.feedback,
          title: S.of(context).feedback,
          icon: const Icon(FluentIcons.chat_warning_24_regular),
          groupValue: _drawerIndex,
          onChanged: _changeIndex,
        ),
      CustomDrawerItem<_DrawerIndex>(
        value: _DrawerIndex.about,
        title: S.of(context).about,
        icon: const Icon(FluentIcons.info_24_regular),
        groupValue: _drawerIndex,
        onChanged: _changeIndex,
      ),
      CustomDrawerItem<_DrawerIndex>(
        value: _DrawerIndex.exit,
        title: S.of(context).exit,
        icon: const Icon(FluentIcons.power_24_regular),
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

  void _showPrivacyDialog() {
    if (!DB().generalSettings.isPrivacyPolicyAccepted &&
        Localizations.localeOf(context).languageCode.startsWith("zh")) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const PrivacyDialog(),
      );
    }
  }

  /// Drafts an email and sends it to the developer
  static Future<void> _launchFeedback(UserFeedback feedback) async {
    final screenshotFilePath = await _saveFeedbackImage(feedback.screenshot);
    final packageInfo = await PackageInfo.fromPlatform();
    final version = "${packageInfo.version} (${packageInfo.buildNumber})";

    final Email email = Email(
      body: feedback.text,
      subject: Constants.feedbackSubjectPrefix +
          version +
          Constants.feedbackSubjectSuffix,
      recipients: Constants.recipients,
      attachmentPaths: [screenshotFilePath],
    );
    await FlutterEmailSender.send(email);
  }

  static Future<String> _saveFeedbackImage(Uint8List screenshot) async {
    final Directory output = await getTemporaryDirectory();
    final String screenshotFilePath = "${output.path}/sanmill-feedback.png";
    final File screenshotFile = File(screenshotFilePath);
    await screenshotFile.writeAsBytes(screenshot);
    return screenshotFilePath;
  }
}
