// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// home.dart

import 'dart:async';
import 'dart:io';

import 'package:feedback/feedback.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../custom_drawer/custom_drawer.dart';
import '../experience_recording/models/recording_models.dart';
import '../experience_recording/services/recording_service.dart';
import '../game_page/services/gif_share/gif_share.dart';
import '../game_page/services/gif_share/widgets_to_image.dart';
import '../game_page/services/mill.dart' show GameController;
import '../game_page/services/painters/painters.dart';
import '../game_page/widgets/dialogs/lan_config_dialog.dart';
import '../game_platform/game_id.dart';
import '../game_platform/game_menu.dart';
import '../game_platform/game_module.dart';
import '../game_platform/game_registry.dart';
import '../game_platform/game_session.dart';
import '../game_platform/game_session_handle.dart';
import '../game_shell/game_session_scope.dart';
import '../game_shell/game_surface_host.dart';
import '../game_shell/shell_route_ids.dart';
import '../general_settings/models/general_settings.dart';
import '../general_settings/services/config_import_export_service.dart';
import '../generated/intl/l10n.dart';
import '../rule_settings/models/rule_settings.dart';
import '../shared/config/constants.dart';
import '../shared/database/database.dart';
import '../shared/database/settings_repositories.dart';
import '../shared/database/settings_repository.dart';
import '../shared/dialogs/privacy_policy_dialog.dart';
import '../shared/services/catcher_service.dart' show generateOptionsContent;
import '../shared/services/environment_config.dart';
import '../shared/services/logger.dart';
import '../shared/services/snackbar_service.dart';
import '../shared/themes/app_theme.dart';
import '../shared/utils/helpers/list_helpers/stack_list.dart';
import '../shared/widgets/double_back_to_close_app.dart';
import '../shared/widgets/snackbars/scaffold_messenger.dart';
import '../tutorial/widgets/tutorial_dialog.dart';
import 'mill_route_screens.dart';

/// Home View
///
/// Hosts the shared multi-game shell. Drawer entries are sourced from the
/// active [GameModule]'s [GameModule.playModes] and
/// [GameModule.drawerContributions] together with app-level routes (settings,
/// help, exit) defined by [ShellRouteIds].
class Home extends StatefulWidget {
  const Home({super.key});

  static const Key homeMainKey = Key('home_main');

  @override
  HomeState createState() => HomeState();
}

class HomeState extends State<Home> with TickerProviderStateMixin {
  final CustomDrawerController _controller = CustomDrawerController();

  late String _routeId;
  Widget? _screenView;
  final StackList<String> _routes = StackList<String>();
  bool _initialized = false;

  /// Active session for the current [GameId]. Owned by [Home].
  GameSessionHandle? _activeSession;
  GameId? _activeSessionGameId;

  SettingsRepository get _settingsRepository =>
      SettingsRepositories.instance.current.repository;

  String _initialMillRoute() {
    return kIsWeb
        ? ShellRouteIds.millHumanVsHuman
        : ShellRouteIds.millHumanVsAi;
  }

  void _ensureSessionForCurrentGame() {
    final GameId currentId = GameRegistry.instance.currentId;
    if (_activeSessionGameId == currentId && _activeSession != null) {
      return;
    }
    _activeSession?.dispose();
    final GameModule? module = GameRegistry.instance.getModule(currentId);
    _activeSession = module?.startSession();
    _activeSessionGameId = currentId;
  }

