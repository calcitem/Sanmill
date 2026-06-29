// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../game_page/services/mill.dart' show GameController, GameMode;
import '../../game_page/services/painters/painters.dart' show deviceWidth;
import '../../game_page/widgets/dialogs/lan_config_dialog.dart';
import '../../game_page/widgets/game_page.dart' show GamePage;
import '../../game_page/widgets/import_game_page.dart';
import '../../game_page/widgets/moves_list_page.dart';
import '../../game_platform/board_geometry.dart';
import '../../game_platform/engine/engine_port.dart';
import '../../game_platform/engine/native_topology.dart';
import '../../game_platform/game_export.dart';
import '../../game_platform/game_feature_flags.dart';
import '../../game_platform/game_id.dart';
import '../../game_platform/game_menu.dart';
import '../../game_platform/game_module.dart';
import '../../game_platform/game_module_metadata.dart';
import '../../game_platform/game_persistence_scope.dart';
import '../../game_platform/game_session.dart';
import '../../game_platform/game_session_handle.dart';
import '../../game_platform/notation_port.dart';
import '../../game_platform/rule_settings_port.dart';
import '../../game_platform/rules_port.dart';
import '../../game_platform/shell_route_navigation_source.dart';
import '../../general_settings/models/general_settings.dart';
import '../../generated/intl/l10n.dart';
import '../../puzzle/pages/puzzles_home_page.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../rule_settings/widgets/rule_settings_page.dart';
import '../../shared/database/database.dart' show DB;
import '../../shared/database/settings_repositories.dart';
import '../../shared/services/logger.dart';
import '../../shared/services/snackbar_service.dart';
import '../../shared/themes/app_theme.dart';
import '../../statistics/widgets/stats_page.dart';
import 'mill_engine_port.dart';
import 'mill_marked_pieces_codec.dart';
import 'mill_notation_port.dart';
import 'mill_route_ids.dart';
import 'mill_rule_settings_port.dart';
import 'native_mill_game_session.dart';
import 'native_mill_rules_port.dart';
import 'opening_explorer/opening_explorer_page.dart';

typedef NativeMillSessionFactory =
    GameSessionHandle Function({
      required RuleSettings ruleSettings,
      GeneralSettings? generalSettings,
    });

class MillGameModule extends GameModule {
  MillGameModule({NativeMillSessionFactory? nativeSessionFactory})
    : _nativeSessionFactory =
          nativeSessionFactory ??
          (({
            required RuleSettings ruleSettings,
            GeneralSettings? generalSettings,
          }) {
            return NativeMillGameSession(
              rules: ruleSettings,
              generalSettings: generalSettings,
            );
          }) {
    // Hook the Mill payload extras decoder into the framework so generic
    // [TgfKernel] callers see `millMarkedNodes` in their snapshot payload
    // without the framework needing to know about Mill internals.
    registerMillKernelExtras();
  }

  final NativeMillSessionFactory _nativeSessionFactory;

  @override
  GameModuleMetadata get metadata =>
      const GameModuleMetadata(id: GameId.mill, shortLabel: 'Mill');

  @override
  GameFeatureFlags get features => const GameFeatureFlags(
    supportsAi: true,
    supportsLan: true,
    supportsPuzzles: true,
    supportsStatistics: true,
    supportsTimer: true,
    capabilities: <GameCapability>{
      GameCapability.analysis,
      GameCapability.importExport,
      GameCapability.recording,
    },
  );

  @override
  BoardGeometry get boardGeometry =>
      const NativeTopologyFactory().millBoardGeometry();

  /// Mill legacy [Hive] models use scattered low typeId values (0–~38) — frozen.
  @override
  GamePersistenceScope get persistenceScope => const GamePersistenceScope(
    gameId: GameId.mill,
    hiveTypeIdMin: 0,
    hiveTypeIdMax: 50,
  );

  @override
  GameSessionHandle startSession() {
    return _nativeSessionFactory(
      ruleSettings: DB().ruleSettings,
      generalSettings: DB().generalSettings,
    );
  }

  /// Creates a Rust-native Mill session.  Alias for [startSession] kept for
  /// call-site clarity in tests.
  GameSessionHandle startNativeSession({
    RuleSettings ruleSettings = const RuleSettings(),
    GeneralSettings? generalSettings,
  }) {
    return _nativeSessionFactory(
      ruleSettings: ruleSettings,
      generalSettings: generalSettings,
    );
  }

  @override
  RulesPort? get rulesPort => NativeMillRulesPort(
    ruleSettings: DB().ruleSettings,
    generalSettings: DB().generalSettings,
  );

  /// Alias for [rulesPort]; provided for explicit opt-in at call sites.
  RulesPort nativeRulesPort({
    RuleSettings ruleSettings = const RuleSettings(),
  }) {
    return NativeMillRulesPort(ruleSettings: ruleSettings);
  }

  @override
  NotationPort? get notationPort => const MillNotationPort();

