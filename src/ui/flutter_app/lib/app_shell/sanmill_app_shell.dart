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
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../experience_recording/models/recording_models.dart';
import '../experience_recording/services/recording_service.dart';
import '../game_page/services/mill.dart' show GameController;
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
        return Icons.home_rounded;
      case SanmillShellTab.puzzles:
        return Icons.extension_rounded;
      case SanmillShellTab.learn:
        return Icons.school_rounded;
      case SanmillShellTab.watch:
        return Icons.live_tv_rounded;
      case SanmillShellTab.more:
        return Icons.menu_rounded;
    }
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
  final Map<SanmillShellTab, ScrollController> _scrollControllers =
      <SanmillShellTab, ScrollController>{
        for (final SanmillShellTab tab in SanmillShellTab.values)
          tab: ScrollController(debugLabel: 'Sanmill ${tab.name} root'),
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
    }
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

  String _rootRouteIdForTab(SanmillShellTab tab) {
    switch (tab) {
      case SanmillShellTab.home:
        return SanmillShellRouteIds.homeRoot.value;
      case SanmillShellTab.puzzles:
        return _puzzlesContribution(context)?.id.value ??
            SanmillShellRouteIds.moreRoot.value;
      case SanmillShellTab.learn:
        return ShellRouteIds.appHowToPlay.value;
      case SanmillShellTab.watch:
        return SanmillShellRouteIds.watchRoot.value;
      case SanmillShellTab.more:
        return SanmillShellRouteIds.moreRoot.value;
    }
  }

  GameMenuContribution? _puzzlesContribution(BuildContext context) {
    return _findContribution(
      context,
      (GameMenuContribution contribution) =>
          contribution.id.value.toLowerCase().contains('puzzle'),
    );
  }

  GameMenuContribution? _statisticsContribution(BuildContext context) {
    return _findContribution(
      context,
      (GameMenuContribution contribution) =>
          contribution.id.value.toLowerCase().contains('statistic'),
    );
  }

  GameMenuContribution? _findContribution(
    BuildContext context,
    bool Function(GameMenuContribution contribution) test,
  ) {
    return _findGameMenuContribution(context, test);
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

  Widget _buildTabRoot(SanmillShellTab tab) {
    switch (tab) {
      case SanmillShellTab.home:
        return _HomeTabRoot(
          scrollController: _scrollControllers[SanmillShellTab.home]!,
          onPlayRouteSelected: _selectPlayRoute,
        );
      case SanmillShellTab.puzzles:
        final GameMenuContribution? contribution = _puzzlesContribution(
          context,
        );
        return contribution == null
            ? _UnavailableTabPage(label: S.of(context).puzzles)
            : _buildRouteSurface(contribution.id.value);
      case SanmillShellTab.learn:
        return _buildRouteSurface(ShellRouteIds.appHowToPlay.value);
      case SanmillShellTab.watch:
        return _WatchTabRoot(
          scrollController: _scrollControllers[SanmillShellTab.watch]!,
          statisticsContribution: _statisticsContribution(context),
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
      final String nextRouteId = _rootRouteIdForTab(_currentTab);
      if (!await _transitionToRoute(nextRouteId)) {
        return false;
      }
      if (!mounted) {
        return false;
      }
      navigator!.pop();
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
        bottomNavigationBar: NavigationBar(
          key: const Key('sanmill_bottom_navigation_bar'),
          selectedIndex: _currentTab.index,
          destinations: <NavigationDestination>[
            for (final SanmillShellTab tab in SanmillShellTab.values)
              NavigationDestination(
                key: tab.key,
                icon: Icon(tab.icon),
                selectedIcon: Icon(tab.icon),
                label: tab.label(strings),
              ),
          ],
          onDestinationSelected: (int index) =>
              _selectTab(SanmillShellTab.values[index]),
        ),
      ),
    );

    return content;
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

  @override
  void initState() {
    super.initState();
    _builtTabs.add(widget.currentTab);
  }

  @override
  void didUpdateWidget(covariant _SanmillTabSwitchingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _builtTabs.add(widget.currentTab);
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
                child: widget.tabBuilder(context, tab),
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

class _HomeTabRoot extends StatelessWidget {
  const _HomeTabRoot({
    required this.scrollController,
    required this.onPlayRouteSelected,
  });

  final ScrollController scrollController;
  final ValueChanged<String> onPlayRouteSelected;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final GameModule module = GameRegistry.instance.current;
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
      body: ListTileTheme.merge(
        iconColor: Theme.of(context).colorScheme.primary,
        child: ListView(
          key: const Key('sanmill_home_list'),
          controller: scrollController,
          padding: const EdgeInsets.only(top: 16, bottom: 24),
          children: <Widget>[
            _MoreSection(
              title: strings.game,
              headerKey: const Key('sanmill_home_play_modes_group'),
              children: <Widget>[
                for (final GameModeEntry mode in playModes)
                  _MoreTile(
                    key: mode.drawerKey ?? Key('home_${mode.id.value}'),
                    icon: mode.icon ?? Icons.sports_esports_rounded,
                    title: mode.label,
                    onTap: () => onPlayRouteSelected(mode.id.value),
                  ),
              ],
            ),
          ],
        ),
      ),
      floatingActionButton: playModes.isEmpty
          ? null
          : _FloatingPlayButton(
              onPressed: () => _showPlayBottomSheet(context, playModes),
            ),
    );
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
          onPlayRouteSelected: onPlayRouteSelected,
        );
      },
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
      tooltip: S.of(context).newGame,
      icon: const Icon(Icons.sports_esports_rounded),
      label: Text(S.of(context).newGame),
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
    return SingleChildScrollView(
      key: const Key('sanmill_home_play_sheet'),
      padding: EdgeInsets.fromLTRB(
        0,
        8,
        0,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: LichessListSection(
        header: Text(strings.game),
        cardKey: const Key('sanmill_home_play_sheet_card'),
        children: <Widget>[
          for (final GameModeEntry mode in playModes)
            _MoreTile(
              key: Key('sanmill_home_play_sheet_${mode.id.value}'),
              icon: mode.icon ?? Icons.sports_esports_rounded,
              title: mode.label,
              onTap: () {
                Navigator.of(context).pop();
                onPlayRouteSelected(mode.id.value);
              },
            ),
        ],
      ),
    );
  }
}

