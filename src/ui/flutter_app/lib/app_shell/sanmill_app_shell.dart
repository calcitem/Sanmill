// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:io';

import 'package:feedback/feedback.dart';
import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../experience_recording/models/recording_models.dart';
import '../experience_recording/services/recording_service.dart';
import '../game_page/services/mill.dart'
    show GameController, LoadService, PieceColor;
import '../game_page/services/save_load/saved_game_catalog.dart';
import '../game_page/widgets/mini_board.dart';
import '../game_page/widgets/saved_games_page.dart';
import '../game_platform/game_id.dart';
import '../game_platform/game_menu.dart';
import '../game_platform/game_module.dart';
import '../game_platform/game_registry.dart';
import '../game_platform/game_route_id.dart';
import '../game_platform/game_session.dart';
import '../game_platform/game_session_handle.dart';
import '../game_shell/game_session_scope.dart';
import '../game_shell/shell_route_ids.dart';
import '../games/mill/mill_session_animation_bridge.dart';
import '../games/mill/mill_session_recorder_bridge.dart';
import '../games/mill/native_mill_snapshot_board_view.dart';
import '../general_settings/models/general_settings.dart';
import '../general_settings/services/config_import_export_service.dart';
import '../generated/intl/l10n.dart';
import '../home/module_route_screens.dart';
import '../shared/config/constants.dart';
import '../shared/database/database.dart';
import '../shared/database/settings_repositories.dart';
import '../shared/database/settings_repository.dart';
import '../shared/dialogs/privacy_policy_dialog.dart';
import '../shared/services/catcher_service.dart' show generateOptionsContent;
import '../shared/services/environment_config.dart';
import '../shared/services/logger.dart';
import '../shared/themes/app_styles.dart';
import '../shared/widgets/double_back_to_close_app.dart';
import '../shared/widgets/lichess_list_section.dart';
import '../shared/widgets/snackbars/scaffold_messenger.dart';
import '../tutorial/widgets/tutorial_dialog.dart';

enum SanmillShellTab {
  home,
  puzzles,
  learn,
  watch,
  more;

  Key get key => Key('sanmill_tab_$name');

  IconData get icon {
    switch (this) {
      case SanmillShellTab.home:
        return Symbols.home_rounded;
      case SanmillShellTab.puzzles:
        return Symbols.extension_rounded;
      case SanmillShellTab.learn:
        return Symbols.school_rounded;
      case SanmillShellTab.watch:
        return Symbols.live_tv_rounded;
      case SanmillShellTab.more:
        return Symbols.menu_rounded;
    }
  }

  IconData get selectedIcon {
    return icon;
  }

  String label(S strings) {
    switch (this) {
      case SanmillShellTab.home:
        return strings.home;
      case SanmillShellTab.puzzles:
        return strings.puzzles;
      case SanmillShellTab.learn:
        return strings.learn;
      case SanmillShellTab.watch:
        return strings.watch;
      case SanmillShellTab.more:
        return strings.more;
    }
  }
}

abstract final class SanmillShellRouteIds {
  static const GameRouteId homeRoot = GameRouteId('app.tab.home');
  static const GameRouteId learnRoot = GameRouteId('app.tab.learn');
  static const GameRouteId watchRoot = GameRouteId('app.tab.watch');
  static const GameRouteId moreRoot = GameRouteId('app.tab.more');
}

GameMenuContribution? _findGameMenuContribution(
  BuildContext context,
  bool Function(GameMenuContribution contribution) test,
) {
  for (final GameMenuContribution contribution
      in GameRegistry.instance.current.drawerContributions(context)) {
    if (contribution.availableIn(context) && test(contribution)) {
      return contribution;
    }
  }
  return null;
}

class SanmillAppShell extends StatefulWidget {
  const SanmillAppShell({super.key});

  static const Key shellKey = Key('sanmill_app_shell');

  @override
  State<SanmillAppShell> createState() => SanmillAppShellState();
}

class SanmillAppShellState extends State<SanmillAppShell> {
  final Map<SanmillShellTab, GlobalKey<NavigatorState>> _navigatorKeys =
      <SanmillShellTab, GlobalKey<NavigatorState>>{
        for (final SanmillShellTab tab in SanmillShellTab.values)
          tab: GlobalKey<NavigatorState>(debugLabel: 'Sanmill ${tab.name}'),
      };
  final Map<SanmillShellTab, _SanmillTabRouteObserver> _routeObservers =
      <SanmillShellTab, _SanmillTabRouteObserver>{
        for (final SanmillShellTab tab in SanmillShellTab.values)
          tab: _SanmillTabRouteObserver(),
      };
  final Map<SanmillShellTab, ScrollController> _scrollControllers =
      <SanmillShellTab, ScrollController>{
        for (final SanmillShellTab tab in SanmillShellTab.values)
          tab: ScrollController(debugLabel: 'Sanmill ${tab.name} root'),
      };
  final Map<SanmillShellTab, _SanmillTabInteraction> _tabInteractions =
      <SanmillShellTab, _SanmillTabInteraction>{
        for (final SanmillShellTab tab in SanmillShellTab.values)
          tab: _SanmillTabInteraction(),
      };

  SanmillShellTab _currentTab = SanmillShellTab.home;
  late String _routeId;
  late String _playRouteId;
  bool _initialized = false;

  GameSessionHandle? _activeSession;
  GameId? _activeSessionGameId;
  MillSessionRecorderBridge? _activeMillRecorderBridge;
  MillSessionAnimationBridge? _activeMillAnimationBridge;
  VoidCallback? _activeSessionSnapshotListener;

  SettingsRepository get _settingsRepository =>
      SettingsRepositories.instance.current.repository;

  @visibleForTesting
  SanmillShellTab get debugCurrentTab => _currentTab;

  @visibleForTesting
  String get debugCurrentRouteId => _routeId;

  @visibleForTesting
  String get debugPlayRouteId => _playRouteId;

  @override
  void initState() {
    super.initState();
    GameRegistry.instance.addListener(_onRegistryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPrivacyDialog());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _initialized = true;
    _ensureSessionForCurrentGame();
    final GameModule module = GameRegistry.instance.current;
    _playRouteId = module.defaultShellRoute(context);
    _routeId = SanmillShellRouteIds.homeRoot.value;
    module.didNavigateShellRoute(
      context,
      previousRouteId: null,
      nextRouteId: _routeId,
    );
    firstRun(context);
  }

  @override
  void dispose() {
    GameRegistry.instance.removeListener(_onRegistryChanged);
    for (final ScrollController controller in _scrollControllers.values) {
      controller.dispose();
    }
    for (final _SanmillTabInteraction interaction in _tabInteractions.values) {
      interaction.dispose();
    }
    _disposeActiveSessionBindings();
    _activeSession?.dispose();
    _activeSession = null;
    super.dispose();
  }

  void _ensureSessionForCurrentGame() {
    final GameId currentId = GameRegistry.instance.currentId;
    if (_activeSessionGameId == currentId && _activeSession != null) {
      return;
    }
    _disposeActiveSessionBindings();
    _activeSession?.dispose();
    final GameModule? module = GameRegistry.instance.getModule(currentId);
    _activeSession = module?.startSession();
    _activeSessionGameId = currentId;
    final GameSessionHandle? session = _activeSession;
    if (session != null) {
      _bindActiveSessionSnapshot(session);
    }
    if (currentId == GameId.mill && session != null) {
      _activeMillRecorderBridge = MillSessionRecorderBridge.forGameController(
        session: session,
      );
      _activeMillAnimationBridge = MillSessionAnimationBridge(session: session);
    }
  }

