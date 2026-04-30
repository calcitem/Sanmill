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
import '../game_platform/game_id.dart';
import '../game_platform/game_menu.dart';
import '../game_platform/game_module.dart';
import '../game_platform/game_registry.dart';
import '../game_platform/game_route_id.dart';
import '../game_platform/game_session.dart';
import '../game_platform/game_session_handle.dart';
import '../game_shell/debug_route_ids.dart';
import '../game_shell/game_session_scope.dart';
import '../game_shell/shared_game_shell.dart';
import '../game_shell/shell_route_ids.dart';
import '../games/mill/mill_session_recorder_bridge.dart';
import '../general_settings/models/general_settings.dart';
import '../general_settings/services/config_import_export_service.dart';
import '../generated/intl/l10n.dart';
import '../shared/config/constants.dart';
import '../shared/database/database.dart';
import '../shared/database/settings_repositories.dart';
import '../shared/database/settings_repository.dart';
import '../shared/dialogs/privacy_policy_dialog.dart';
import '../shared/services/catcher_service.dart' show generateOptionsContent;
import '../shared/services/environment_config.dart';
import '../shared/services/logger.dart';
import '../shared/utils/helpers/list_helpers/stack_list.dart';
import '../shared/widgets/snackbars/scaffold_messenger.dart';
import '../tutorial/widgets/tutorial_dialog.dart';
import 'module_route_screens.dart';

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
  MillSessionRecorderBridge? _activeMillRecorderBridge;

  SettingsRepository get _settingsRepository =>
      SettingsRepositories.instance.current.repository;

  void _ensureSessionForCurrentGame() {
    final GameId currentId = GameRegistry.instance.currentId;
    if (_activeSessionGameId == currentId && _activeSession != null) {
      return;
    }
    _disposeActiveMillRecorderBridge();
    _activeSession?.dispose();
    final GameModule? module = GameRegistry.instance.getModule(currentId);
    _activeSession = module?.startSession();
    _activeSessionGameId = currentId;
    final GameSessionHandle? session = _activeSession;
    if (currentId == GameId.mill && session != null) {
      _activeMillRecorderBridge = MillSessionRecorderBridge.forGameController(
        session: session,
      );
    }
  }

  void _onRegistryChanged() {
    if (!mounted) {
      return;
    }
    final GameId newId = GameRegistry.instance.currentId;
    if (_activeSessionGameId != null && _activeSessionGameId != newId) {
      final GameId oldId = _activeSessionGameId!;
      final GameModule? oldModule = GameRegistry.instance.getModule(oldId);
      oldModule?.onShellInactive(context, lastShellRouteId: _routeId);
    }
    _ensureSessionForCurrentGame();
    _routes.clear();
    final GameModule m = GameRegistry.instance.current;
    _routeId = m.defaultShellRoute(context);
    _routes.push(_routeId);
    _screenView = buildModuleScreenForGame(
      context,
      newId,
      _routeId,
      session: _activeSession,
    );
    m.didNavigateShellRoute(
      context,
      previousRouteId: null,
      nextRouteId: _routeId,
    );
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    GameRegistry.instance.addListener(_onRegistryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPrivacyDialog());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _ensureSessionForCurrentGame();
      final GameModule m = GameRegistry.instance.current;
      _routeId = m.defaultShellRoute(context);
      _routes.push(_routeId);
      _screenView = buildModuleScreenForGame(
        context,
        m.metadata.id,
        _routeId,
        session: _activeSession,
      );
      m.didNavigateShellRoute(
        context,
        previousRouteId: null,
        nextRouteId: _routeId,
      );
      firstRun(context);
    }
  }

  @override
  void dispose() {
    GameRegistry.instance.removeListener(_onRegistryChanged);
    _disposeActiveMillRecorderBridge();
    _activeSession?.dispose();
    _activeSession = null;
    _controller.dispose();
    super.dispose();
  }

  void _disposeActiveMillRecorderBridge() {
    final MillSessionRecorderBridge? bridge = _activeMillRecorderBridge;
    if (bridge == null) {
      return;
    }
    _activeMillRecorderBridge = null;
    unawaited(bridge.dispose());
  }

  Future<void> _selectRoute(String routeId) async {
    _controller.hideDrawer();

    if (routeId == ShellRouteIds.appSettingsGroup.value ||
        routeId == ShellRouteIds.appHelpGroup.value) {
      // Group expand/collapse is handled by [CustomDrawerItem] internally.
      return;
    }

    if (routeId == ShellRouteIds.appBackToMainGame.value) {
      GameRegistry.instance.selectPrimary();
      return;
    }

    if (routeId == DebugRouteIds.platformProbe.value) {
      logger.i('Switching to platform probe (tic-tac-toe demo).');
      GameRegistry.instance.select(GameId.demoProbe);
      return;
    }

    if (routeId == ShellRouteIds.appExit.value) {
      logger.i('Exiting...');
      if (EnvironmentConfig.test == false && !kIsWeb) {
        SystemChannels.platform.invokeMethod<void>('SystemNavigator.pop');
      }
      return;
    }

    if ((routeId == ShellRouteIds.appHowToPlay.value ||
            routeId == ShellRouteIds.appAbout.value ||
            routeId == ShellRouteIds.appFeedback.value) &&
        EnvironmentConfig.test == true) {
      logger.w('Do not test HowToPlay/Feedback/About page.');
      return;
    }

    if (routeId == ShellRouteIds.appFeedback.value) {
      logger.i('Switching to Feedback');
      if (Platform.isAndroid) {
        BetterFeedback.of(context).show(_launchFeedback);
      } else {
        logger.w('flutter_email_sender does not support this platform.');
      }
      return;
    }

    if (!mounted) {
      return;
    }

    if (_routeId == routeId) {
      return;
    }

    final GameModule module = GameRegistry.instance.current;
    if (!await module.willNavigateToShellRoute(
      context,
      previousRouteId: _routeId,
      nextRouteId: routeId,
    )) {
      return;
    }
    if (!mounted) {
      return;
    }

    module.didNavigateShellRoute(
      context,
      previousRouteId: _routeId,
      nextRouteId: routeId,
    );

    final Widget? screen =
        buildModuleScreenForGame(
          context,
          GameRegistry.instance.currentId,
          routeId,
          session: _activeSession,
        ) ??
        buildAppShellScreen(context, routeId);
    if (screen == null) {
      logger.w('No screen for route $routeId.');
      return;
    }

    if (!mounted) {
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

  /// Primary play mode routes (per [GameModule.playModes]) vs settings/help.
  bool _routeIsPlayModeSurface(BuildContext context, String routeId) {
    final GameModule module = GameRegistry.instance.current;
    return module.isPlayModeRoute(routeId, context);
  }

  void _pushRoute(String routeId) {
    final bool curIsGame = _routeIsPlayModeSurface(context, _routeId);
    final bool nextIsGame = _routeIsPlayModeSurface(context, routeId);
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
    if (_routes.length <= 1) {
      return false;
    }
    final String fromRoute = _routeId;
    _routes.pop();
    final String toRoute = _routes.top();
    GameRegistry.instance.current.didNavigateShellRoute(
      context,
      previousRouteId: fromRoute,
      nextRouteId: toRoute,
    );
    final Widget? screen =
        buildModuleScreenForGame(
          context,
          GameRegistry.instance.currentId,
          toRoute,
          session: _activeSession,
        ) ??
        buildAppShellScreen(context, toRoute);
    if (screen == null) {
      return false;
    }
    setState(() {
      _routeId = toRoute;
      _screenView = screen;
      logger.t('_routeId: $_routeId');
    });
    return true;
  }

  void firstRun(BuildContext context) {
    if (_settingsRepository.generalSettings.firstRun != true) {
      return;
    }
    _settingsRepository.generalSettings = _settingsRepository.generalSettings
        .copyWith(firstRun: false);

    GameRegistry.instance.current.applyFirstRunDefaults(context);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GameRegistry.instance,
      builder: (BuildContext context, Widget? _) {
        _ensureSessionForCurrentGame();
        final GameSession? session = _activeSession;
        final Widget body = _buildGameShellHome(context);
        if (session != null) {
          return GameSessionScope(session: session, child: body);
        }
        return body;
      },
    );
  }

  // --- Drawer item construction --------------------------------------------

  /// Maps a route id string to a stable drawer-item [Key].
  ///
  /// Keeping these keys stable preserves existing integration tests.
  static final Map<String, Key> _routeToDrawerKey = <String, Key>{
    ShellRouteIds.appSettingsGroup.value: const Key(
      'drawer_item_settings_group',
    ),
    ShellRouteIds.appGeneralSettings.value: const Key(
      'drawer_item_general_settings_child',
    ),
    ShellRouteIds.appRuleSettings.value: const Key(
      'drawer_item_rule_settings_child',
    ),
    ShellRouteIds.appAppearance.value: const Key(
      'drawer_item_appearance_child',
    ),
    ShellRouteIds.appHelpGroup.value: const Key('drawer_item_help_group'),
    ShellRouteIds.appHowToPlay.value: const Key(
      'drawer_item_how_to_play_child',
    ),
    ShellRouteIds.appFeedback.value: const Key('drawer_item_feedback_child'),
    ShellRouteIds.appAbout.value: const Key('drawer_item_about_child'),
    ShellRouteIds.appExit.value: const Key('drawer_item_exit'),
    ShellRouteIds.appBackToMainGame.value: const Key(
      'drawer_item_back_to_main_game',
    ),
    DebugRouteIds.platformProbe.value: const Key('drawer_item_platform_probe'),
  };

  /// Maps a route id string to the fluent icon shown in the drawer.
  static final Map<String, Icon> _routeToIcon = <String, Icon>{
    ShellRouteIds.appSettingsGroup.value: const Icon(
      FluentIcons.settings_24_regular,
    ),
    ShellRouteIds.appGeneralSettings.value: const Icon(
      FluentIcons.options_24_regular,
    ),
    ShellRouteIds.appRuleSettings.value: const Icon(
      FluentIcons.task_list_ltr_24_regular,
    ),
    ShellRouteIds.appAppearance.value: const Icon(
      FluentIcons.design_ideas_24_regular,
    ),
    ShellRouteIds.appHelpGroup.value: const Icon(
      FluentIcons.question_circle_24_regular,
    ),
    ShellRouteIds.appHowToPlay.value: const Icon(
      FluentIcons.question_circle_24_regular,
    ),
    ShellRouteIds.appFeedback.value: const Icon(FluentIcons.comment_24_regular),
    ShellRouteIds.appAbout.value: const Icon(FluentIcons.info_24_regular),
    ShellRouteIds.appExit.value: const Icon(FluentIcons.power_24_regular),
    ShellRouteIds.appBackToMainGame.value: const Icon(
      FluentIcons.home_24_regular,
    ),
    DebugRouteIds.platformProbe.value: const Icon(Icons.science_outlined),
  };

  /// Returns the stable drawer-item [Key] for [routeId], or `null` if unknown.
  Key? _drawerItemKey(String routeId, {Key? moduleKey}) =>
      moduleKey ?? _routeToDrawerKey[routeId];

  /// Returns the icon for [routeId], falling back to a generic apps icon for
  /// routes contributed by game modules that do not provide metadata yet.
  Icon _iconFor(String routeId, {IconData? moduleIcon}) => moduleIcon == null
      ? _routeToIcon[routeId] ?? const Icon(FluentIcons.apps_24_regular)
      : Icon(moduleIcon);

  CustomDrawerItem<String> _modeItem(GameModeEntry mode) {
    return CustomDrawerItem<String>(
      key: _drawerItemKey(mode.id.value, moduleKey: mode.drawerKey),
      itemValue: mode.id.value,
      itemTitle: mode.label,
      itemIcon: _iconFor(mode.id.value, moduleIcon: mode.icon),
      currentSelectedValue: _routeId,
      onSelectionChanged: _selectRoute,
    );
  }

  CustomDrawerItem<String> _contributionItem(GameMenuContribution c) {
    return CustomDrawerItem<String>(
      key: _drawerItemKey(c.id.value, moduleKey: c.drawerKey),
      itemValue: c.id.value,
      itemTitle: c.label,
      itemIcon: _iconFor(c.id.value, moduleIcon: c.icon),
      currentSelectedValue: _routeId,
      onSelectionChanged: _selectRoute,
    );
  }

  CustomDrawerItem<String> _appItem(
    GameRouteId routeId,
    String label, {
    List<CustomDrawerItem<String>>? children,
    Function(String)? onTap,
  }) {
    return CustomDrawerItem<String>(
      key: _drawerItemKey(routeId.value),
      itemValue: routeId.value,
      itemTitle: label,
      itemIcon: _iconFor(routeId.value),
      currentSelectedValue: _routeId,
      onSelectionChanged: onTap ?? _selectRoute,
      children: children,
    );
  }

  Widget _buildGameShellHome(BuildContext context) {
    final GameModule gameModule = GameRegistry.instance.current;
    gameModule.applyShellLayoutHints(context);

    final S s = S.of(context);

    final List<GameModeEntry> playModes = gameModule
        .playModes(context)
        .where((GameModeEntry m) => m.availableIn(context))
        .toList();
    final List<GameMenuContribution> contributions = gameModule
        .drawerContributions(context)
        .where((GameMenuContribution c) => c.availableIn(context))
        .toList();

    final List<CustomDrawerItem<String>> drawerItems =
        <CustomDrawerItem<String>>[
          if (!GameRegistry.instance.isPrimarySelected)
            _appItem(ShellRouteIds.appBackToMainGame, s.shellBackToMainGame),
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
              if (gameModule.buildRuleSettingsScreen(context) != null)
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
              GameRegistry.instance.isPrimarySelected &&
              GameRegistry.instance.getModule(GameId.demoProbe) != null)
            _appItem(DebugRouteIds.platformProbe, 'Tic-Tac-Toe (sample)'),
        ];

    return SharedGameShell(
      drawerController: _controller,
      drawerHeaderTitle: s.appName,
      drawerItems: drawerItems,
      mainScreen: _screenView ?? const SizedBox.shrink(),
      onWillPopStackEntry: () {
        return !_canPopRoute();
      },
      isDrawerGestureDisabled: (BuildContext ctx, CustomDrawerValue value) {
        return (!DB().displaySettings.swipeToRevealTheDrawer &&
                !value.isDrawerVisible) ||
            ((kIsWeb ||
                    Platform.isWindows ||
                    Platform.isLinux ||
                    Platform.isMacOS) &&
                _routeIsPlayModeSurface(ctx, _routeId) &&
                !value.isDrawerVisible);
      },
      doubleBackSnackBar: CustomSnackBar(s.tapBackAgainToLeave),
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
    final GameModule module = GameRegistry.instance.current;
    if (module.shouldShowRuleSettingsOnboarding(
      Localizations.localeOf(context),
    )) {
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
          _selectRoute(ShellRouteIds.appRuleSettings.value);
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
