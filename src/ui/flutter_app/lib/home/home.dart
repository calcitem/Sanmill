// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// home.dart

import 'dart:async';
import 'dart:io';

import 'package:feedback/feedback.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../appearance_settings/widgets/appearance_settings_page.dart';
import '../custom_drawer/custom_drawer.dart';
import '../game_page/services/gif_share/gif_share.dart';
import '../game_page/services/gif_share/widgets_to_image.dart';
import '../game_page/services/mill.dart';
import '../game_page/services/painters/painters.dart';
import '../game_page/widgets/dialogs/lan_config_dialog.dart';
import '../game_page/widgets/game_page.dart';
import '../general_settings/models/general_settings.dart';
import '../general_settings/widgets/general_settings_page.dart';
import '../generated/intl/l10n.dart';
import '../main.dart';
import '../misc/about_page.dart';
import '../misc/how_to_play_screen.dart';
import '../rule_settings/models/rule_settings.dart';
import '../rule_settings/widgets/rule_settings_page.dart';
import '../shared/config/constants.dart';
import '../shared/database/database.dart';
import '../shared/dialogs/privacy_policy_dialog.dart';
import '../shared/services/environment_config.dart';
import '../shared/services/logger.dart';
import '../shared/services/snackbar_service.dart';
import '../shared/themes/app_theme.dart';
import '../shared/utils/helpers/list_helpers/stack_list.dart';
import '../shared/widgets/double_back_to_close_app.dart';
import '../shared/widgets/snackbars/scaffold_messenger.dart';
import '../statistics/widgets/stats_page.dart';
import '../tutorial/widgets/tutorial_dialog.dart';

// Define the possible states of the drawer
enum _DrawerIndex {
  humanVsAi,
  humanVsHuman,
  aiVsAi,
  humanVsLAN,
  setupPosition,
  statistics,
  settingsGroup,
  generalSettings,
  ruleSettings,
  appearance,
  helpGroup,
  howToPlay,
  feedback,
  about,
  exit,
}

// Extension to handle widget selection based on drawer state
extension _DrawerScreen on _DrawerIndex {
  Widget? get screen {
    switch (this) {
      case _DrawerIndex.humanVsAi:
        return GamePage(GameMode.humanVsAi, key: const Key("human_ai"));
      case _DrawerIndex.humanVsHuman:
        GameController().disableStats = true;
        return GamePage(GameMode.humanVsHuman, key: const Key("human_human"));
      case _DrawerIndex.aiVsAi:
        GameController().disableStats = true;
        return GamePage(GameMode.aiVsAi, key: const Key("ai_ai"));
      case _DrawerIndex.humanVsLAN:
        return GamePage(GameMode.humanVsLAN, key: const Key("human_lan"));
      case _DrawerIndex.setupPosition:
        return GamePage(
          GameMode.setupPosition,
          key: const Key("setup_position"),
        );
      case _DrawerIndex.statistics:
        return const StatisticsPage();
      case _DrawerIndex.generalSettings:
        return const GeneralSettingsPage();
      case _DrawerIndex.ruleSettings:
        return const RuleSettingsPage();
      case _DrawerIndex.appearance:
        return const AppearanceSettingsPage();
      case _DrawerIndex.howToPlay:
        return const HowToPlayScreen();
      case _DrawerIndex.feedback:
        // ignore: only_throw_errors
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
      // Parent groups do not have screens
      case _DrawerIndex.settingsGroup:
      case _DrawerIndex.helpGroup:
        return null;
    }
  }
}

/// Home View
///
/// This widget implements the home view of our app.
class Home extends StatefulWidget {
  const Home({super.key});

  static const Key homeMainKey = Key('home_main');

  @override
  HomeState createState() => HomeState();
}

class HomeState extends State<Home> with TickerProviderStateMixin {
  final CustomDrawerController _controller = CustomDrawerController();

  Widget _screenView = kIsWeb
      ? _DrawerIndex.humanVsHuman.screen!
      : _DrawerIndex.humanVsAi.screen!;
  _DrawerIndex _drawerIndex = kIsWeb
      ? _DrawerIndex.humanVsHuman
      : _DrawerIndex.humanVsAi;
  final StackList<_DrawerIndex> _routes = StackList<_DrawerIndex>();