  void _bindActiveSessionSnapshot(GameSession session) {
    GameController().bindActiveSession(session);
    void listener() {
      final GameController controller = GameController();
      controller.activeSessionSnapshot = session.state.value;
      controller.headerIconsNotifier.showIcons();
    }

    session.state.addListener(listener);
    _activeSessionSnapshotListener = listener;
  }

  void _disposeActiveSessionBindings() {
    final GameSessionHandle? session = _activeSession;
    final VoidCallback? listener = _activeSessionSnapshotListener;
    if (session != null && listener != null) {
      session.state.removeListener(listener);
    }
    _activeSessionSnapshotListener = null;
    if (session != null) {
      GameController().unbindActiveSession(session);
    }
    _disposeActiveMillRecorderBridge();
    _disposeActiveMillAnimationBridge();
  }

  void _disposeActiveMillRecorderBridge() {
    final MillSessionRecorderBridge? bridge = _activeMillRecorderBridge;
    if (bridge == null) {
      return;
    }
    _activeMillRecorderBridge = null;
    unawaited(bridge.dispose());
  }

  void _disposeActiveMillAnimationBridge() {
    final MillSessionAnimationBridge? bridge = _activeMillAnimationBridge;
    if (bridge == null) {
      return;
    }
    _activeMillAnimationBridge = null;
    unawaited(bridge.dispose());
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
    final GameModule module = GameRegistry.instance.current;
    final String nextRouteId = module.defaultShellRoute(context);
    _playRouteId = nextRouteId;
    _routeId = SanmillShellRouteIds.homeRoot.value;
    module.didNavigateShellRoute(
      context,
      previousRouteId: null,
      nextRouteId: _routeId,
    );
    setState(() {
      _currentTab = SanmillShellTab.home;
      _popAllTabsToRoot();
    });
  }

  Future<void> _selectTab(SanmillShellTab tab) async {
    if (tab == _currentTab) {
      await _handleRepeatedTabTap(tab);
      return;
    }

    final String nextRouteId = _rootRouteIdForTab(tab);
    if (!await _transitionToRoute(nextRouteId)) {
      return;
    }
    setState(() {
      _currentTab = tab;
    });
  }

  Future<void> _handleRepeatedTabTap(SanmillShellTab tab) async {
    final NavigatorState? navigator = _navigatorKeys[tab]?.currentState;
    if (navigator?.canPop() ?? false) {
      if (!await _transitionToRoute(_rootRouteIdForTab(tab))) {
        return;
      }
      navigator!.popUntil((Route<dynamic> route) => route.isFirst);
      return;
    }
    if (_routeId != _rootRouteIdForTab(tab)) {
      await _transitionToRoute(_rootRouteIdForTab(tab));
    }
    final ScrollController? controller = _scrollControllers[tab];
    if (controller != null && controller.hasClients && controller.offset > 0) {
      controller.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      return;
    }
    _tabInteractions[tab]?.notifyItemTapped();
  }

  Future<bool> _transitionToRoute(String nextRouteId) async {
    if (_routeId == nextRouteId) {
      return true;
    }
    final GameModule module = GameRegistry.instance.current;
    if (!await module.willNavigateToShellRoute(
      context,
      previousRouteId: _routeId,
      nextRouteId: nextRouteId,
    )) {
      return false;
    }
    if (!mounted) {
      return false;
    }
    module.didNavigateShellRoute(
      context,
      previousRouteId: _routeId,
      nextRouteId: nextRouteId,
    );
    _routeId = nextRouteId;
    RecordingService().recordEvent(
      RecordingEventType.gameModeChange,
      <String, dynamic>{'mode': nextRouteId},
    );
    return true;
  }