  void _onRegistryChanged() {
    if (!mounted) {
      return;
    }
    _ensureSessionForCurrentGame();
    final GameId currentId = GameRegistry.instance.currentId;
    if (currentId == GameId.mill) {
      // Returning to Mill: reset to a sane default route.
      _routes.clear();
      _routeId = _initialMillRoute();
      _routes.push(_routeId);
      _screenView = buildMillModuleScreen(
        context,
        _routeId,
        session: _activeSession,
      );
    }
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _routeId = _initialMillRoute();
    GameRegistry.instance.addListener(_onRegistryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPrivacyDialog());
    _routes.push(_routeId);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _ensureSessionForCurrentGame();
      _screenView ??= buildMillModuleScreen(
        context,
        _routeId,
        session: _activeSession,
      );
      firstRun(context);
    }
  }

  @override
  void dispose() {
    GameRegistry.instance.removeListener(_onRegistryChanged);
    _activeSession?.dispose();
    _activeSession = null;
    _controller.dispose();
    super.dispose();
  }

  Future<void> _selectRoute(String routeId) async {
    _controller.hideDrawer();

    if (routeId == ShellRouteIds.appSettingsGroup ||
        routeId == ShellRouteIds.appHelpGroup) {
      // Group expand/collapse is handled by [CustomDrawerItem] internally.
      return;
    }

    if (routeId == ShellRouteIds.debugPlatformProbe) {
      logger.i('Switching to platform probe (tic-tac-toe demo).');
      GameRegistry.instance.select(GameId.demoProbe);
      return;
    }

    if (routeId == ShellRouteIds.appExit) {
      logger.i('Exiting...');
      if (EnvironmentConfig.test == false && !kIsWeb) {
        SystemChannels.platform.invokeMethod<void>('SystemNavigator.pop');
      }
      return;
    }

    if ((routeId == ShellRouteIds.appHowToPlay ||
            routeId == ShellRouteIds.appAbout ||
            routeId == ShellRouteIds.appFeedback) &&
        EnvironmentConfig.test == true) {
      logger.w('Do not test HowToPlay/Feedback/About page.');
      return;
    }

    if (routeId == ShellRouteIds.appFeedback) {
      logger.i('Switching to Feedback');
      if (Platform.isAndroid) {
        BetterFeedback.of(context).show(_launchFeedback);
      } else {
        logger.w('flutter_email_sender does not support this platform.');
      }
      return;
    }

    if (routeId == ShellRouteIds.millHumanVsLan &&
        _routeId != ShellRouteIds.millHumanVsLan) {
      SnackBarService.showRootSnackBar(S.of(context).experimental);
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext _) => const LanConfigDialog(),
      );
      if (confirmed != true) {
        return;
      }
    }

    if (_routeId == ShellRouteIds.millHumanVsLan &&
        routeId != ShellRouteIds.millHumanVsLan) {
      logger.i('Leaving LAN mode: disposing network and resetting the board.');
      // ignore: deprecated_member_use_from_same_package
      GameController().networkService?.dispose();
      // ignore: deprecated_member_use_from_same_package
      GameController().networkService = null;
      // ignore: deprecated_member_use_from_same_package
      GameController().reset(force: true);
    }

    if (!mounted) {
      return;
    }
    final Widget? screen =
        buildMillModuleScreen(context, routeId, session: _activeSession) ??
        buildAppShellScreen(context, routeId);
    if (screen == null) {
      logger.w('No screen for route $routeId.');
      return;
    }

    if (_routeId == routeId) {
      // Same route — nothing to push onto the stack.
      return;
    }

    RecordingService().recordEvent(
      RecordingEventType.gameModeChange,
      <String, dynamic>{'mode': routeId},
    );

    setState(() {
      _pushRoute(routeId);
      _routeId = routeId;
      _screenView = screen;
    });
  }

  bool _routeIsGame(String routeId) {
    return isMillPlayRoute(routeId);
  }

  void _pushRoute(String routeId) {
    final bool curIsGame = _routeIsGame(_routeId);
    final bool nextIsGame = _routeIsGame(routeId);
    if (curIsGame && !nextIsGame) {
      _routes.push(routeId);
    } else if (!curIsGame && nextIsGame) {
      _routes.clear();
      _routes.push(routeId);
    } else {
      if (_routes.isNotEmpty) {
        _routes.pop();
      }
      _routes.push(routeId);
    }
  }

  bool _canPopRoute() {
    if (_routes.length > 1) {
      _routes.pop();
      final String previous = _routes.top();
      final Widget? screen =
          buildMillModuleScreen(context, previous, session: _activeSession) ??
          buildAppShellScreen(context, previous);
      setState(() {
        _routeId = previous;
        if (screen != null) {
          _screenView = screen;
        }
        logger.t('_routeId: $_routeId');
      });
      return true;
    }
    return false;
  }

  void firstRun(BuildContext context) {
    if (_settingsRepository.generalSettings.firstRun != true) {
      return;
    }
    _settingsRepository.generalSettings = _settingsRepository.generalSettings
        .copyWith(firstRun: false);

    if (GameRegistry.instance.currentId != GameId.mill) {
      // Locale-driven Mill rule presets are Mill-specific.
      return;
    }
    final Locale locale = Localizations.localeOf(context);
    final String languageCode = locale.languageCode;

    switch (languageCode) {
      case 'af': // South Africa
      case 'zu': // South Africa
        _settingsRepository.ruleSettings = _settingsRepository.ruleSettings
            .copyWith(
              piecesCount: 12,
              hasDiagonalLines: true,
              boardFullAction: BoardFullAction.agreeToDraw,
              endgameNMoveRule: 10,
              restrictRepeatedMillsFormation: true,
            );
        break;
      case 'fa': // Iran
      case 'si': // Sri Lanka
        _settingsRepository.ruleSettings = _settingsRepository.ruleSettings
            .copyWith(piecesCount: 12, hasDiagonalLines: true);
        break;
      case 'ru': // Russia
        _settingsRepository.ruleSettings = _settingsRepository.ruleSettings
            .copyWith(oneTimeUseMill: true, mayRemoveFromMillsAlways: true);
        break;
      case 'ko': // Korea
        _settingsRepository.ruleSettings = _settingsRepository.ruleSettings
            .copyWith(
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GameRegistry.instance,
      builder: (BuildContext context, Widget? _) {
        _ensureSessionForCurrentGame();
        final GameId currentId = GameRegistry.instance.currentId;
        final GameSession? session = _activeSession;
        Widget body;
        if (currentId == GameId.mill) {
          body = _buildMillAppHome(context);
        } else {
          body = GameSurfaceHost(
            gameId: currentId,
            externalSession: session,
            onClose: () => GameRegistry.instance.select(GameId.mill),
          );
        }
        if (session != null) {
          return GameSessionScope(session: session, child: body);
        }
        return body;
      },
    );
  }

  // --- Drawer item construction --------------------------------------------

  /// Maps a [ShellRouteIds] route to a stable drawer-item key. Keeping these
  /// keys preserves existing integration tests.
  Key? _drawerItemKey(String routeId) {
    switch (routeId) {
      case ShellRouteIds.millHumanVsAi:
        return const Key('drawer_item_human_vs_ai');
      case ShellRouteIds.millHumanVsHuman:
        return const Key('drawer_item_human_vs_human');
      case ShellRouteIds.millAiVsAi:
        return const Key('drawer_item_ai_vs_ai');
      case ShellRouteIds.millHumanVsLan:
        return const Key('drawer_item_human_vs_lan');
      case ShellRouteIds.millSetupPosition:
        return const Key('drawer_item_setup_position');
      case ShellRouteIds.millPuzzles:
        return const Key('drawer_item_puzzles');
      case ShellRouteIds.millStatistics:
        return const Key('drawer_item_statistics');
      case ShellRouteIds.appSettingsGroup:
        return const Key('drawer_item_settings_group');
      case ShellRouteIds.appGeneralSettings:
        return const Key('drawer_item_general_settings_child');
      case ShellRouteIds.appRuleSettings:
        return const Key('drawer_item_rule_settings_child');
      case ShellRouteIds.appAppearance:
        return const Key('drawer_item_appearance_child');
      case ShellRouteIds.appHelpGroup:
        return const Key('drawer_item_help_group');
      case ShellRouteIds.appHowToPlay:
        return const Key('drawer_item_how_to_play_child');
      case ShellRouteIds.appFeedback:
        return const Key('drawer_item_feedback_child');
      case ShellRouteIds.appAbout:
        return const Key('drawer_item_about_child');
      case ShellRouteIds.appExit:
        return const Key('drawer_item_exit');
      case ShellRouteIds.debugPlatformProbe:
        return const Key('drawer_item_platform_probe');
      default:
        return null;
    }
  }

  /// Default fluent icon for built-in routes.
  Icon _iconFor(String routeId) {
    switch (routeId) {
      case ShellRouteIds.millHumanVsAi:
        return const Icon(FluentIcons.person_24_regular);
      case ShellRouteIds.millHumanVsHuman:
        return const Icon(FluentIcons.people_24_regular);
      case ShellRouteIds.millAiVsAi:
        return const Icon(FluentIcons.bot_24_regular);
      case ShellRouteIds.millHumanVsLan:
        return const Icon(FluentIcons.wifi_1_24_regular);
      case ShellRouteIds.millSetupPosition:
        return const Icon(FluentIcons.drafts_24_regular);
      case ShellRouteIds.millPuzzles:
        return const Icon(FluentIcons.puzzle_piece_24_regular);
      case ShellRouteIds.millStatistics:
        return const Icon(FluentIcons.calculator_24_regular);
      case ShellRouteIds.appSettingsGroup:
        return const Icon(FluentIcons.settings_24_regular);
      case ShellRouteIds.appGeneralSettings:
        return const Icon(FluentIcons.options_24_regular);
      case ShellRouteIds.appRuleSettings:
        return const Icon(FluentIcons.task_list_ltr_24_regular);
      case ShellRouteIds.appAppearance:
        return const Icon(FluentIcons.design_ideas_24_regular);
      case ShellRouteIds.appHelpGroup:
        return const Icon(FluentIcons.question_circle_24_regular);
      case ShellRouteIds.appHowToPlay:
        return const Icon(FluentIcons.question_circle_24_regular);
      case ShellRouteIds.appFeedback:
        return const Icon(FluentIcons.comment_24_regular);
      case ShellRouteIds.appAbout:
        return const Icon(FluentIcons.info_24_regular);
      case ShellRouteIds.appExit:
        return const Icon(FluentIcons.power_24_regular);
      case ShellRouteIds.debugPlatformProbe:
        return const Icon(Icons.science_outlined);
      default:
        return const Icon(FluentIcons.apps_24_regular);
    }
  }

  CustomDrawerItem<String> _modeItem(GameModeEntry mode) {
    return CustomDrawerItem<String>(
      key: _drawerItemKey(mode.id),
      itemValue: mode.id,
      itemTitle: mode.label,
      itemIcon: _iconFor(mode.id),
      currentSelectedValue: _routeId,
      onSelectionChanged: _selectRoute,
    );
  }

  CustomDrawerItem<String> _contributionItem(GameMenuContribution c) {
    return CustomDrawerItem<String>(
      key: _drawerItemKey(c.id),
      itemValue: c.id,
      itemTitle: c.label,
      itemIcon: _iconFor(c.id),
      currentSelectedValue: _routeId,
      onSelectionChanged: _selectRoute,
    );
  }

  CustomDrawerItem<String> _appItem(
    String routeId,
    String label, {
    List<CustomDrawerItem<String>>? children,
    Function(String)? onTap,
  }) {
    return CustomDrawerItem<String>(
      key: _drawerItemKey(routeId),
      itemValue: routeId,
      itemTitle: label,
      itemIcon: _iconFor(routeId),
      currentSelectedValue: _routeId,
      onSelectionChanged: onTap ?? _selectRoute,
      children: children,
    );
  }

  Widget _buildMillAppHome(BuildContext context) {
    AppTheme.boardPadding =
        ((deviceWidth(context) - AppTheme.boardMargin * 2) *
                DB().displaySettings.pieceWidth /
                7) /
            2 +
        4;

    final S s = S.of(context);
    final GameModule millModule = GameRegistry.instance.current;

    final List<GameModeEntry> playModes = millModule
        .playModes(context)
        .where((GameModeEntry m) => m.availableIn(context))
        .toList();
    final List<GameMenuContribution> contributions = millModule
        .drawerContributions(context)
        .where((GameMenuContribution c) => c.availableIn(context))
        .toList();

    final List<CustomDrawerItem<String>> drawerItems =
        <CustomDrawerItem<String>>[
          ...playModes.map(_modeItem),
          ...contributions
              .where(
                (GameMenuContribution c) => c.section == GameMenuSection.game,
              )
              .map(_contributionItem),
          _appItem(
            ShellRouteIds.appSettingsGroup,
            s.settings,
            onTap: (_) {},
            children: <CustomDrawerItem<String>>[
              _appItem(ShellRouteIds.appGeneralSettings, s.generalSettings),
              _appItem(ShellRouteIds.appRuleSettings, s.ruleSettings),
              _appItem(ShellRouteIds.appAppearance, s.appearance),
            ],
          ),
          _appItem(
            ShellRouteIds.appHelpGroup,
            s.help,
            onTap: (_) {},
            children: <CustomDrawerItem<String>>[
              _appItem(ShellRouteIds.appHowToPlay, s.howToPlay),
              if (!kIsWeb && Platform.isAndroid)
                _appItem(ShellRouteIds.appFeedback, s.feedback),
              _appItem(ShellRouteIds.appAbout, s.about),
            ],
          ),
          if (!kIsWeb && Platform.isAndroid)
            _appItem(ShellRouteIds.appExit, s.exit),
          if (kDebugMode &&
              GameRegistry.instance.getModule(GameId.demoProbe) != null)
            _appItem(ShellRouteIds.debugPlatformProbe, 'Tic-Tac-Toe (sample)'),
        ];

    return DoubleBackToCloseApp(
      snackBar: CustomSnackBar(s.tapBackAgainToLeave),
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
              headerTitle: s.appName,
              key: const Key('custom_drawer_header'),
            ),
            drawerItems: drawerItems,
            disabledGestures:
                (!DB().displaySettings.swipeToRevealTheDrawer &&
                    !value.isDrawerVisible) ||
                ((kIsWeb ||
                        Platform.isWindows ||
                        Platform.isLinux ||
                        Platform.isMacOS) &&
                    _routeIsGame(_routeId) &&
                    !value.isDrawerVisible),
            orientation: MediaQuery.of(context).orientation,
            mainScreenWidget: _screenView ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  void _showPrivacyDialog() {
    if (EnvironmentConfig.test == true) {
      return;
    }

    if (!kDebugMode &&
        !DB().generalSettings.isPrivacyPolicyAccepted &&
        Localizations.localeOf(context).languageCode.startsWith('zh') &&
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
    if (!kDebugMode && DB().generalSettings.showTutorial) {
      await Navigator.of(context).push(
        MaterialPageRoute<dynamic>(
          builder: (BuildContext context) => const TutorialDialog(),
          fullscreenDialog: true,
        ),
      );
      _showRuleSettingsOnboarding();
    }
  }

  void _showRuleSettingsOnboarding() {
    final Locale locale = Localizations.localeOf(context);
    final String languageCode = locale.languageCode;

    if (languageCode == 'af' ||
        languageCode == 'fa' ||
        languageCode == 'fr' ||
        languageCode == 'nb' ||
        languageCode == 'nl' ||
        languageCode == 'ru' ||
        languageCode == 'tr' ||
        languageCode == 'uk' ||
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
                  Navigator.of(context).pop(false);
                },
                child: Text(S.of(context).no),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
                child: Text(S.of(context).yes),
              ),
            ],
          );
        },
      ).then((bool? result) {
        if (result ?? false) {
          _selectRoute(ShellRouteIds.appRuleSettings);
        }
      });
    }
  }

  static Future<void> _launchFeedback(UserFeedback feedback) async {
    final String screenshotFilePath = await _saveFeedbackImage(
      feedback.screenshot,
    );

    final String optionsContent = generateOptionsContent();
    final String optionsFilePath = await _saveOptionsContentToFile(
      optionsContent,
    );

    final String? configFilePath =
        await ConfigImportExportService.exportSettingsJsonOnly();

    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    final String version =
        '${packageInfo.version} (${packageInfo.buildNumber})';

    final Email email = Email(
      body: feedback.text,
      subject:
          Constants.feedbackSubjectPrefix +
          version +
          Constants.feedbackSubjectSuffix,
      recipients: Constants.recipientEmails,
      attachmentPaths: <String>[
        screenshotFilePath,
        optionsFilePath,
        ?configFilePath,
      ],
    );

    await FlutterEmailSender.send(email);
  }

  static Future<String> _saveOptionsContentToFile(String content) async {
    final Directory output = await getTemporaryDirectory();
    final File file = File('${output.path}/sanmill-options.txt');
    if (file.existsSync()) {
      file.deleteSync();
    }
    await file.writeAsString(content);
    return file.path;
  }

  static Future<String> _saveFeedbackImage(Uint8List screenshot) async {
    final Directory output = await getTemporaryDirectory();
    final String screenshotFilePath = '${output.path}/sanmill-feedback.png';
    final File screenshotFile = File(screenshotFilePath);
    if (screenshotFile.existsSync()) {
      screenshotFile.deleteSync();
    }
    await screenshotFile.writeAsBytes(screenshot);
    return screenshotFilePath;
  }
}