  /// Callback from drawer for replace screen
  /// as user need with passing DrawerIndex (Enum index)
  Future<void> _changeIndex(_DrawerIndex index) async {
    _controller.hideDrawer();

    // Print the name of the screen being switched to (in English)
    switch (index) {
      case _DrawerIndex.humanVsAi:
        logger.i('Switching to Human vs AI');
        break;
      case _DrawerIndex.humanVsHuman:
        logger.i('Switching to Human vs Human');
        break;
      case _DrawerIndex.aiVsAi:
        logger.i('Switching to AI vs AI');
        break;
      case _DrawerIndex.humanVsLAN:
        logger.i('Switching to Human vs LAN');
        break;
      case _DrawerIndex.setupPosition:
        logger.i('Switching to Setup Position');
        break;
      case _DrawerIndex.statistics:
        logger.i('Switching to Statistics');
        break;
      // Logging for group items is not strictly necessary as they don't switch screens
      case _DrawerIndex.settingsGroup:
        logger.i('Toggling Settings group'); // Or simply remove logging
        break;
      case _DrawerIndex.generalSettings:
        logger.i('Switching to General Settings');
        break;
      case _DrawerIndex.ruleSettings:
        logger.i('Switching to Rule Settings');
        break;
      case _DrawerIndex.appearance:
        logger.i('Switching to Appearance');
        break;
      case _DrawerIndex.helpGroup:
        logger.i('Toggling Help group'); // Or simply remove logging
        break;
      case _DrawerIndex.howToPlay:
        logger.i('Switching to How To Play');
        break;
      case _DrawerIndex.feedback:
        logger.i('Switching to Feedback');
        break;
      case _DrawerIndex.about:
        logger.i('Switching to About');
        break;
      case _DrawerIndex.exit:
        logger.i('Exiting...');
        break;
    }

    // ---------------------------------------------------------------------
    // If leaving LAN mode, disconnect and reset the game.
    // ---------------------------------------------------------------------
    if (_drawerIndex == _DrawerIndex.humanVsLAN &&
        index != _DrawerIndex.humanVsLAN) {
      logger.i("Leaving LAN mode: disposing network and resetting the board.");
      // Dispose any existing LAN connection
      GameController().networkService?.dispose();
      GameController().networkService = null; // optional

      // Force a fresh game state so the board is cleared
      GameController().reset(force: true);
    }

    // If no real change in index (and it's not the special "feedback" case,
    // or a group item that doesn't change screen), just return.
    if (_drawerIndex == index &&
        _drawerIndex != _DrawerIndex.feedback &&
        index != _DrawerIndex.settingsGroup && // Add group checks
        index != _DrawerIndex.helpGroup) {
      return;
    }

    // Handle the LAN-setup dialog, feedback, etc. as before...
    if (index == _DrawerIndex.humanVsLAN) {
      // Show experimental feature notification
      SnackBarService.showRootSnackBar(S.of(context).experimental);

      // Show LAN config dialog and await result
      final bool? result = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => const LanConfigDialog(),
      );

      if (result ?? false) {
        setState(() {
          _pushRoute(_DrawerIndex.humanVsLAN);
          _drawerIndex = _DrawerIndex.humanVsLAN;
          _screenView = GamePage(
            GameMode.humanVsLAN,
            key: const Key("human_lan"),
          );
        });
      }
      return;
    }

    if ((index == _DrawerIndex.howToPlay ||
            index == _DrawerIndex.about ||
            index == _DrawerIndex.feedback) &&
        EnvironmentConfig.test == true) {
      return logger.w("Do not test HowToPlay/Feedback/About page.");
    }

    if (index == _DrawerIndex.feedback) {
      if (Platform.isAndroid) {
        return BetterFeedback.of(context).show(_launchFeedback);
      } else {
        return logger.w("flutter_email_sender does not support this platform.");
      }
    }