  Future<void> _selectPlayRoute(String routeId) async {
    if (!await _transitionToRoute(routeId)) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _playRouteId = routeId;
      _currentTab = SanmillShellTab.home;
    });
    final NavigatorState? navigator =
        _navigatorKeys[SanmillShellTab.home]?.currentState;
    navigator?.popUntil((Route<dynamic> route) => route.isFirst);
    navigator?.push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: routeId),
        builder: (_) => _buildRouteSurface(routeId),
      ),
    );
  }

  Future<void> _continueCurrentGame() async {
    await _selectPlayRoute(_playRouteId);
  }

  Future<void> _openSavedGame(String path) async {
    await LoadService.loadGame(
      context,
      path,
      isRunning: true,
      shouldPop: false,
    );
    if (!mounted) {
      return;
    }
    await _selectPlayRoute(_playRouteId);
  }

  Future<void> _openSavedGamesFromWatch() async {
    await _navigatorKeys[SanmillShellTab.watch]?.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => SavedGamesPage(onGameLoaded: _continueCurrentGame),
      ),
    );
  }

  Future<void> _pushAppRoute(String routeId) async {
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
    if (!await _transitionToRoute(routeId)) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _currentTab = SanmillShellTab.more;
    });
    _navigatorKeys[SanmillShellTab.more]?.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  Future<void> _pushWatchRoute(String routeId) async {
    final Widget? screen = buildModuleScreenForGame(
      context,
      GameRegistry.instance.currentId,
      routeId,
      session: _activeSession,
    );
    if (screen == null) {
      logger.w('No Watch screen for route $routeId.');
      return;
    }
    if (!await _transitionToRoute(routeId)) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _currentTab = SanmillShellTab.watch;
    });
    _navigatorKeys[SanmillShellTab.watch]?.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  Future<void> _pushLearnRoute(String routeId) async {
    final Widget? screen =
        buildModuleScreenForGame(
          context,
          GameRegistry.instance.currentId,
          routeId,
          session: _activeSession,
        ) ??
        buildAppShellScreen(context, routeId);
    if (screen == null) {
      logger.w('No Learn screen for route $routeId.');
      return;
    }
    if (!await _transitionToRoute(routeId)) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _currentTab = SanmillShellTab.learn;
    });
    _navigatorKeys[SanmillShellTab.learn]?.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  String _rootRouteIdForTab(SanmillShellTab tab) {
    switch (tab) {
      case SanmillShellTab.home:
        return SanmillShellRouteIds.homeRoot.value;
      case SanmillShellTab.puzzles:
        return _puzzlesContribution(context)?.id.value ??
            SanmillShellRouteIds.moreRoot.value;
      case SanmillShellTab.learn:
        return SanmillShellRouteIds.learnRoot.value;
      case SanmillShellTab.watch:
        return SanmillShellRouteIds.watchRoot.value;
      case SanmillShellTab.more:
        return SanmillShellRouteIds.moreRoot.value;
    }
  }

  GameMenuContribution? _puzzlesContribution(BuildContext context) {
    return _targetedContribution(context, GameMenuTarget.puzzles);
  }

  GameMenuContribution? _statisticsContribution(BuildContext context) {
    return _targetedContribution(context, GameMenuTarget.watch);
  }

  GameMenuContribution? _targetedContribution(
    BuildContext context,
    GameMenuTarget target, [
    bool Function(GameMenuContribution contribution)? test,
  ]) {
    return _findGameMenuContribution(
      context,
      (GameMenuContribution contribution) =>
          contribution.targets.contains(target) &&
          (test?.call(contribution) ?? true),
    );
  }

  List<GameMenuContribution> _targetedContributions(
    BuildContext context,
    GameMenuTarget target,
  ) {
    return GameRegistry.instance.current
        .drawerContributions(context)
        .where(
          (GameMenuContribution contribution) =>
              contribution.availableIn(context) &&
              contribution.targets.contains(target),
        )
        .toList(growable: false);
  }

  Widget _buildRouteSurface(String routeId) {
    return buildModuleScreenForGame(
          context,
          GameRegistry.instance.currentId,
          routeId,
          session: _activeSession,
        ) ??
        buildAppShellScreen(context, routeId) ??
        _UnavailableTabPage(label: routeId);
  }

  Widget _buildScrollableRouteSurface(SanmillShellTab tab, String routeId) {
    final ScrollController? controller = _scrollControllers[tab];
    assert(controller != null, 'Missing root scroll controller for $tab.');
    return PrimaryScrollController(
      controller: controller!,
      child: _buildRouteSurface(routeId),
    );
  }

  Widget _buildTabRoot(SanmillShellTab tab) {
    switch (tab) {
      case SanmillShellTab.home:
        return _HomeTabRoot(
          scrollController: _scrollControllers[SanmillShellTab.home]!,
          tabInteraction: _tabInteractions[SanmillShellTab.home]!,
          isActive: _currentTab == SanmillShellTab.home,
          currentPlayRouteId: _playRouteId,
          onContinueGame: _continueCurrentGame,
          onPlayRouteSelected: _selectPlayRoute,
          onSavedGameSelected: _openSavedGame,
        );
      case SanmillShellTab.puzzles:
        final GameMenuContribution? contribution = _puzzlesContribution(
          context,
        );
        return contribution == null
            ? _UnavailableTabPage(label: S.of(context).puzzles)
            : _buildScrollableRouteSurface(tab, contribution.id.value);
      case SanmillShellTab.learn:
        return _LearnTabRoot(
          scrollController: _scrollControllers[SanmillShellTab.learn]!,
          studyTools: _targetedContributions(context, GameMenuTarget.learn),
          onLearnRouteSelected: _pushLearnRoute,
        );
      case SanmillShellTab.watch:
        return _WatchTabRoot(
          scrollController: _scrollControllers[SanmillShellTab.watch]!,
          statisticsContribution: _statisticsContribution(context),
          onLoadGame: _openSavedGamesFromWatch,
          onWatchRouteSelected: _pushWatchRoute,
        );
      case SanmillShellTab.more:
        return _MoreTabRoot(
          scrollController: _scrollControllers[SanmillShellTab.more]!,
          onAppRouteSelected: _pushAppRoute,
          onFeedback: _showFeedback,
          onExit: _exitApp,
        );
    }
  }

  Widget _buildTabNavigator(SanmillShellTab tab) {
    return Navigator(
      key: _navigatorKeys[tab],
      observers: <NavigatorObserver>[_routeObservers[tab]!],
      onGenerateRoute: (RouteSettings settings) {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => _buildTabRoot(tab),
        );
      },
    );
  }

  void _popAllTabsToRoot() {
    for (final GlobalKey<NavigatorState> key in _navigatorKeys.values) {
      key.currentState?.popUntil((Route<dynamic> route) => route.isFirst);
    }
  }

  Future<bool> _handleBack() async {
    final NavigatorState? navigator = _navigatorKeys[_currentTab]?.currentState;
    if (navigator?.canPop() ?? false) {
      final Route<dynamic>? topRoute = _routeObservers[_currentTab]?.topRoute;
      if (topRoute is! PageRoute<dynamic>) {
        navigator!.pop();
        return false;
      }
      final String nextRouteId = _rootRouteIdForTab(_currentTab);
      if (!await _transitionToRoute(nextRouteId)) {
        return false;
      }
      if (!mounted) {
        return false;
      }
      navigator!.pop();
      setState(() {});
      return false;
    }
    if (_currentTab != SanmillShellTab.home) {
      if (!await _transitionToRoute(SanmillShellRouteIds.homeRoot.value)) {
        return false;
      }
      if (!mounted) {
        return false;
      }
      setState(() {
        _currentTab = SanmillShellTab.home;
      });
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GameRegistry.instance,
      builder: (BuildContext context, Widget? _) {
        _ensureSessionForCurrentGame();
        GameRegistry.instance.current.applyShellLayoutHints(context);
        final GameSession? session = _activeSession;
        final Widget shell = _buildResponsiveShell(context);
        if (session != null) {
          return GameSessionScope(session: session, child: shell);
        }
        return shell;
      },
    );
  }

  Widget _buildResponsiveShell(BuildContext context) {
    final S strings = S.of(context);
    final bool showBottomNavigationBar = !_isImmersivePlayRoute(context);
    final Widget content = DoubleBackToCloseApp(
      snackBar: CustomSnackBar(strings.tapBackAgainToLeave),
      willBack: _handleBack,
      child: Scaffold(
        key: SanmillAppShell.shellKey,
        body: _SanmillTabSwitchingView(
          key: const Key('sanmill_tab_indexed_stack'),
          currentTab: _currentTab,
          tabBuilder: (BuildContext context, SanmillShellTab tab) =>
              _buildTabNavigator(tab),
        ),
        bottomNavigationBar: showBottomNavigationBar
            ? NavigationBar(
                key: const Key('sanmill_bottom_navigation_bar'),
                selectedIndex: _currentTab.index,
                destinations: <NavigationDestination>[
                  for (final SanmillShellTab tab in SanmillShellTab.values)
                    NavigationDestination(
                      key: tab.key,
                      icon: Icon(tab.icon, fill: 0),
                      selectedIcon: Icon(tab.selectedIcon, fill: 1),
                      label: tab.label(strings),
                    ),
                ],
                onDestinationSelected: (int index) =>
                    _selectTab(SanmillShellTab.values[index]),
              )
            : null,
      ),
    );

    return content;
  }

  bool _isImmersivePlayRoute(BuildContext context) {
    if (_currentTab != SanmillShellTab.home || _routeId != _playRouteId) {
      return false;
    }
    return GameRegistry.instance.current
        .playModes(context)
        .any(
          (GameModeEntry mode) =>
              mode.section == GameMenuSection.play && mode.id.value == _routeId,
        );
  }

  void firstRun(BuildContext context) {
    if (_settingsRepository.generalSettings.firstRun != true) {
      return;
    }
    _settingsRepository.generalSettings = _settingsRepository.generalSettings
        .copyWith(firstRun: false);
    GameRegistry.instance.current.applyFirstRunDefaults(context);
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
            PrivacyPolicyDialog(onConfirm: _showFirstRunGuidance),
      );
    } else {
      _showFirstRunGuidance();
    }
  }

  void _showFirstRunGuidance() {
    if (!kDebugMode && DB().generalSettings.showTutorial) {
      DB().generalSettings = DB().generalSettings.copyWith(showTutorial: false);
    }
    _showRuleSettingsOnboarding();
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
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(S.of(context).no),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(S.of(context).yes),
              ),
            ],
          );
        },
      ).then((bool? result) {
        if (result ?? false) {
          _pushAppRoute(ShellRouteIds.appRuleSettings.value);
        }
      });
    }
  }

  void _showFeedback() {
    if (EnvironmentConfig.test == true) {
      return;
    }
    if (!kIsWeb && Platform.isAndroid) {
      BetterFeedback.of(context).show(_launchFeedback);
    } else {
      logger.w('flutter_email_sender does not support this platform.');
    }
  }

  void _exitApp() {
    if (EnvironmentConfig.test == false && !kIsWeb) {
      SystemChannels.platform.invokeMethod<void>('SystemNavigator.pop');
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

typedef _SanmillTabBuilder =
    Widget Function(BuildContext context, SanmillShellTab tab);

class _SanmillTabRouteObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = <Route<dynamic>>[];

  Route<dynamic>? get topRoute => _stack.isEmpty ? null : _stack.last;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final bool removed = _stack.remove(route);
    assert(removed, 'Popped route was not tracked by the tab route observer.');
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final bool removed = _stack.remove(route);
    assert(removed, 'Removed route was not tracked by the tab route observer.');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute == null) {
      assert(newRoute != null, 'Route replacement must provide a new route.');
      _stack.add(newRoute!);
      return;
    }
    final int index = _stack.indexOf(oldRoute);
    assert(index != -1, 'Replaced route was not tracked by the tab observer.');
    if (newRoute == null) {
      _stack.removeAt(index);
      return;
    }
    _stack[index] = newRoute;
  }
}