  @override
  RuleSettingsPort<Object>? get ruleSettingsPort =>
      MillRuleSettingsPort(SettingsRepositories.instance.repository)
          as RuleSettingsPort<Object>;

  @override
  GameExportData? buildExportData(
    BuildContext context, {
    required GameSession session,
  }) {
    // Mill exports through its dedicated PGN writer (`ExportService`),
    // which preserves the tag pairs, move numbers, the result marker,
    // variations, annotations, and the setup `[FEN]`.  The cross-game
    // `NotationPort` can only emit a flat space-separated move-token
    // list and would silently drop all of that, so opt out of the
    // generic export path here: `GameController.export` then falls back
    // to the full PGN exporter.  Revisit once the notation port can
    // round-trip PGN metadata and variations.
    return null;
  }

  @override
  EnginePort? get enginePort => MillEnginePortAdapter();

  @override
  Widget? buildRuleSettingsScreen(BuildContext context) =>
      const RuleSettingsPage();

  @override
  String defaultShellRoute(BuildContext context) {
    return MillRouteIds.humanVsAi.value;
  }

  @override
  void applyShellLayoutHints(BuildContext context) {
    AppTheme.boardPadding =
        ((deviceWidth(context) - AppTheme.boardMargin * 2) *
                DB().displaySettings.pieceWidth /
                7) /
            2 +
        4;
  }

  @override
  void applyFirstRunDefaults(BuildContext context) {
    final Locale locale = Localizations.localeOf(context);
    final String languageCode = locale.languageCode;
    final SettingsRepositories repositories = SettingsRepositories.instance;

    switch (languageCode) {
      case 'af': // South Africa
      case 'zu': // South Africa
        repositories.repository.ruleSettings = repositories
            .repository
            .ruleSettings
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
        repositories.repository.ruleSettings = repositories
            .repository
            .ruleSettings
            .copyWith(piecesCount: 12, hasDiagonalLines: true);
        break;
      case 'ru': // Russia
        repositories.repository.ruleSettings = repositories
            .repository
            .ruleSettings
            .copyWith(oneTimeUseMill: true, mayRemoveFromMillsAlways: true);
        break;
      case 'ko': // Korea
        repositories.repository.ruleSettings = repositories
            .repository
            .ruleSettings
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
  bool shouldShowRuleSettingsOnboarding(Locale locale) {
    switch (locale.languageCode) {
      case 'af':
      case 'fa':
      case 'fr':
      case 'nb':
      case 'nl':
      case 'ru':
      case 'tr':
      case 'uk':
      case 'zh':
        return true;
      default:
        return false;
    }
  }

  @override
  void onShellInactive(
    BuildContext context, {
    required String lastShellRouteId,
  }) {
    if (lastShellRouteId == MillRouteIds.humanVsLan.value) {
      logger.i(
        'Game switch: leaving LAN mode, disposing network and resetting board.',
      );
      // ignore: deprecated_member_use_from_same_package
      GameController().networkService?.dispose();
      // ignore: deprecated_member_use_from_same_package
      GameController().networkService = null;
      // ignore: deprecated_member_use_from_same_package
      GameController().reset(force: true);
    }
  }

  @override
  Future<bool> willNavigateToShellRoute(
    BuildContext context, {
    required String? previousRouteId,
    required String nextRouteId,
    ShellRouteNavigationSource source = ShellRouteNavigationSource.drawer,
  }) async {
    if (source != ShellRouteNavigationSource.drawer) {
      return true;
    }
    if (nextRouteId != MillRouteIds.humanVsLan.value ||
        previousRouteId == MillRouteIds.humanVsLan.value) {
      return true;
    }
    final S s = S.of(context);
    SnackBarService.showRootSnackBar(s.experimental);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext _) => const LanConfigDialog(),
    );
    return confirmed ?? false;
  }

  @override
  void didNavigateShellRoute(
    BuildContext context, {
    required String? previousRouteId,
    required String nextRouteId,
  }) {
    if (previousRouteId == MillRouteIds.humanVsLan.value &&
        nextRouteId != MillRouteIds.humanVsLan.value) {
      logger.i('Leaving LAN mode: disposing network and resetting the board.');
      // ignore: deprecated_member_use_from_same_package
      GameController().networkService?.dispose();
      // ignore: deprecated_member_use_from_same_package
      GameController().networkService = null;
      // ignore: deprecated_member_use_from_same_package
      GameController().reset(force: true);
    }
    if (isPlayModeRoute(nextRouteId, context)) {
      _syncMillStatsForPlayModeRoute(nextRouteId);
    }
  }

  void _syncMillStatsForPlayModeRoute(String playRouteId) {
    if (playRouteId == MillRouteIds.humanVsHuman.value ||
        playRouteId == MillRouteIds.aiVsAi.value) {
      GameController().disableStats = true;
    } else {
      GameController().disableStats = false;
    }
  }