    // Do not attempt to set screen for group items
    if (index == _DrawerIndex.settingsGroup ||
        index == _DrawerIndex.helpGroup) {
      // Parent items are handled by CustomDrawer's expansion logic,
      // no screen change or route push needed here for the parent itself.
      // SelectionChanged for these is `(_) {}` anyway.
      return;
    }

    setState(() {
      assert(index != _DrawerIndex.feedback);
      assert(index != _DrawerIndex.settingsGroup);
      assert(index != _DrawerIndex.helpGroup);
      _pushRoute(index);
      _drawerIndex = index;
      if (index.screen != null) {
        _screenView = index.screen!;
      }
    });
  }

  // Function to check if the current drawer state corresponds to a game
  bool _isGame(_DrawerIndex index) {
    switch (index) {
      case _DrawerIndex.humanVsAi:
      case _DrawerIndex.humanVsHuman:
      case _DrawerIndex.aiVsAi:
      case _DrawerIndex.humanVsLAN:
      case _DrawerIndex.setupPosition:
        return true;
      case _DrawerIndex.statistics:
      case _DrawerIndex.settingsGroup:
      case _DrawerIndex.generalSettings:
      case _DrawerIndex.ruleSettings:
      case _DrawerIndex.appearance:
      case _DrawerIndex.helpGroup:
      case _DrawerIndex.howToPlay:
      case _DrawerIndex.feedback:
      case _DrawerIndex.about:
      case _DrawerIndex.exit:
        return false;
    }
  }

  // Function to handle route changes
  void _pushRoute(_DrawerIndex index) {
    final bool curIsGame = _isGame(_drawerIndex);
    final bool nextIsGame = _isGame(index);
    if (curIsGame && !nextIsGame) {
      _routes.push(index);
    } else if (!curIsGame && nextIsGame) {
      _routes.clear();
      _routes.push(index);
    } else {
      _routes.pop();
      _routes.push(index);
    }
    setState(() {});
  }

  bool _canPopRoute() {
    if (_routes.length > 1) {
      _routes.pop();
      setState(() {
        _drawerIndex = _routes.top();
        if (_drawerIndex.screen != null) {
          _screenView = _drawerIndex.screen!;
        }
        logger.t('_drawerIndex: $_drawerIndex');
      });
      return true;
    } else {
      return false;
    }
  }

  // Function to handle first time run
  void firstRun(BuildContext context) {
    if (DB().generalSettings.firstRun == true) {
      DB().generalSettings = DB().generalSettings.copyWith(firstRun: false);

      final Locale locale = Localizations.localeOf(context);
      final String languageCode = locale.languageCode;

      switch (languageCode) {
        case "af": // South Africa
        case "zu": // South Africa
          DB().ruleSettings = DB().ruleSettings.copyWith(
            piecesCount: 12,
            hasDiagonalLines: true,
            boardFullAction: BoardFullAction.agreeToDraw,
            endgameNMoveRule: 10,
            restrictRepeatedMillsFormation: true,
          );
          break;
        case "fa": // Iran
        case "si": // Sri Lanka
          DB().ruleSettings = DB().ruleSettings.copyWith(
            piecesCount: 12,
            hasDiagonalLines: true,
          );
          break;
        case "ru": // Russia
          DB().ruleSettings = DB().ruleSettings.copyWith(
            oneTimeUseMill: true,
            mayRemoveFromMillsAlways: true,
          );
          break;
        case "ko": // Korea
          DB().ruleSettings = DB().ruleSettings.copyWith(
            piecesCount: 12,
            hasDiagonalLines: true,
            mayFly: false,
            millFormationActionInPlacingPhase:
                MillFormationActionInPlacingPhase.markAndDelayRemovingPieces,
            mayRemoveFromMillsAlways: true,
          );
          break;
        default:
          break;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPrivacyDialog());
    _routes.push(_drawerIndex);
  }

  @override
  void didChangeDependencies() {
    firstRun(context);

    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.boardPadding =
        ((deviceWidth(context) - AppTheme.boardMargin * 2) *
                DB().displaySettings.pieceWidth /
                7) /
            2 +
        4;

    final List<CustomDrawerItem<_DrawerIndex>>
    drawerItems = <CustomDrawerItem<_DrawerIndex>>[
      if (!kIsWeb)
        CustomDrawerItem<_DrawerIndex>(
          key: const Key('drawer_item_human_vs_ai'),
          itemValue: _DrawerIndex.humanVsAi,
          itemTitle: S.of(context).humanVsAi,
          itemIcon: const Icon(FluentIcons.person_24_regular),
          currentSelectedValue: _drawerIndex,
          onSelectionChanged: _changeIndex,
        ),
      CustomDrawerItem<_DrawerIndex>(
        key: const Key('drawer_item_human_vs_human'),
        itemValue: _DrawerIndex.humanVsHuman,
        itemTitle: S.of(context).humanVsHuman,
        itemIcon: const Icon(FluentIcons.people_24_regular),
        currentSelectedValue: _drawerIndex,
        onSelectionChanged: _changeIndex,
      ),
      if (!kIsWeb)
        CustomDrawerItem<_DrawerIndex>(
          key: const Key('drawer_item_ai_vs_ai'),
          itemValue: _DrawerIndex.aiVsAi,
          itemTitle: S.of(context).aiVsAi,
          itemIcon: const Icon(FluentIcons.bot_24_regular),
          currentSelectedValue: _drawerIndex,
          onSelectionChanged: _changeIndex,
        ),
      CustomDrawerItem<_DrawerIndex>(
        key: const Key('drawer_item_human_vs_lan'),
        itemValue: _DrawerIndex.humanVsLAN,
        itemTitle: S.of(context).humanVsLAN,
        itemIcon: const Icon(FluentIcons.wifi_1_24_regular),
        currentSelectedValue: _drawerIndex,
        onSelectionChanged: _changeIndex,
      ),
      // Setup position does not yet model pieces in hand, so we hide it when
      // the current rule removes stones from a player's reserve.
      // TODO: Support removeOpponentsPieceFromHand
      if (DB().ruleSettings.millFormationActionInPlacingPhase !=
              MillFormationActionInPlacingPhase
                  .removeOpponentsPieceFromHandThenYourTurn &&
          DB().ruleSettings.millFormationActionInPlacingPhase !=
              MillFormationActionInPlacingPhase
                  .removeOpponentsPieceFromHandThenOpponentsTurn)
        CustomDrawerItem<_DrawerIndex>(
          key: const Key('drawer_item_setup_position'),
          itemValue: _DrawerIndex.setupPosition,
          itemTitle: S.of(context).setupPosition,
          itemIcon: const Icon(FluentIcons.drafts_24_regular),
          currentSelectedValue: _drawerIndex,
          onSelectionChanged: _changeIndex,
        ),
      // Statistics item
      CustomDrawerItem<_DrawerIndex>(
        key: const Key('drawer_item_statistics'),
        itemValue: _DrawerIndex.statistics,
        itemTitle: S.of(context).statistics,
        itemIcon: const Icon(FluentIcons.calculator_24_regular),
        currentSelectedValue: _drawerIndex,
        onSelectionChanged: _changeIndex,
      ),
      // Settings group item
      CustomDrawerItem<_DrawerIndex>(
        key: const Key('drawer_item_settings_group'), // Changed key
        itemValue: _DrawerIndex.settingsGroup, // New itemValue for the group
        itemTitle: S.of(context).settings,
        itemIcon: const Icon(FluentIcons.settings_24_regular),
        currentSelectedValue: _drawerIndex,
        onSelectionChanged: (_) {}, // Parent item tap is handled for expansion
        // Children are now part of the CustomDrawerItem's children list
        children: <CustomDrawerItem<_DrawerIndex>>[
          CustomDrawerItem<_DrawerIndex>(
            key: const Key(
              'drawer_item_general_settings_child',
            ), // Key for child
            itemValue: _DrawerIndex.generalSettings,
            itemTitle: S.of(context).generalSettings,
            itemIcon: const Icon(
              FluentIcons.options_24_regular,
            ), // Original icon
            currentSelectedValue: _drawerIndex,
            onSelectionChanged: _changeIndex,
            // No manual indentation needed
          ),
          CustomDrawerItem<_DrawerIndex>(
            key: const Key('drawer_item_rule_settings_child'), // Key for child
            itemValue: _DrawerIndex.ruleSettings,
            itemTitle: S.of(context).ruleSettings,
            itemIcon: const Icon(
              FluentIcons.task_list_ltr_24_regular,
            ), // Original icon
            currentSelectedValue: _drawerIndex,
            onSelectionChanged: _changeIndex,
            // No manual indentation needed
          ),
          CustomDrawerItem<_DrawerIndex>(
            key: const Key('drawer_item_appearance_child'), // Key for child
            itemValue: _DrawerIndex.appearance,
            itemTitle: S.of(context).appearance,
            itemIcon: const Icon(
              FluentIcons.design_ideas_24_regular,
            ), // Original icon
            currentSelectedValue: _drawerIndex,
            onSelectionChanged: _changeIndex,
            // No manual indentation needed
          ),
        ],
      ),
      // New "Help" group
      CustomDrawerItem<_DrawerIndex>(
        key: const Key('drawer_item_help_group'),
        itemValue: _DrawerIndex.helpGroup, // Use specific group itemValue
        itemTitle: S.of(context).help,
        itemIcon: const Icon(FluentIcons.question_circle_24_regular),
        currentSelectedValue: _drawerIndex,
        onSelectionChanged: (_) {}, // Parent item tap is handled for expansion
        children: <CustomDrawerItem<_DrawerIndex>>[
          CustomDrawerItem<_DrawerIndex>(
            key: const Key('drawer_item_how_to_play_child'),
            itemValue: _DrawerIndex.howToPlay,
            itemTitle: S.of(context).howToPlay,
            itemIcon: const Icon(FluentIcons.question_circle_24_regular),
            currentSelectedValue: _drawerIndex,
            onSelectionChanged: _changeIndex,
          ),
          if (!kIsWeb && Platform.isAndroid)
            CustomDrawerItem<_DrawerIndex>(
              key: const Key('drawer_item_feedback_child'),
              itemValue: _DrawerIndex.feedback,
              itemTitle: S.of(context).feedback,
              itemIcon: const Icon(FluentIcons.comment_24_regular),
              currentSelectedValue: _drawerIndex,
              onSelectionChanged: _changeIndex,
            ),
          CustomDrawerItem<_DrawerIndex>(
            key: const Key('drawer_item_about_child'),
            itemValue: _DrawerIndex.about,
            itemTitle: S.of(context).about,
            itemIcon: const Icon(FluentIcons.info_24_regular),
            currentSelectedValue: _drawerIndex,
            onSelectionChanged: _changeIndex,
          ),
        ],
      ),
      if (!kIsWeb && Platform.isAndroid)
        CustomDrawerItem<_DrawerIndex>(
          key: const Key('drawer_item_exit'),
          itemValue: _DrawerIndex.exit,
          itemTitle: S.of(context).exit,
          itemIcon: const Icon(FluentIcons.power_24_regular),
          currentSelectedValue: _drawerIndex,
          onSelectionChanged: _changeIndex,
        ),
    ];

    return DoubleBackToCloseApp(
      snackBar: CustomSnackBar(S.of(context).tapBackAgainToLeave),
      willBack: () {
        return !_canPopRoute();
      },
      child: WidgetsToImage(
        controller: GifShare().controller,
        child: ValueListenableBuilder<CustomDrawerValue>(
          valueListenable: _controller,
          builder: (_, CustomDrawerValue value, Widget? child) => CustomDrawer(
            key: CustomDrawer.drawerMainKey,
            controller: _controller,
            drawerHeader: CustomDrawerHeader(
              headerTitle: S.of(context).appName,
              key: const Key("custom_drawer_header"),
            ),
            drawerItems: drawerItems,
            disabledGestures:
                (!DB().displaySettings.swipeToRevealTheDrawer &&
                    !value.isDrawerVisible) ||
                ((kIsWeb ||
                        Platform.isWindows ||
                        Platform.isLinux ||
                        Platform.isMacOS) &&
                    _isGame(_drawerIndex) &&
                    !value.isDrawerVisible),
            orientation: MediaQuery.of(context).orientation,
            mainScreenWidget: _screenView,
          ),
        ),
      ),
    );
  }

  void _showPrivacyDialog() {
    if (EnvironmentConfig.test == true) {
      return;
    }

    if (!kDebugMode && // Add kDebugMode check here
        !DB().generalSettings.isPrivacyPolicyAccepted &&
        Localizations.localeOf(context).languageCode.startsWith("zh") &&
        (!kIsWeb && Platform.isAndroid)) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) =>
            PrivacyPolicyDialog(onConfirm: _showTutorialDialog),
      );
    } else {
      _showTutorialDialog();
    }
  }

  Future<void> _showTutorialDialog() async {
    // Skip tutorial dialog in debug mode
    if (!kDebugMode && DB().generalSettings.showTutorial) {
      await Navigator.of(context).push(
        MaterialPageRoute<dynamic>(
          builder: (BuildContext context) => const TutorialDialog(),
          fullscreenDialog: true,
        ),
      );

      // Show rule settings onboarding dialog for Russian and Persian locales
      _showRuleSettingsOnboarding();
    }
  }

  /// Show rule settings onboarding dialog for specific locales
  void _showRuleSettingsOnboarding() {
    final Locale locale = Localizations.localeOf(context);
    final String languageCode = locale.languageCode;

    // Only show for Russian (ru) and Persian (fa) locales
    if (languageCode == 'af' ||
        languageCode == 'ru' ||
        languageCode == 'fa' ||
        languageCode == 'fr' ||
        languageCode == 'nl' ||
        languageCode == 'tr' ||
        languageCode == 'zh') {
      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(S.of(context).configureRules),
            content: Text(S.of(context).configureRulesPrompt),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  // User chose not to configure rules, just close the dialog
                  Navigator.of(context).pop(false);
                },
                child: Text(S.of(context).no),
              ),
              TextButton(
                onPressed: () {
                  // User chose to configure rules
                  Navigator.of(context).pop(true);
                },
                child: Text(S.of(context).yes),
              ),
            ],
          );
        },
      ).then((bool? result) {
        if (result == true) {
          // Navigate to Rule Settings page
          _changeIndex(_DrawerIndex.ruleSettings);
        }
        // If result is false or null, do nothing (no prompt on exit)
      });
    }
  }

  /// Drafts an email and sends it to the developer
  static Future<void> _launchFeedback(UserFeedback feedback) async {
    final String screenshotFilePath = await _saveFeedbackImage(
      feedback.screenshot,
    );

    final String optionsContent = generateOptionsContent();
    final String optionsFilePath = await _saveOptionsContentToFile(
      optionsContent,
    );

    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    final String version =
        "${packageInfo.version} (${packageInfo.buildNumber})";

    final Email email = Email(
      body: feedback.text,
      subject:
          Constants.feedbackSubjectPrefix +
          version +
          Constants.feedbackSubjectSuffix,
      recipients: Constants.recipientEmails,
      attachmentPaths: <String>[screenshotFilePath, optionsFilePath],
    );

    await FlutterEmailSender.send(email);
  }

  static Future<String> _saveOptionsContentToFile(String content) async {
    final Directory output = await getTemporaryDirectory();
    final File file = File('${output.path}/sanmill-options.txt');

    // Delete the file synchronously if it exists to avoid slow async IO operations
    if (file.existsSync()) {
      file.deleteSync();
    }

    // Write content to the file asynchronously
    await file.writeAsString(content);
    return file.path;
  }

  static Future<String> _saveFeedbackImage(Uint8List screenshot) async {
    final Directory output = await getTemporaryDirectory();
    final String screenshotFilePath = "${output.path}/sanmill-feedback.png";
    final File screenshotFile = File(screenshotFilePath);

    // Delete the screenshot file synchronously if it exists
    if (screenshotFile.existsSync()) {
      screenshotFile.deleteSync();
    }

    // Write bytes to the screenshot file asynchronously
    await screenshotFile.writeAsBytes(screenshot);
    return screenshotFilePath;
  }
}