class _SanmillTabInteraction extends ChangeNotifier {
  void notifyItemTapped() {
    notifyListeners();
  }
}

class _SanmillTabSwitchingView extends StatefulWidget {
  const _SanmillTabSwitchingView({
    super.key,
    required this.currentTab,
    required this.tabBuilder,
  });

  final SanmillShellTab currentTab;
  final _SanmillTabBuilder tabBuilder;

  @override
  State<_SanmillTabSwitchingView> createState() =>
      _SanmillTabSwitchingViewState();
}

class _SanmillTabSwitchingViewState extends State<_SanmillTabSwitchingView> {
  final Set<SanmillShellTab> _builtTabs = <SanmillShellTab>{};
  final Map<SanmillShellTab, FocusScopeNode> _tabFocusNodes =
      <SanmillShellTab, FocusScopeNode>{
        for (final SanmillShellTab tab in SanmillShellTab.values)
          tab: FocusScopeNode(debugLabel: 'Sanmill ${tab.name} tab focus'),
      };

  @override
  void initState() {
    super.initState();
    _builtTabs.add(widget.currentTab);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _focusActiveTab();
  }

  @override
  void didUpdateWidget(covariant _SanmillTabSwitchingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _builtTabs.add(widget.currentTab);
    _focusActiveTab();
  }

  @override
  void dispose() {
    for (final FocusScopeNode node in _tabFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _focusActiveTab() {
    final FocusScopeNode? node = _tabFocusNodes[widget.currentTab];
    assert(node != null, 'Missing focus node for ${widget.currentTab}.');
    FocusScope.of(context).setFirstFocus(node!);
  }

  @override
  Widget build(BuildContext context) {
    _builtTabs.add(widget.currentTab);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        for (final SanmillShellTab tab in SanmillShellTab.values)
          if (_builtTabs.contains(tab))
            HeroMode(
              enabled: tab == widget.currentTab,
              child: _TabVisibility(
                active: tab == widget.currentTab,
                child: FocusScope(
                  key: Key('sanmill_tab_focus_${tab.name}'),
                  node: _tabFocusNodes[tab],
                  child: widget.tabBuilder(context, tab),
                ),
              ),
            ),
      ],
    );
  }
}

class _TabVisibility extends StatelessWidget {
  const _TabVisibility({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Offstage(
      offstage: !active,
      child: TickerMode(enabled: active, child: child),
    );
  }
}

class _HomeTabRoot extends StatefulWidget {
  const _HomeTabRoot({
    required this.scrollController,
    required this.tabInteraction,
    required this.isActive,
    required this.currentPlayRouteId,
    required this.onContinueGame,
    required this.onPlayRouteSelected,
    required this.onSavedGameSelected,
  });

  final ScrollController scrollController;
  final Listenable tabInteraction;
  final bool isActive;
  final String currentPlayRouteId;
  final VoidCallback onContinueGame;
  final ValueChanged<String> onPlayRouteSelected;
  final ValueChanged<String> onSavedGameSelected;

  @override
  State<_HomeTabRoot> createState() => _HomeTabRootState();
}

class _HomeTabRootState extends State<_HomeTabRoot> {
  static const int _recentGamesLimit = 5;
  static const int _savedGamesQueryLimit = (_recentGamesLimit + 1) * 4;

  late Future<List<SavedGameSummary>> _recentGamesFuture;

  @override
  void initState() {
    super.initState();
    _recentGamesFuture = _loadRecentGames();
  }

  @override
  void didUpdateWidget(covariant _HomeTabRoot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      unawaited(_refreshRecentGames());
    }
  }

  Future<List<SavedGameSummary>> _loadRecentGames() {
    return savedGameCatalog.listRecent(
      limit: _savedGamesQueryLimit,
      includePreviews: true,
    );
  }

  Future<void> _refreshRecentGames() async {
    final Future<List<SavedGameSummary>> nextRecentGames = _loadRecentGames();
    setState(() {
      _recentGamesFuture = nextRecentGames;
    });
    await nextRecentGames;
  }

  Future<void> _openSavedGamesPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SavedGamesPage(onGameLoaded: widget.onContinueGame),
      ),
    );
    if (mounted) {
      await _refreshRecentGames();
    }
  }

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final GameModule module = GameRegistry.instance.current;
    final bool useWideHomeLayout = MediaQuery.sizeOf(context).width >= 720;
    final List<GameModeEntry> playModes = module
        .playModes(context)
        .where(
          (GameModeEntry mode) =>
              mode.section == GameMenuSection.play && mode.availableIn(context),
        )
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          strings.appName,
          key: const Key('sanmill_home_appbar_title'),
        ),
      ),
      body: RefreshIndicator.adaptive(
        onRefresh: _refreshRecentGames,
        child: ListTileTheme.merge(
          iconColor: Theme.of(context).colorScheme.primary,
          child: ListView(
            key: const Key('sanmill_home_list'),
            controller: widget.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 16, bottom: 24),
            children: _buildHomeContent(context, playModes, useWideHomeLayout),
          ),
        ),
      ),
      floatingActionButton: playModes.isEmpty
          ? null
          : _FloatingPlayButton(
              onPressed: () => _showPlayBottomSheet(context, playModes),
            ),
    );
  }

  List<Widget> _buildHomeContent(
    BuildContext context,
    List<GameModeEntry> playModes,
    bool useWideHomeLayout,
  ) {
    return <Widget>[
      _HomeGamesOverview(
        currentPlayRouteId: widget.currentPlayRouteId,
        playModes: playModes,
        future: _recentGamesFuture,
        limit: _recentGamesLimit,
        useWideLayout: useWideHomeLayout,
        tabInteraction: widget.tabInteraction,
        onContinueGame: widget.onContinueGame,
        onShowAll: _openSavedGamesPage,
        onSavedGameSelected: widget.onSavedGameSelected,
      ),
    ];
  }

  void _showPlayBottomSheet(
    BuildContext context,
    List<GameModeEntry> playModes,
  ) {
    assert(playModes.isNotEmpty, 'Play bottom sheet requires play modes.');
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return _PlayBottomSheet(
          playModes: playModes,
          onPlayRouteSelected: widget.onPlayRouteSelected,
        );
      },
    );
  }
}