  @override
  List<GameModeEntry> playModes(BuildContext context) {
    final S s = S.of(context);
    return <GameModeEntry>[
      GameModeEntry(
        id: MillRouteIds.humanVsAi,
        label: s.playAgainstComputer,
        icon: Icons.memory_rounded,
        drawerKey: const Key('drawer_item_human_vs_ai'),
        contentKey: const Key('human_ai'),
        isAvailable: (_) => features.supports(GameCapability.ai),
        builder: (BuildContext context, {Key? key, GameSession? session}) =>
            GamePage(GameMode.humanVsAi, key: key),
      ),
      GameModeEntry(
        id: MillRouteIds.humanVsHuman,
        label: s.overTheBoard,
        icon: Icons.table_restaurant_outlined,
        drawerKey: const Key('drawer_item_human_vs_human'),
        contentKey: const Key('human_human'),
        builder: (BuildContext context, {Key? key, GameSession? session}) =>
            GamePage(GameMode.humanVsHuman, key: key),
      ),
      GameModeEntry(
        id: MillRouteIds.aiVsAi,
        label: s.aiVsAi,
        icon: FluentIcons.bot_24_regular,
        drawerKey: const Key('drawer_item_ai_vs_ai'),
        contentKey: const Key('ai_ai'),
        isAvailable: (_) => features.supports(GameCapability.ai),
        builder: (BuildContext context, {Key? key, GameSession? session}) =>
            GamePage(GameMode.aiVsAi, key: key),
      ),
      GameModeEntry(
        id: MillRouteIds.humanVsLan,
        label: s.humanVsLAN,
        icon: FluentIcons.wifi_1_24_regular,
        drawerKey: const Key('drawer_item_human_vs_lan'),
        contentKey: const Key('human_lan'),
        isAvailable: (_) => features.supports(GameCapability.lan),
        builder: (BuildContext context, {Key? key, GameSession? session}) =>
            GamePage(GameMode.humanVsLAN, key: key),
      ),
      GameModeEntry(
        id: MillRouteIds.setupPosition,
        label: s.boardEditor,
        section: GameMenuSection.tools,
        icon: FluentIcons.edit_24_regular,
        drawerKey: const Key('drawer_item_setup_position'),
        contentKey: const Key('setup_position'),
        builder: (BuildContext context, {Key? key, GameSession? session}) =>
            GamePage(GameMode.setupPosition, key: key),
      ),
    ];
  }

  @override
  List<GameMenuContribution> drawerContributions(BuildContext context) {
    final S s = S.of(context);
    return <GameMenuContribution>[
      GameMenuContribution(
        id: MillRouteIds.importGame,
        label: s.importGame,
        section: GameMenuSection.tools,
        icon: FluentIcons.clipboard_paste_24_regular,
        drawerKey: const Key('drawer_item_import_game'),
        contentKey: const Key('import_game'),
        builder: (BuildContext context, {Key? key, GameSession? session}) {
          return ImportGamePage(key: key);
        },
      ),
      GameMenuContribution(
        id: MillRouteIds.analysis,
        label: s.analysis,
        section: GameMenuSection.tools,
        icon: FluentIcons.beaker_24_regular,
        drawerKey: const Key('drawer_item_analysis'),
        contentKey: const Key('analysis_panel'),
        builder: (BuildContext context, {Key? key, GameSession? session}) {
          return MovesListPage.analysisPanel(key: key);
        },
      ),
      GameMenuContribution(
        id: MillRouteIds.openingExplorer,
        label: s.openingExplorer,
        section: GameMenuSection.tools,
        icon: FluentIcons.book_open_24_regular,
        drawerKey: const Key('drawer_item_opening_explorer'),
        contentKey: const Key('opening_explorer'),
        builder: (BuildContext context, {Key? key, GameSession? session}) {
          return OpeningExplorerPage(key: key, session: session);
        },
      ),
      if (features.supports(GameCapability.puzzles))
        GameMenuContribution(
          id: MillRouteIds.puzzles,
          label: s.puzzles,
          icon: FluentIcons.puzzle_piece_24_regular,
          targets: const <GameMenuTarget>{GameMenuTarget.puzzles},
          drawerKey: const Key('drawer_item_puzzles'),
          contentKey: const Key('puzzles'),
          isAvailable: (_) => features.supports(GameCapability.puzzles),
          builder: (BuildContext context, {Key? key, GameSession? session}) {
            return PuzzlesHomePage(key: key);
          },
        ),
      if (features.supports(GameCapability.statistics))
        GameMenuContribution(
          id: MillRouteIds.statistics,
          label: s.statistics,
          icon: FluentIcons.calculator_24_regular,
          targets: const <GameMenuTarget>{GameMenuTarget.watch},
          drawerKey: const Key('drawer_item_statistics'),
          contentKey: const Key('statistics'),
          isAvailable: (_) => features.supports(GameCapability.statistics),
          builder: (BuildContext context, {Key? key, GameSession? session}) {
            return StatisticsPage(key: key);
          },
        ),
    ];
  }

  @override
  Widget buildGameSurface(
    BuildContext context, {
    Key? key,
    GameSession? session,
  }) {
    return GamePage(GameMode.humanVsAi, key: key);
  }
}