class _WatchTabRoot extends StatelessWidget {
  const _WatchTabRoot({
    required this.scrollController,
    required this.statisticsContribution,
    required this.onWatchRouteSelected,
  });

  final ScrollController scrollController;
  final GameMenuContribution? statisticsContribution;
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
            if (contribution != null)
              _MoreSection(
                title: strings.watch,
                children: <Widget>[
                  _MoreTile(
                    key: const Key('drawer_item_statistics'),
                    icon: contribution.icon ?? Icons.bar_chart_rounded,
                    title: contribution.label,
                    onTap: () => onWatchRouteSelected(contribution.id.value),
                  ),
                ],
              )
            else
              SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.5,
                child: Center(
                  child: Icon(
                    Icons.visibility_off_rounded,
                    size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
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
          ],
        ),
        _MoreSection(
          title: strings.settings,
          headerKey: const Key('drawer_item_settings_group'),
          children: <Widget>[
            _MoreTile(
              key: const Key('drawer_item_general_settings'),
              icon: Icons.tune_rounded,
              title: strings.generalSettings,
              onTap: () =>
                  onAppRouteSelected(ShellRouteIds.appGeneralSettings.value),
            ),
            if (module.buildRuleSettingsScreen(context) != null)
              _MoreTile(
                key: const Key('drawer_item_rule_settings'),
                icon: Icons.rule_rounded,
                title: strings.ruleSettings,
                onTap: () =>
                    onAppRouteSelected(ShellRouteIds.appRuleSettings.value),
              ),
            _MoreTile(
              key: const Key('drawer_item_appearance'),
              icon: Icons.palette_rounded,
              title: strings.appearance,
              onTap: () =>
                  onAppRouteSelected(ShellRouteIds.appAppearance.value),
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
  });

  final String title;
  final List<Widget> children;
  final Key? headerKey;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return LichessListSection(
      headerKey: headerKey,
      header: Text(title),
      children: children,
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