class _HomeGamesOverview extends StatelessWidget {
  const _HomeGamesOverview({
    required this.currentPlayRouteId,
    required this.playModes,
    required this.future,
    required this.limit,
    required this.useWideLayout,
    required this.tabInteraction,
    required this.onContinueGame,
    required this.onShowAll,
    required this.onSavedGameSelected,
  });

  final String currentPlayRouteId;
  final List<GameModeEntry> playModes;
  final Future<List<SavedGameSummary>> future;
  final int limit;
  final bool useWideLayout;
  final Listenable tabInteraction;
  final VoidCallback onContinueGame;
  final VoidCallback onShowAll;
  final ValueChanged<String> onSavedGameSelected;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: GameController().gameRecorder.moveCountNotifier,
      builder: (BuildContext context, int moveCount, _) {
        final _ActiveGamePreview? activeGame = _activeGamePreview(
          context,
          moveCount,
        );
        return FutureBuilder<List<SavedGameSummary>>(
          future: future,
          builder:
              (
                BuildContext context,
                AsyncSnapshot<List<SavedGameSummary>> snapshot,
              ) {
                final List<SavedGameSummary> homeGames =
                    snapshot.data ?? const <SavedGameSummary>[];
                final List<SavedGameSummary> ongoingGames = homeGames
                    .where((SavedGameSummary game) => game.isOngoing)
                    .toList(growable: false);
                final List<SavedGameSummary> recentGames = homeGames
                    .where((SavedGameSummary game) => !game.isOngoing)
                    .toList(growable: false);
                if (activeGame == null &&
                    ongoingGames.isEmpty &&
                    recentGames.isEmpty) {
                  return const SizedBox.shrink();
                }

                final bool useCarousel = !useWideLayout;
                final Widget ongoingSection = _HomeOngoingGames(
                  activeGame: activeGame,
                  savedGames: ongoingGames,
                  limit: limit,
                  useCarousel: useCarousel,
                  tabInteraction: tabInteraction,
                  onShowAll: onShowAll,
                  onContinueGame: onContinueGame,
                  onSavedGameSelected: onSavedGameSelected,
                );
                final Widget recentSection = _SavedGamePreviewSection(
                  title: S.of(context).recentGames,
                  headerKey: const Key('sanmill_home_recent_games_group'),
                  gameKeyPrefix: 'sanmill_home_recent_game',
                  games: recentGames,
                  limit: limit,
                  useCarousel: useCarousel,
                  tabInteraction: tabInteraction,
                  fallbackIcon: Icons.history_rounded,
                  onShowAll: onShowAll,
                  onSavedGameSelected: onSavedGameSelected,
                  detailForGame: _SavedGamePreviewSection.players,
                );

                if (!useWideLayout) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[ongoingSection, recentSection],
                  );
                }

                return Row(
                  key: const Key('sanmill_home_wide_content'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: ongoingSection),
                    Expanded(child: recentSection),
                  ],
                );
              },
        );
      },
    );
  }

  _ActiveGamePreview? _activeGamePreview(BuildContext context, int moveCount) {
    final GameStateSnapshot? snapshot = GameController().activeSessionSnapshot;
    final bool isTerminal = snapshot?.outcome.isTerminal ?? false;
    if (moveCount == 0 || isTerminal) {
      return null;
    }

    GameModeEntry? mode;
    for (final GameModeEntry entry in playModes) {
      if (entry.id.value == currentPlayRouteId) {
        mode = entry;
        break;
      }
    }

    final S strings = S.of(context);
    return _ActiveGamePreview(
      boardLayout: _ActiveGamePreview.boardLayoutFromSnapshot(snapshot),
      title: mode?.label ?? strings.game,
      subtitle: _ActiveGamePreview.subtitleFromSnapshot(
        strings,
        snapshot,
        moveCount,
      ),
    );
  }
}

typedef _SavedGameDetailBuilder = String? Function(SavedGameSummary game);

class _ActiveGamePreview {
  const _ActiveGamePreview({
    required this.boardLayout,
    required this.title,
    required this.subtitle,
  });

  final String? boardLayout;
  final String title;
  final String subtitle;

  static String? boardLayoutFromSnapshot(GameStateSnapshot? snapshot) {
    if (snapshot == null) {
      return null;
    }
    return NativeMillSnapshotBoardView.fromSnapshot(snapshot)?.toBoardLayout();
  }

  static String subtitleFromSnapshot(
    S strings,
    GameStateSnapshot? snapshot,
    int moveCount,
  ) {
    final List<String> parts = <String>['${strings.moves}: $moveCount'];
    final String? sideToMove = _sideToMove(strings, snapshot);
    if (sideToMove != null) {
      parts.add(strings.sideToMove(sideToMove));
    }
    return parts.join(' · ');
  }

  static String? _sideToMove(S strings, GameStateSnapshot? snapshot) {
    return switch (snapshot?.activeSeat) {
      PlayerSeat.first => strings.player1,
      PlayerSeat.second => strings.player2,
      PlayerSeat.none || null => null,
    };
  }
}

class _HomeOngoingGames extends StatelessWidget {
  const _HomeOngoingGames({
    required this.activeGame,
    required this.savedGames,
    required this.limit,
    required this.useCarousel,
    required this.tabInteraction,
    required this.onShowAll,
    required this.onContinueGame,
    required this.onSavedGameSelected,
  }) : assert(limit > 0, 'Ongoing games section limit must be positive.');

  final _ActiveGamePreview? activeGame;
  final List<SavedGameSummary> savedGames;
  final int limit;
  final bool useCarousel;
  final Listenable tabInteraction;
  final VoidCallback onShowAll;
  final VoidCallback onContinueGame;
  final ValueChanged<String> onSavedGameSelected;

