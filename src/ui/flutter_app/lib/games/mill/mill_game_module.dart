// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../game_page/services/mill.dart' show GameController, GameMode;
import '../../game_page/services/painters/painters.dart' show deviceWidth;
import '../../game_page/widgets/dialogs/lan_config_dialog.dart';
import '../../game_page/widgets/game_page.dart' show GamePage;
import '../../game_platform/board_geometry.dart';
import '../../game_platform/game_feature_flags.dart';
import '../../game_platform/game_id.dart';
import '../../game_platform/game_menu.dart';
import '../../game_platform/game_module.dart';
import '../../game_platform/game_module_metadata.dart';
import '../../game_platform/game_persistence_scope.dart';
import '../../game_platform/game_session.dart';
import '../../game_platform/game_session_handle.dart';
import '../../game_platform/notation_port.dart';
import '../../game_platform/rules_port.dart';
import '../../game_platform/shell_route_navigation_source.dart';
import '../../generated/intl/l10n.dart';
import '../../puzzle/pages/puzzles_home_page.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';
import '../../shared/services/snackbar_service.dart';
import '../../shared/themes/app_theme.dart';
import '../../statistics/widgets/stats_page.dart';
import 'mill_board_geometry.dart';
import 'mill_game_session.dart';
import 'mill_notation_port.dart';
import 'mill_route_ids.dart';
import 'mill_rules_adapter.dart';

class MillGameModule extends GameModule {
  MillGameModule();

  @override
  GameModuleMetadata get metadata =>
      const GameModuleMetadata(id: GameId.mill, shortLabel: 'Mill');

  @override
  GameFeatureFlags get features => const GameFeatureFlags(
    supportsAi: true,
    supportsLan: true,
    supportsPuzzles: true,
    supportsSetupPosition: true,
    supportsStatistics: true,
    supportsTimer: true,
    capabilities: <GameCapability>{
      GameCapability.analysis,
      GameCapability.importExport,
      GameCapability.recording,
    },
  );

  @override
  BoardGeometry get boardGeometry => millDefaultBoardGeometry;

  /// Mill legacy [Hive] models use scattered low typeId values (0–~38) — frozen.
  @override
  GamePersistenceScope get persistenceScope => const GamePersistenceScope(
    gameId: GameId.mill,
    hiveTypeIdMin: 0,
    hiveTypeIdMax: 50,
  );

  @override
  GameSessionHandle startSession() => MillGameSession();

  @override
  RulesPort? get rulesPort => MillRulesAdapter();

  @override
  NotationPort? get notationPort => const MillNotationPort();

  @override
  String defaultShellRoute(BuildContext context) {
    return kIsWeb ? MillRouteIds.humanVsHuman : MillRouteIds.humanVsAi;
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
  void onShellInactive(
    BuildContext context, {
    required String lastShellRouteId,
  }) {
    if (lastShellRouteId == MillRouteIds.humanVsLan) {
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
    if (nextRouteId != MillRouteIds.humanVsLan ||
        previousRouteId == MillRouteIds.humanVsLan) {
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
    if (previousRouteId == MillRouteIds.humanVsLan &&
        nextRouteId != MillRouteIds.humanVsLan) {
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
    if (playRouteId == MillRouteIds.humanVsHuman ||
        playRouteId == MillRouteIds.aiVsAi) {
      GameController().disableStats = true;
    } else {
      GameController().disableStats = false;
    }
  }

  @override
  List<GameModeEntry> playModes(BuildContext context) {
    final S s = S.of(context);
    return <GameModeEntry>[
      if (!kIsWeb)
        GameModeEntry(
          id: MillRouteIds.humanVsAi,
          label: s.humanVsAi,
          contentKey: const Key('human_ai'),
          isAvailable: (_) => !kIsWeb,
          builder: (BuildContext context, {Key? key, GameSession? session}) =>
              GamePage(GameMode.humanVsAi, key: key),
        ),
      GameModeEntry(
        id: MillRouteIds.humanVsHuman,
        label: s.humanVsHuman,
        contentKey: const Key('human_human'),
        builder: (BuildContext context, {Key? key, GameSession? session}) =>
            GamePage(GameMode.humanVsHuman, key: key),
      ),
      if (!kIsWeb)
        GameModeEntry(
          id: MillRouteIds.aiVsAi,
          label: s.aiVsAi,
          contentKey: const Key('ai_ai'),
          isAvailable: (_) => !kIsWeb,
          builder: (BuildContext context, {Key? key, GameSession? session}) =>
              GamePage(GameMode.aiVsAi, key: key),
        ),
      GameModeEntry(
        id: MillRouteIds.humanVsLan,
        label: s.humanVsLAN,
        contentKey: const Key('human_lan'),
        builder: (BuildContext context, {Key? key, GameSession? session}) =>
            GamePage(GameMode.humanVsLAN, key: key),
      ),
      GameModeEntry(
        id: MillRouteIds.setupPosition,
        label: s.setupPosition,
        contentKey: const Key('setup_position'),
        isAvailable: (BuildContext context) {
          return DB().ruleSettings.millFormationActionInPlacingPhase !=
                  MillFormationActionInPlacingPhase
                      .removeOpponentsPieceFromHandThenYourTurn &&
              DB().ruleSettings.millFormationActionInPlacingPhase !=
                  MillFormationActionInPlacingPhase
                      .removeOpponentsPieceFromHandThenOpponentsTurn;
        },
        builder: (BuildContext context, {Key? key, GameSession? session}) =>
            GamePage(GameMode.setupPosition, key: key),
      ),
    ];
  }

  @override
  List<GameMenuContribution> drawerContributions(BuildContext context) {
    if (!features.supportsPuzzles && !features.supportsStatistics) {
      return const <GameMenuContribution>[];
    }
    final S s = S.of(context);
    return <GameMenuContribution>[
      if (features.supportsPuzzles)
        GameMenuContribution(
          id: MillRouteIds.puzzles,
          label: s.puzzles,
          contentKey: const Key('puzzles'),
          isAvailable: (_) => features.supportsPuzzles,
          builder: (BuildContext context, {Key? key, GameSession? session}) {
            return PuzzlesHomePage(key: key);
          },
        ),
      if (features.supportsStatistics)
        GameMenuContribution(
          id: MillRouteIds.statistics,
          label: s.statistics,
          contentKey: const Key('statistics'),
          isAvailable: (_) => features.supportsStatistics,
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
    return GamePage(
      kIsWeb ? GameMode.humanVsHuman : GameMode.humanVsAi,
      key: key,
    );
  }
}