  @override
  Widget build(BuildContext context) {
    if (activeGame == null && savedGames.isEmpty) {
      return const SizedBox.shrink();
    }

    final S strings = S.of(context);
    final int savedLimit = activeGame == null ? limit : limit - 1;
    final Iterable<(int, SavedGameSummary)> visibleSavedGames = savedGames
        .take(savedLimit)
        .indexed;
    final bool hasMore = savedGames.length > savedLimit;

    if (useCarousel) {
      return _HomeGameCarouselSection(
        title: strings.ongoingGames,
        headerKey: const Key('sanmill_home_ongoing_game_group'),
        listKey: const Key('sanmill_home_ongoing_game_card'),
        tabInteraction: tabInteraction,
        onHeaderTap: hasMore ? onShowAll : null,
        children: <Widget>[
          if (activeGame != null)
            _GamePreviewCarouselCard(
              key: const Key('sanmill_home_ongoing_game'),
              boardLayout: activeGame!.boardLayout,
              fallbackIcon: Icons.play_circle_outline_rounded,
              title: activeGame!.title,
              subtitle: activeGame!.subtitle,
              detail: strings.continueGame,
              onTap: onContinueGame,
            ),
          for (final (int index, SavedGameSummary game) in visibleSavedGames)
            _GamePreviewCarouselCard(
              key: Key('sanmill_home_saved_ongoing_game_$index'),
              boardLayout: game.preview?.boardLayout,
              fallbackIcon: Icons.play_circle_outline_rounded,
              title: game.displayName,
              subtitle: _SavedGamePreviewSection.subtitleForGame(
                MaterialLocalizations.of(context),
                strings,
                game,
              ),
              detail: strings.continueGame,
              onTap: () => onSavedGameSelected(game.path),
            ),
        ],
      );
    }

    return _MoreSection(
      title: strings.ongoingGames,
      headerKey: const Key('sanmill_home_ongoing_game_group'),
      onHeaderTap: hasMore ? onShowAll : null,
      children: <Widget>[
        if (activeGame != null)
          _GamePreviewTile(
            key: const Key('sanmill_home_ongoing_game'),
            boardLayout: activeGame!.boardLayout,
            fallbackIcon: Icons.play_circle_outline_rounded,
            title: activeGame!.title,
            subtitle: activeGame!.subtitle,
            detail: strings.continueGame,
            onTap: onContinueGame,
          ),
        for (final (int index, SavedGameSummary game) in visibleSavedGames)
          _GamePreviewTile(
            key: Key('sanmill_home_saved_ongoing_game_$index'),
            boardLayout: game.preview?.boardLayout,
            fallbackIcon: Icons.play_circle_outline_rounded,
            title: game.displayName,
            subtitle: _SavedGamePreviewSection.subtitleForGame(
              MaterialLocalizations.of(context),
              strings,
              game,
            ),
            detail: strings.continueGame,
            onTap: () => onSavedGameSelected(game.path),
          ),
      ],
    );
  }
}

class _SavedGamePreviewSection extends StatelessWidget {
  const _SavedGamePreviewSection({
    required this.title,
    required this.headerKey,
    required this.gameKeyPrefix,
    required this.games,
    required this.limit,
    required this.useCarousel,
    required this.tabInteraction,
    required this.fallbackIcon,
    required this.onShowAll,
    required this.onSavedGameSelected,
    required this.detailForGame,
  }) : assert(limit > 0, 'Recent games section limit must be positive.');

  final String title;
  final Key headerKey;
  final String gameKeyPrefix;
  final List<SavedGameSummary> games;
  final int limit;
  final bool useCarousel;
  final Listenable tabInteraction;
  final IconData fallbackIcon;
  final VoidCallback onShowAll;
  final ValueChanged<String> onSavedGameSelected;
  final _SavedGameDetailBuilder detailForGame;

  @override
  Widget build(BuildContext context) {
    if (games.isEmpty) {
      return const SizedBox.shrink();
    }
    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );
    final S strings = S.of(context);
    final bool hasMore = games.length > limit;
    final Iterable<(int, SavedGameSummary)> visibleGames = games
        .take(limit)
        .indexed;
    if (useCarousel) {
      return _HomeGameCarouselSection(
        title: title,
        headerKey: headerKey,
        tabInteraction: tabInteraction,
        onHeaderTap: hasMore ? onShowAll : null,
        children: <Widget>[
          for (final (int index, SavedGameSummary game) in visibleGames)
            _GamePreviewCarouselCard(
              key: Key('${gameKeyPrefix}_$index'),
              boardLayout: game.preview?.boardLayout,
              fallbackIcon: fallbackIcon,
              title: game.displayName,
              subtitle: subtitleForGame(localizations, strings, game),
              detail: detailForGame(game),
              onTap: () => onSavedGameSelected(game.path),
            ),
        ],
      );
    }

    return _MoreSection(
      title: title,
      headerKey: headerKey,
      onHeaderTap: hasMore ? onShowAll : null,
      children: <Widget>[
        for (final (int index, SavedGameSummary game) in visibleGames)
          _GamePreviewTile(
            key: Key('${gameKeyPrefix}_$index'),
            boardLayout: game.preview?.boardLayout,
            fallbackIcon: fallbackIcon,
            title: game.displayName,
            subtitle: subtitleForGame(localizations, strings, game),
            detail: detailForGame(game),
            onTap: () => onSavedGameSelected(game.path),
          ),
      ],
    );
  }

  static String subtitleForGame(
    MaterialLocalizations localizations,
    S strings,
    SavedGameSummary game,
  ) {
    final DateTime modified = game.modified.toLocal();
    final String modifiedAt =
        '${localizations.formatShortDate(modified)} '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(modified))}';
    final List<String> parts = <String>[modifiedAt];
    final SavedGamePreview? preview = game.preview;
    if (preview != null && preview.moveCount > 0) {
      parts.add('${strings.moves}: ${preview.moveCount}');
    }
    final String? sideToMove = _sideToMove(strings, preview);
    if (sideToMove != null) {
      parts.add(sideToMove);
    }
    final String? result = preview?.result;
    if (result != null && result != '*') {
      parts.add(result);
    }
    return parts.join(' · ');
  }

  static String? _sideToMove(S strings, SavedGamePreview? preview) {
    if (preview == null || !preview.isOngoing) {
      return null;
    }
    final String? player = switch (preview.sideToMove) {
      PieceColor.white => strings.player1,
      PieceColor.black => strings.player2,
      _ => null,
    };
    return player == null ? null : strings.sideToMove(player);
  }

  static String? players(SavedGameSummary game) {
    final String? white = game.preview?.white;
    final String? black = game.preview?.black;
    if (white != null && black != null) {
      return '$white - $black';
    }
    return white ?? black;
  }
}

class _HomeGameCarouselSection extends StatefulWidget {
  const _HomeGameCarouselSection({
    required this.title,
    required this.children,
    required this.tabInteraction,
    this.headerKey,
    this.listKey,
    this.onHeaderTap,
  });

  final String title;
  final List<Widget> children;
  final Listenable tabInteraction;
  final Key? headerKey;
  final Key? listKey;
  final VoidCallback? onHeaderTap;

  @override
  State<_HomeGameCarouselSection> createState() =>
      _HomeGameCarouselSectionState();
}

class _HomeGameCarouselSectionState extends State<_HomeGameCarouselSection> {
  static const List<int> _flexWeights = <int>[6, 2];
  static const EdgeInsets _carouselPadding = EdgeInsets.symmetric(
    horizontal: 8,
  );

  final CarouselController _controller = CarouselController();

  @override
  void initState() {
    super.initState();
    widget.tabInteraction.addListener(_handleTabInteraction);
  }

  @override
  void didUpdateWidget(covariant _HomeGameCarouselSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.tabInteraction, oldWidget.tabInteraction)) {
      oldWidget.tabInteraction.removeListener(_handleTabInteraction);
      widget.tabInteraction.addListener(_handleTabInteraction);
    }
  }

  @override
  void dispose() {
    widget.tabInteraction.removeListener(_handleTabInteraction);
    _controller.dispose();
    super.dispose();
  }

  void _handleTabInteraction() {
    if (!_controller.hasClients || _controller.offset <= 0) {
      return;
    }
    _controller.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double cardSize = (constraints.maxWidth * 0.72).clamp(
          220.0,
          300.0,
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: AppStyles.bodyPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                key: widget.headerKey,
                padding: const EdgeInsets.fromLTRB(
                  AppStyles.bodyPadding,
                  0,
                  AppStyles.bodyPadding,
                  8,
                ),
                child: DefaultTextStyle.merge(
                  style: AppStyles.sectionTitle.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  child: widget.onHeaderTap == null
                      ? Text(widget.title)
                      : _MoreSectionHeaderLink(
                          title: widget.title,
                          onTap: widget.onHeaderTap!,
                        ),
                ),
              ),
              SizedBox(
                key: widget.listKey,
                height: cardSize,
                child: CarouselView.weighted(
                  controller: _controller,
                  padding: _carouselPadding,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppStyles.compactRadius,
                    ),
                  ),
                  elevation: Theme.of(context).platform == TargetPlatform.iOS
                      ? 0
                      : 1,
                  flexWeights: _flexWeights,
                  itemSnapping: true,
                  children: widget.children,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GamePreviewCarouselCard extends StatelessWidget {
  const _GamePreviewCarouselCard({
    super.key,
    required this.boardLayout,
    required this.fallbackIcon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.detail,
  });

  final String? boardLayout;
  final IconData fallbackIcon;
  final String title;
  final String subtitle;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppStyles.compactRadius),
      ),
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _BoardPreviewSurface(
              layout: boardLayout,
              fallbackIcon: fallbackIcon,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.72),
                  ],
                  stops: const <double>[0.48, 1],
                ),
              ),
            ),
            PositionedDirectional(
              start: 12,
              end: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.86),
                      letterSpacing: 0,
                    ),
                  ),
                  if (detail != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GamePreviewTile extends StatelessWidget {
  const _GamePreviewTile({
    super.key,
    required this.boardLayout,
    required this.fallbackIcon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.detail,
  });

  final String? boardLayout;
  final IconData fallbackIcon;
  final String title;
  final String subtitle;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            _BoardPreview(layout: boardLayout, fallbackIcon: fallbackIcon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0,
                    ),
                  ),
                  if (detail != null) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardPreview extends StatelessWidget {
  const _BoardPreview({required this.layout, required this.fallbackIcon});

  final String? layout;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 92,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppStyles.compactRadius),
        child: _BoardPreviewSurface(layout: layout, fallbackIcon: fallbackIcon),
      ),
    );
  }
}

class _BoardPreviewSurface extends StatelessWidget {
  const _BoardPreviewSurface({
    required this.layout,
    required this.fallbackIcon,
  });

  final String? layout;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final String? boardLayout = layout;
    if (boardLayout == null || boardLayout.isEmpty) {
      return ColoredBox(
        color: colorScheme.surfaceContainerHighest,
        child: Icon(fallbackIcon, color: colorScheme.onSurfaceVariant),
      );
    }
    return IgnorePointer(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox.square(
          dimension: 320,
          child: MiniBoard(boardLayout: boardLayout),
        ),
      ),
    );
  }
}

class _FloatingPlayButton extends StatelessWidget {
  const _FloatingPlayButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      key: const Key('sanmill_home_play_fab'),
      onPressed: onPressed,
      tooltip: S.of(context).play,
      icon: const Icon(Icons.sports_esports_rounded),
      label: Text(S.of(context).play),
    );
  }
}

class _PlayBottomSheet extends StatelessWidget {
  const _PlayBottomSheet({
    required this.playModes,
    required this.onPlayRouteSelected,
  });

  final List<GameModeEntry> playModes;
  final ValueChanged<String> onPlayRouteSelected;

  @override
  Widget build(BuildContext context) {
    assert(playModes.isNotEmpty, 'Play bottom sheet requires play modes.');
    final S strings = S.of(context);
    final List<GameModeEntry> quickStartModes = _quickStartModes(playModes);
    final Set<String> quickStartIds = quickStartModes
        .map((GameModeEntry mode) => mode.id.value)
        .toSet();
    final List<GameModeEntry> moreModes = playModes
        .where((GameModeEntry mode) => !quickStartIds.contains(mode.id.value))
        .toList(growable: false);

    return SingleChildScrollView(
      key: const Key('sanmill_home_play_sheet'),
      padding: EdgeInsets.fromLTRB(
        0,
        16,
        0,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          LichessListSection(
            header: Text(strings.play),
            headerKey: const Key('sanmill_home_play_sheet_quick_start_group'),
            cardKey: const Key('sanmill_home_play_sheet_card'),
            children: <Widget>[
              for (final GameModeEntry mode in quickStartModes)
                _buildModeTile(context, mode),
            ],
          ),
          LichessListSection(
            header: Text(strings.more),
            headerKey: const Key('sanmill_home_play_sheet_more_modes_group'),
            cardKey: const Key('sanmill_home_play_sheet_more_modes_card'),
            children: <Widget>[
              for (final GameModeEntry mode in moreModes)
                _buildModeTile(context, mode),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeTile(BuildContext context, GameModeEntry mode) {
    return _MoreTile(
      key: Key('sanmill_home_play_sheet_${mode.id.value}'),
      icon: mode.icon ?? Icons.sports_esports_rounded,
      title: mode.label,
      onTap: () {
        Navigator.of(context).pop();
        onPlayRouteSelected(mode.id.value);
      },
    );
  }

  static List<GameModeEntry> _quickStartModes(List<GameModeEntry> modes) {
    final List<GameModeEntry> quickModes = modes
        .where(_isQuickStartMode)
        .toList(growable: false);
    if (quickModes.isNotEmpty) {
      return quickModes;
    }
    return modes.take(2).toList(growable: false);
  }

  static bool _isQuickStartMode(GameModeEntry mode) {
    final String id = mode.id.value.toLowerCase();
    return id.contains('humanvsai') || id.contains('humanvshuman');
  }
}

class _LearnTabRoot extends StatelessWidget {
  const _LearnTabRoot({
    required this.scrollController,
    required this.studyTools,
    required this.onLearnRouteSelected,
  });

  final ScrollController scrollController;
  final List<GameMenuContribution> studyTools;
  final ValueChanged<String> onLearnRouteSelected;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(strings.learn)),
      body: ListTileTheme.merge(
        iconColor: Theme.of(context).colorScheme.primary,
        child: ListView(
          key: const Key('sanmill_learn_list'),
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: <Widget>[
            _MoreSection(
              title: strings.learn,
              headerKey: const Key('sanmill_learn_guides_group'),
              children: <Widget>[
                if (GameRegistry.instance.current.metadata.id == GameId.mill)
                  _MoreTile(
                    key: const Key('sanmill_learn_coordinate_training'),
                    icon: Symbols.where_to_vote,
                    title: strings.coordinateTraining,
                    onTap: () => onLearnRouteSelected(
                      ShellRouteIds.appCoordinateTraining.value,
                    ),
                  ),
                _MoreTile(
                  key: const Key('sanmill_learn_tutorial'),
                  icon: Icons.tips_and_updates_rounded,
                  title: strings.tutorial,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      fullscreenDialog: true,
                      builder: (_) => const TutorialDialog(),
                    ),
                  ),
                ),
                _MoreTile(
                  key: const Key('sanmill_learn_how_to_play'),
                  icon: Icons.school_rounded,
                  title: strings.howToPlay,
                  onTap: () =>
                      onLearnRouteSelected(ShellRouteIds.appHowToPlay.value),
                ),
              ],
            ),
            _MoreSection(
              title: strings.tools,
              headerKey: const Key('sanmill_learn_tools_group'),
              children: <Widget>[
                for (final GameMenuContribution tool in studyTools)
                  _MoreTile(
                    key: Key('sanmill_learn_${tool.id.value}'),
                    icon: tool.icon ?? Icons.auto_stories_rounded,
                    title: tool.label,
                    onTap: () => onLearnRouteSelected(tool.id.value),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WatchTabRoot extends StatelessWidget {
  const _WatchTabRoot({
    required this.scrollController,
    required this.statisticsContribution,
    required this.onLoadGame,
    required this.onWatchRouteSelected,
  });

  final ScrollController scrollController;
  final GameMenuContribution? statisticsContribution;
  final VoidCallback onLoadGame;
  final ValueChanged<String> onWatchRouteSelected;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final GameMenuContribution? contribution = statisticsContribution;

    return Scaffold(
      appBar: AppBar(title: Text(strings.watch)),
      body: ListTileTheme.merge(
        iconColor: Theme.of(context).colorScheme.primary,
        child: ListView(
          key: const Key('sanmill_watch_list'),
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: <Widget>[
            _MoreSection(
              title: strings.replay,
              headerKey: const Key('sanmill_watch_replay_group'),
              children: <Widget>[
                _MoreTile(
                  key: const Key('sanmill_watch_load_game'),
                  icon: Icons.folder_open_rounded,
                  title: strings.loadGame,
                  onTap: onLoadGame,
                ),
              ],
            ),
            if (contribution != null)
              _MoreSection(
                title: strings.statistics,
                headerKey: const Key('sanmill_watch_statistics_group'),
                children: <Widget>[
                  _MoreTile(
                    key: const Key('drawer_item_statistics'),
                    icon: contribution.icon ?? Icons.bar_chart_rounded,
                    title: contribution.label,
                    onTap: () => onWatchRouteSelected(contribution.id.value),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _MoreTabRoot extends StatelessWidget {
  const _MoreTabRoot({
    required this.scrollController,
    required this.onAppRouteSelected,
    required this.onFeedback,
    required this.onExit,
  });

  final ScrollController scrollController;
  final ValueChanged<String> onAppRouteSelected;
  final VoidCallback onFeedback;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          strings.appName,
          key: const Key('sanmill_more_appbar_title'),
        ),
      ),
      body: ListTileTheme.merge(
        iconColor: Theme.of(context).colorScheme.primary,
        child: ListView(
          key: const Key('sanmill_more_list'),
          controller: scrollController,
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          children: <Widget>[
            _MenuEntries(
              onAppRouteSelected: onAppRouteSelected,
              onFeedback: onFeedback,
              onExit: onExit,
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuEntries extends StatelessWidget {
  const _MenuEntries({
    required this.onAppRouteSelected,
    required this.onFeedback,
    required this.onExit,
  });

  final ValueChanged<String> onAppRouteSelected;
  final VoidCallback onFeedback;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final GameModule module = GameRegistry.instance.current;
    final List<GameMenuContribution> contributionTools = module
        .drawerContributions(context)
        .where(
          (GameMenuContribution contribution) =>
              contribution.section == GameMenuSection.tools &&
              contribution.targets.contains(GameMenuTarget.more) &&
              contribution.availableIn(context),
        )
        .toList(growable: false);
    final List<GameModeEntry> tools = module
        .playModes(context)
        .where(
          (GameModeEntry mode) =>
              mode.section == GameMenuSection.tools &&
              mode.availableIn(context),
        )
        .toList(growable: false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _MoreSection(
          title: strings.tools,
          headerKey: const Key('drawer_item_tools_group'),
          children: <Widget>[
            for (final GameMenuContribution tool in contributionTools)
              _MoreTile(
                key: tool.drawerKey ?? Key('more_tool_${tool.id.value}'),
                icon: tool.icon ?? Icons.build_rounded,
                title: tool.label,
                onTap: () => onAppRouteSelected(tool.id.value),
              ),
            for (final GameModeEntry tool in tools)
              _MoreTile(
                key: tool.drawerKey ?? Key('more_tool_${tool.id.value}'),
                icon: tool.icon ?? Icons.build_rounded,
                title: tool.label,
                onTap: () => onAppRouteSelected(tool.id.value),
              ),
            _MoreTile(
              key: const Key('drawer_item_clock'),
              icon: Icons.alarm_outlined,
              title: strings.clock,
              onTap: () => onAppRouteSelected(ShellRouteIds.appClock.value),
            ),
            if (module.metadata.id == GameId.mill)
              _MoreTile(
                key: const Key('drawer_item_variants'),
                icon: Icons.category_outlined,
                title: strings.variants,
                onTap: () =>
                    onAppRouteSelected(ShellRouteIds.appVariants.value),
              ),
          ],
        ),
        _MoreSection(
          title: strings.settings,
          headerKey: const Key('drawer_item_settings_group'),
          children: <Widget>[
            _MoreTile(
              key: const Key('drawer_item_settings'),
              icon: Icons.settings_outlined,
              title: strings.settings,
              onTap: () =>
                  onAppRouteSelected(ShellRouteIds.appSettingsGroup.value),
            ),
          ],
        ),
        _MoreSection(
          title: strings.help,
          headerKey: const Key('drawer_item_help_group'),
          children: <Widget>[
            _MoreTile(
              key: const Key('drawer_item_how_to_play'),
              icon: Icons.school_rounded,
              title: strings.howToPlay,
              onTap: () => onAppRouteSelected(ShellRouteIds.appHowToPlay.value),
            ),
            if (!kIsWeb && Platform.isAndroid)
              _MoreTile(
                key: const Key('drawer_item_feedback'),
                icon: Icons.feedback_rounded,
                title: strings.feedback,
                onTap: onFeedback,
              ),
            _MoreTile(
              key: const Key('drawer_item_about'),
              icon: Icons.info_rounded,
              title: strings.about,
              onTap: () => onAppRouteSelected(ShellRouteIds.appAbout.value),
            ),
          ],
        ),
        if (!kIsWeb && Platform.isAndroid)
          _MoreSection(
            title: strings.appName,
            children: <Widget>[
              _MoreTile(
                key: const Key('drawer_item_exit'),
                icon: Icons.power_settings_new_rounded,
                title: strings.exit,
                onTap: onExit,
              ),
            ],
          ),
      ],
    );
  }
}

class _MoreSection extends StatelessWidget {
  const _MoreSection({
    required this.title,
    required this.children,
    this.headerKey,
    this.onHeaderTap,
  });

  final String title;
  final List<Widget> children;
  final Key? headerKey;
  final VoidCallback? onHeaderTap;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return LichessListSection(
      headerKey: headerKey,
      header: onHeaderTap == null
          ? Text(title)
          : _MoreSectionHeaderLink(title: title, onTap: onHeaderTap!),
      children: children,
    );
  }
}

class _MoreSectionHeaderLink extends StatelessWidget {
  const _MoreSectionHeaderLink({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(title),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: Theme.of(context).platform == TargetPlatform.iOS
          ? const Icon(Icons.chevron_right_rounded)
          : null,
      onTap: onTap,
    );
  }
}

class _UnavailableTabPage extends StatelessWidget {
  const _UnavailableTabPage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(label)),
      body: Center(
        child: Icon(
          Icons.block_rounded,
          size: 48,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
