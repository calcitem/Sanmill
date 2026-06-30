// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// play_area.dart

import 'dart:async';
import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_screenshot_widget/native_screenshot_widget.dart';

import '../../experience_recording/models/recording_models.dart';
import '../../experience_recording/services/recording_service.dart';
import '../../game_platform/game_session.dart'
    show GameAction, GameSession, PlayerSeat;
import '../../game_shell/game_session_scope.dart';
import '../../games/mill/mill_action_codec.dart';
import '../../games/mill/mill_board_transform_actions.dart';
import '../../games/mill/native_mill_game_session.dart';
import '../../games/mill/native_mill_rules_port.dart';
import '../../games/mill/opening_explorer/opening_explorer_page.dart';
import '../../general_settings/widgets/general_settings_page.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/config/constants.dart';
import '../../shared/database/database.dart';
import '../../shared/services/screenshot_service.dart';
import '../../shared/themes/app_styles.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/widgets/lichess_action_sheet.dart';
import '../../shared/widgets/lichess_bottom_bar.dart';
import '../../shared/widgets/lichess_list_section.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../../statistics/services/stats_service.dart';
import '../services/analysis/analysis_service.dart';
import '../services/analysis_mode.dart';
import '../services/import_export/pgn.dart';
import '../services/mill.dart';
import '../services/painters/advantage_graph_painter.dart';
import '../services/player_timer.dart';
import 'ai_chat_dialog.dart';
import 'game_page.dart';
import 'mini_board.dart';
import 'modals/game_options_modal.dart';
import 'moves_list_page.dart';
import 'toolbars/game_toolbar.dart';

/// The PlayArea widget is the main content of the game page.
class PlayArea extends StatefulWidget {
  /// Creates a PlayArea widget.
  ///
  /// The [boardImage] parameter is the ImageProvider for the selected board image.
  /// The [child] is typically the GameBoard widget.
  const PlayArea({
    super.key,
    required this.boardImage,
    required this.child, // new
  });

  /// The ImageProvider for the selected board image.
  final ImageProvider? boardImage;

  /// The child widget to be displayed, typically the GameBoard.
  final Widget child;

  @override
  PlayAreaState createState() => PlayAreaState();
}

class PlayAreaState extends State<PlayArea> {
  /// A list to store historical advantage values for the advantage chart.
  List<int> advantageData = <int>[];

  bool _isBoardFlipped = false;
  bool _isHintSearching = false;
  static const double _kMoveListRouteTopInset = 80;
  static const double _kInlineMoveListHeight = 40;
  static const double _kPlayerPanelHeight = 56;
  static const double _kAnalysisEngineLinesReserveHeight = 90;
  static const double _kBalancedLayoutSafetyMargin = 24;
  static const double _kHumanDatabaseStatsStripHeight = 40;
  static const double _kAdvantageIndicatorWidth = 16;
  static const double _kAdvantageIndicatorGap = 6;

  @override
  void initState() {
    super.initState();
    // Listen to changes in header icons (usually triggered after a move).
    GameController().headerIconsNotifier.addListener(_updateUI);

    // Optionally, initialize advantageData with the current value:
    advantageData.add(_getCurrentAdvantageValue());
  }

  @override
  void dispose() {
    GameController().headerIconsNotifier.removeListener(_updateUI);
    super.dispose();
  }

  /// Retrieve the current advantage value from GameController.
  /// value > 0 means white advantage, value < 0 means black advantage.
  /// The range is [-100, 100].
  int _getCurrentAdvantageValue() {
    final int value = GameController().value == null
        ? 0
        : int.parse(GameController().value!);
    return value;
  }

  Widget? _buildHumanDatabaseStatsStrip(BuildContext context) {
    if (!DB().generalSettings.showHumanDatabaseStats) {
      return null;
    }
    final HumanDatabaseMoveStats? stats =
        GameController().activeNativeMillSession?.lastHumanDatabaseMoveStats;

    final Color contentColor = DB().colorSettings.messageColor.withValues(
      alpha: stats == null ? 0.58 : 0.78,
    );
    final Color borderColor = DB().colorSettings.messageColor.withValues(
      alpha: 0.16,
    );
    final String statsText = stats == null
        ? S.of(context).humanGameDatabaseStatsUnavailable
        : '${stats.notation}  '
              'W ${stats.winPercent.toStringAsFixed(1)}%  '
              'D ${stats.drawPercent.toStringAsFixed(1)}%  '
              'L ${stats.lossPercent.toStringAsFixed(1)}%  '
              'n=${stats.total}';

    return Padding(
      key: const Key('play_area_human_database_stats_strip'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.boardMargin,
        vertical: 4,
      ),
      child: Semantics(
        key: const Key('play_area_human_database_stats_semantics'),
        liveRegion: stats != null,
        child: DecoratedBox(
          key: const Key('play_area_human_database_stats'),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: <Widget>[
                  Icon(Icons.storage_rounded, size: 16, color: contentColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: Text(
                        statsText,
                        key: ValueKey<String>(statsText),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: contentColor),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _moveListRouteTopInset(BuildContext context) {
    return Navigator.canPop(context) ? _kMoveListRouteTopInset : 0;
  }

  Widget _withMoveListTopInset(BuildContext context, Widget child) {
    final double topInset = _moveListRouteTopInset(context);
    if (topInset == 0) {
      return child;
    }
    return Padding(
      key: const Key('play_area_move_list_route_top_inset'),
      padding: EdgeInsets.only(top: topInset),
      child: child,
    );
  }

  double _inlineMoveListHeightForRoute(BuildContext context) {
    return _kInlineMoveListHeight + _moveListRouteTopInset(context);
  }

  Color _actionSheetBackground(BuildContext context) {
    return Theme.of(context).colorScheme.surfaceContainerLow;
  }

  Color _actionSheetForeground(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface;
  }

  BuildContext _stableActionContext(BuildContext fallbackContext) {
    final BuildContext? overlayContext =
        currentNavigatorKey.currentState?.overlay?.context;
    if (overlayContext != null && overlayContext.mounted) {
      return overlayContext;
    }

    final BuildContext? messengerContext =
        rootScaffoldMessengerKey.currentState?.context;
    if (messengerContext != null &&
        messengerContext.mounted &&
        Navigator.maybeOf(messengerContext) != null) {
      return messengerContext;
    }

    assert(fallbackContext.mounted, 'Action menus require a mounted context.');
    return fallbackContext;
  }

  bool _shouldShowAdvantageGraph({required bool isGameSurface}) {
    return isGameSurface &&
        DB().displaySettings.isAdvantageGraphShown &&
        advantageData.isNotEmpty;
  }

  double _pieceRowsHeightForLayout(BuildContext context) {
    final double scaledTextHeight = MediaQuery.textScalerOf(context).scale(18);
    return math.max(24, scaledTextHeight + 6) * 2;
  }

  double _humanAiPlayerPanelHeightForLayout(BuildContext context) {
    final double scaledTextHeight = MediaQuery.textScalerOf(context).scale(38);
    return math.max(_kPlayerPanelHeight, scaledTextHeight + 18);
  }

  /// Updates the UI by calling setState.
  /// Appends the current advantage value so that the chart reflects
  /// the latest advantage trend after each AI move.
  void _updateUI() {
    setState(() {
      if (GameController().gameRecorder.mainlineMoves.isEmpty) {
        advantageData.clear();
        advantageData.add(_getCurrentAdvantageValue());
      }

      if (GameController().lastMoveFromAI &&
          GameController().value != null &&
          GameController().aiMoveType != AiMoveType.unknown) {
        advantageData.add(_getCurrentAdvantageValue());
        GameController().lastMoveFromAI = false;
      }
    });
  }

  /// Takes a screenshot and saves it to the specified [storageLocation]
  /// with an optional [filename].
  Future<void> _takeScreenshot(
    String storageLocation, [
    String? filename,
  ]) async {
    await ScreenshotService.takeScreenshot(storageLocation, filename);
  }

  /// Opens a modal bottom sheet containing [modal].
  void _openModal(BuildContext context, Widget modal) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.modalBottomSheetBackgroundColor,
      builder: (_) => modal,
    );
  }

  /// Navigates to the GeneralSettingsPage.
  void _navigateToSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<GeneralSettingsPage>(
        settings: const RouteSettings(name: '/generalSettings'),
        builder: (_) => const GeneralSettingsPage(),
      ),
    );
  }

  /// Opens a dialog with the provided [dialog] widget.
  void _openDialog(BuildContext context, Widget dialog) {
    showDialog(context: context, builder: (_) => dialog);
  }

  void _openGameOptions(BuildContext context) {
    _openModal(
      context,
      GameOptionsModal(onTriggerScreenshot: () => _takeScreenshot("gallery")),
    );
  }

  void _requestRegularNewGame(NavigatorState navigator) {
    if (_isAnalysisMode) {
      RecordingService().recordEvent(
        RecordingEventType.toolbarAction,
        <String, dynamic>{'toolbar': 'analysisBottom', 'action': 'newGame'},
      );
      GameController().reset();
      GameController().headerIconsNotifier.showIcons();
      GameController().boardSemanticsNotifier.updateSemantics();
      return;
    }

    _openGameOptions(navigator.context);
  }

  void _openMovesWithNavigator(NavigatorState navigator) {
    if (DB().generalSettings.screenReaderSupport) {
      // On screen readers, use a bottom sheet.
      final BuildContext navigatorContext = navigator.context;
      _openModal(navigatorContext, _buildMoveModal(navigatorContext));
      return;
    }

    // Complete all ongoing animations before navigating to ensure pieces are
    // in their final positions when the user returns.
    GameController().animationManager.completeAllAnimations();
    navigator.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/movesList'),
        builder: (BuildContext context) => const MovesListPage(),
      ),
    );
  }

  Future<void> _applyAnalysisMove(BuildContext context, String move) async {
    final GameSession? session = GameSessionScope.sessionOf(context);
    assert(session != null, 'Analysis move application requires a session.');
    if (session == null) {
      return;
    }

    GameAction? selectedAction;
    for (final GameAction action in session.legalActions) {
      if (MillActionCodec.moveStringFrom(action) == move) {
        selectedAction = action;
        break;
      }
    }

    assert(
      selectedAction != null,
      'Analysis move "$move" must be legal in the active session.',
    );
    if (selectedAction == null) {
      return;
    }

    AnalysisMode.disable();
    await session.apply(selectedAction);
  }

  void _openBoardEditorFromAnalysis() {
    assert(_isAnalysisMode, 'Board editor menu entry is analysis-mode only.');
    GameController().enterSetupPosition();
    if (mounted) {
      setState(() {});
    }
  }

  void _continueFromHere({
    required NativeMillGameSession session,
    required NavigatorState navigator,
    required GameMode mode,
  }) {
    assert(_isAnalysisMode, 'Continue from here is analysis-mode only.');
    assert(
      mode == GameMode.humanVsAi || mode == GameMode.humanVsHuman,
      'Continue from here only supports local playable modes.',
    );
    final String fen = session.getFen();
    final bool started = GameController().startGameFromFen(
      mode: mode,
      fen: fen,
    );
    assert(started, 'Continue from here must start from the current FEN.');

    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{
        'toolbar': 'analysisMenu',
        'action': 'continueFromHere',
        'mode': mode.toString(),
      },
    );

    navigator.pushReplacement(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/continueFromHere/${mode.name}'),
        builder: (BuildContext routeContext) =>
            _ContinueFromHereGameRoute(mode: mode),
      ),
    );
  }

  void _showContinueFromHereMenu(
    BuildContext context, {
    required NativeMillGameSession session,
    required NavigatorState navigator,
    S? strings,
  }) {
    assert(_isAnalysisMode, 'Continue from here menu is analysis-mode only.');
    if (!mounted) {
      return;
    }
    final BuildContext sheetContext = _stableActionContext(context);
    final S effectiveStrings = strings ?? S.of(sheetContext);
    showLichessActionSheet<void>(
      context: sheetContext,
      sheetKey: const Key('play_area_analysis_continue_from_here_sheet'),
      title: Text(effectiveStrings.continueFromHere),
      backgroundColor: _actionSheetBackground(sheetContext),
      foregroundColor: _actionSheetForeground(sheetContext),
      actions: <LichessActionSheetAction>[
        LichessActionSheetAction(
          key: const Key('play_area_analysis_continue_play_against_computer'),
          leading: const Icon(Icons.smart_toy_outlined),
          makeLabel: (BuildContext context) =>
              Text(effectiveStrings.playAgainstComputer),
          onPressed: () => _continueFromHere(
            session: session,
            navigator: navigator,
            mode: GameMode.humanVsAi,
          ),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_analysis_continue_over_the_board'),
          leading: const Icon(Icons.groups_2_outlined),
          makeLabel: (BuildContext context) =>
              Text(effectiveStrings.overTheBoard),
          onPressed: () => _continueFromHere(
            session: session,
            navigator: navigator,
            mode: GameMode.humanVsHuman,
          ),
        ),
      ],
    );
  }

  void _showAnalysisShareExportMenu(BuildContext context, {S? strings}) {
    assert(_isAnalysisMode, 'Share/export menu is analysis-mode only.');
    if (!mounted) {
      return;
    }

    final BuildContext sheetContext = _stableActionContext(context);
    final S effectiveStrings = strings ?? S.of(sheetContext);
    final GameRecorder recorder = GameController().gameRecorder;
    final bool hasVariations = recorder.hasVariations();
    final String pgn = recorder.moveHistoryText.trim();
    final String mainlinePgn = recorder.moveHistoryTextWithoutVariations.trim();
    final String currentLinePgn = recorder.moveHistoryTextCurrentLine.trim();
    final String? fen =
        GameController().activeFen ??
        GameController().activeNativeMillSession?.getFen();

    final List<LichessActionSheetAction> actions = <LichessActionSheetAction>[
      if (!hasVariations && mainlinePgn.isNotEmpty)
        LichessActionSheetAction(
          key: const Key('play_area_analysis_share_export_copy_pgn'),
          leading: const Icon(Icons.article_outlined),
          makeLabel: (BuildContext context) => Text(effectiveStrings.copyPgn),
          onPressed: () => unawaited(
            _copyAnalysisTextToClipboard(
              text: mainlinePgn,
              message: effectiveStrings.moveHistoryCopied,
              eventAction: 'copyPgn',
            ),
          ),
        ),
      if (hasVariations && mainlinePgn.isNotEmpty)
        LichessActionSheetAction(
          key: const Key('play_area_analysis_share_export_copy_mainline'),
          leading: const Icon(Icons.show_chart_outlined),
          makeLabel: (BuildContext context) =>
              Text(effectiveStrings.includeVariationsMainline),
          onPressed: () => unawaited(
            _copyAnalysisTextToClipboard(
              text: mainlinePgn,
              message: effectiveStrings.moveHistoryCopied,
              eventAction: 'copyMainlinePgn',
            ),
          ),
        ),
      if (hasVariations && currentLinePgn.isNotEmpty)
        LichessActionSheetAction(
          key: const Key('play_area_analysis_share_export_copy_current_line'),
          leading: const Icon(Icons.trending_flat),
          makeLabel: (BuildContext context) =>
              Text(effectiveStrings.includeVariationsCurrentLine),
          onPressed: () => unawaited(
            _copyAnalysisTextToClipboard(
              text: currentLinePgn,
              message: effectiveStrings.moveHistoryCopied,
              eventAction: 'copyCurrentLinePgn',
            ),
          ),
        ),
      if (hasVariations && pgn.isNotEmpty)
        LichessActionSheetAction(
          key: const Key('play_area_analysis_share_export_copy_all_variations'),
          leading: const Icon(Icons.account_tree_outlined),
          makeLabel: (BuildContext context) =>
              Text(effectiveStrings.includeVariationsAll),
          onPressed: () => unawaited(
            _copyAnalysisTextToClipboard(
              text: pgn,
              message: effectiveStrings.moveHistoryCopied,
              eventAction: 'copyAllVariationsPgn',
            ),
          ),
        ),
      if (fen != null && fen.trim().isNotEmpty)
        LichessActionSheetAction(
          key: const Key('play_area_analysis_share_export_copy_fen'),
          leading: const Icon(Icons.content_copy_outlined),
          makeLabel: (BuildContext context) => Text(effectiveStrings.copyFen),
          onPressed: () => unawaited(
            _copyAnalysisTextToClipboard(
              text: fen,
              message: effectiveStrings.fenCopiedToClipboard,
              eventAction: 'copyFen',
            ),
          ),
        ),
    ];
    assert(
      actions.isNotEmpty,
      'Share/export menu requires at least one PGN or FEN action.',
    );
    if (actions.isEmpty) {
      return;
    }

    showLichessActionSheet<void>(
      context: sheetContext,
      sheetKey: const Key('play_area_analysis_share_export_sheet'),
      title: Text(effectiveStrings.shareAndExport),
      backgroundColor: _actionSheetBackground(sheetContext),
      foregroundColor: _actionSheetForeground(sheetContext),
      actions: actions,
    );
  }

  Future<void> _copyAnalysisTextToClipboard({
    required String text,
    required String message,
    required String eventAction,
  }) async {
    assert(_isAnalysisMode, 'Analysis export is analysis-mode only.');
    assert(text.trim().isNotEmpty, 'Analysis export text must not be empty.');
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'analysisMenu', 'action': eventAction},
    );

    await Clipboard.setData(ClipboardData(text: text));

    assert(
      rootScaffoldMessengerKey.currentState != null,
      'Analysis export feedback requires the root scaffold messenger.',
    );
    rootScaffoldMessengerKey.currentState!.showSnackBarClear(message);
  }

  bool get _shouldShowAiChatMenuAction {
    if (!DB().generalSettings.aiChatEnabled) {
      return false;
    }

    final GameMode mode = GameController().gameInstance.gameMode;
    return mode == GameMode.humanVsAi ||
        mode == GameMode.humanVsHuman ||
        mode == GameMode.aiVsAi;
  }

  void _showAiChatDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => const AiChatDialog(),
    );
  }

  bool get _usesLichessHumanAiToolbar =>
      GameController().gameInstance.gameMode == GameMode.humanVsAi;

  bool get _isAnalysisMode =>
      GameController().gameInstance.gameMode == GameMode.analysis;

  Phase get _activePhase {
    return GameController().activeSessionPhase ??
        GameController().activeBoardView.phase;
  }

  bool get _canResignFromBottomBar {
    return _usesLichessHumanAiToolbar &&
        GameController().gameRecorder.currentPath.length >= 2 &&
        _activePhase != Phase.ready &&
        _activePhase != Phase.gameOver;
  }

  bool get _canTakeBackFromBottomBar {
    return _usesLichessHumanAiToolbar &&
        GameController().gameRecorder.currentPath.isNotEmpty &&
        !GameController().isEngineRunning &&
        !GameController().isEngineInDelay;
  }

  int get _humanAiTakeBackStepCount {
    assert(_usesLichessHumanAiToolbar);
    return _takeBackStepCountForRequester(_humanAiTakeBackRequesterSide);
  }

  int get _lanTakeBackStepCount {
    assert(GameController().gameInstance.gameMode == GameMode.humanVsLAN);
    final PieceColor requesterSide = GameController().getLocalColor();
    assert(
      requesterSide == PieceColor.white || requesterSide == PieceColor.black,
      'LAN takeback requires a playable local requester side.',
    );
    return _takeBackStepCountForRequester(requesterSide);
  }

  PieceColor get _humanAiTakeBackRequesterSide {
    assert(_usesLichessHumanAiToolbar);
    final List<Player> humanPlayers = GameController().gameInstance.players
        .where((Player player) => !player.isAi)
        .toList(growable: false);
    assert(
      humanPlayers.length == 1,
      'Human vs AI takeback requires exactly one human requester.',
    );
    return humanPlayers.single.color;
  }

  int _takeBackStepCountForRequester(PieceColor requesterSide) {
    assert(
      requesterSide == PieceColor.white || requesterSide == PieceColor.black,
    );
    final List<ExtMove> path = GameController().gameRecorder.currentPath;
    assert(path.isNotEmpty, 'Cannot take back without a move history.');

    final NativeMillRulesPort preview = _takeBackPreviewPort(path);
    try {
      // Undo until the requester is truly the side to act. This keeps capture
      // actions attached to the requester: if White made a mill and captured,
      // then Black replied, a Black request removes only Black's move, while a
      // White request removes Black's move and White's capture.
      for (int steps = 1; steps <= path.length; steps++) {
        preview.undo();
        final PieceColor sideAfterUndo = _pieceColorFromSeat(
          preview.snapshot.activeSeat,
        );
        if (sideAfterUndo == requesterSide) {
          return steps;
        }
      }
    } finally {
      preview.dispose();
    }

    assert(false, 'Move history does not contain the requester side.');
    throw StateError('Move history does not contain the requester side.');
  }

  NativeMillRulesPort _takeBackPreviewPort(List<ExtMove> path) {
    final NativeMillRulesPort port = NativeMillRulesPort(
      ruleSettings: DB().ruleSettings,
      generalSettings: DB().generalSettings,
    );

    try {
      final String? setupPosition = GameController().gameRecorder.setupPosition;
      if (setupPosition != null) {
        port.setFromFen(setupPosition);
      }

      for (final ExtMove move in path) {
        final GameAction? action = _legalActionForMove(port, move.move);
        assert(
          action != null,
          'Cannot replay ${move.move} while calculating requester takeback.',
        );
        port.apply(action!);
      }
      return port;
    } on Object {
      port.dispose();
      rethrow;
    }
  }

  GameAction? _legalActionForMove(NativeMillRulesPort port, String move) {
    for (final GameAction action in port.legalActions) {
      if (MillActionCodec.moveStringFrom(action) == move) {
        return action;
      }
    }
    return null;
  }

  PieceColor _pieceColorFromSeat(PlayerSeat seat) {
    assert(
      seat == PlayerSeat.first || seat == PlayerSeat.second,
      'Requester takeback requires a playable side, got $seat.',
    );
    return seat == PlayerSeat.first ? PieceColor.white : PieceColor.black;
  }

  Future<void> _takeBackFromRegularBottomBar(BuildContext context) async {
    if (GameController().gameInstance.gameMode == GameMode.humanVsLAN) {
      await _takeBackForRequesterFromRegularBottomBar(
        context,
        requesterSide: GameController().getLocalColor(),
      );
      return;
    }

    if (GameController().gameInstance.gameMode == GameMode.humanVsHuman) {
      _showHumanVsHumanTakeBackRequesterSheet(context);
      return;
    }

    await HistoryNavigator.takeBack(context, pop: false, toolbar: true);
  }

  Future<void> _stepBackFromRegularBottomBar(BuildContext context) async {
    if (GameController().gameInstance.gameMode == GameMode.humanVsLAN) {
      return;
    }
    await HistoryNavigator.takeBack(context, pop: false, toolbar: true);
  }

  Future<void> _takeBackForRequesterFromRegularBottomBar(
    BuildContext context, {
    required PieceColor requesterSide,
  }) async {
    final int steps = _takeBackStepCountForRequester(requesterSide);
    RecordingService()
        .recordEvent(RecordingEventType.toolbarAction, <String, dynamic>{
          'toolbar': 'regularBottom',
          'action': 'takeBack',
          'requester': requesterSide.name,
          'steps': steps,
        });
    await HistoryNavigator.takeBackN(context, steps, pop: false, toolbar: true);
  }

  void _showHumanVsHumanTakeBackRequesterSheet(BuildContext context) {
    assert(GameController().gameInstance.gameMode == GameMode.humanVsHuman);
    final S strings = S.of(context);
    showLichessActionSheet<void>(
      context: context,
      sheetKey: const Key('play_area_take_back_requester_sheet'),
      title: Text(strings.humanVsHumanTakeBackRequesterTitle),
      backgroundColor: _actionSheetBackground(context),
      foregroundColor: _actionSheetForeground(context),
      actions: <LichessActionSheetAction>[
        LichessActionSheetAction(
          key: const Key('play_area_take_back_requester_white'),
          leading: _TakeBackRequesterSwatch(
            color: DB().colorSettings.whitePieceColor,
          ),
          makeLabel: (BuildContext context) =>
              Text(strings.humanVsHumanTakeBackRequesterWhite),
          onPressed: () => unawaited(
            _takeBackForRequesterFromRegularBottomBar(
              context,
              requesterSide: PieceColor.white,
            ),
          ),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_take_back_requester_black'),
          leading: _TakeBackRequesterSwatch(
            color: DB().colorSettings.blackPieceColor,
          ),
          makeLabel: (BuildContext context) =>
              Text(strings.humanVsHumanTakeBackRequesterBlack),
          onPressed: () => unawaited(
            _takeBackForRequesterFromRegularBottomBar(
              context,
              requesterSide: PieceColor.black,
            ),
          ),
        ),
      ],
    );
  }

  bool get _canShowHintFromBottomBar {
    final PieceColor sideToMove = GameController().activeBoardView.sideToMove;
    return _usesLichessHumanAiToolbar &&
        _activePhase != Phase.gameOver &&
        (sideToMove == PieceColor.white || sideToMove == PieceColor.black) &&
        GameController().gameInstance.isHumanToMove &&
        !GameController().isEngineRunning &&
        !GameController().isEngineInDelay &&
        !AnalysisMode.isAnalyzing &&
        !_isHintSearching;
  }

  bool get _canResignFromRegularBottomBar {
    return !_usesLichessHumanAiToolbar &&
        !_isAnalysisMode &&
        GameController().gameRecorder.currentPath.length >= 2 &&
        _activePhase != Phase.ready &&
        _activePhase != Phase.gameOver;
  }

  bool get _isRegularGameOver {
    return !_usesLichessHumanAiToolbar &&
        !_isAnalysisMode &&
        _activePhase == Phase.gameOver;
  }

  bool get _isHumanAiGameOver {
    return _usesLichessHumanAiToolbar && _activePhase == Phase.gameOver;
  }

  bool get _canStepBackFromRegularBottomBar {
    return !_usesLichessHumanAiToolbar &&
        GameController().gameInstance.gameMode != GameMode.humanVsLAN &&
        GameController().gameRecorder.activeNode?.parent != null &&
        !GameController().isEngineRunning &&
        !GameController().isEngineInDelay;
  }

  bool get _canTakeBackFromRegularBottomBar {
    return !_usesLichessHumanAiToolbar &&
        GameController().gameRecorder.activeNode?.parent != null &&
        !GameController().isEngineRunning &&
        !GameController().isEngineInDelay;
  }

  bool get _canStepForwardFromRegularBottomBar {
    return !_usesLichessHumanAiToolbar &&
        GameController().gameInstance.gameMode != GameMode.humanVsLAN &&
        (GameController().gameRecorder.activeNode ??
                GameController().gameRecorder.pgnRoot)
            .children
            .isNotEmpty &&
        !GameController().isEngineRunning &&
        !GameController().isEngineInDelay;
  }

  bool get _shouldShowRegularClockControl {
    return !_usesLichessHumanAiToolbar &&
        !_isAnalysisMode &&
        GameController().gameInstance.gameMode == GameMode.humanVsHuman &&
        DB().generalSettings.humanMoveTime > 0;
  }

  VoidCallback? _regularClockControlAction(PlayerTimerStatus status) {
    if (!_shouldShowRegularClockControl ||
        _activePhase == Phase.gameOver ||
        status == PlayerTimerStatus.stopped) {
      return null;
    }

    return switch (status) {
      PlayerTimerStatus.running => PlayerTimer().pause,
      PlayerTimerStatus.paused => PlayerTimer().resume,
      PlayerTimerStatus.stopped => null,
    };
  }

  void _transformActiveBoard(
    MillBoardTransformAction action, {
    required S strings,
    GameSession? session,
  }) {
    final bool transformed = GameController().transformActiveLocalGame(
      action.type,
    );
    if (transformed) {
      setState(() {
        _isBoardFlipped = false;
      });
      if (_usesLichessHumanAiToolbar &&
          GameController().gameInstance.isAiSideToMove) {
        unawaited(
          GameController().engineToGo(
            context,
            isMoveNow: false,
            session: session,
          ),
        );
      }
    }
    assert(
      rootScaffoldMessengerKey.currentState != null,
      'Board transform feedback requires the root scaffold messenger.',
    );
    rootScaffoldMessengerKey.currentState!.showSnackBarClear(
      transformed ? strings.transformed : strings.cannotTransform,
    );
  }

  List<LichessActionSheetAction> _buildBoardTransformActions({
    required String keyPrefix,
    required S strings,
    GameSession? session,
  }) {
    return <LichessActionSheetAction>[
      for (final MillBoardTransformAction action in millBoardTransformActions)
        LichessActionSheetAction(
          key: Key('${keyPrefix}_${action.id}'),
          leading: Icon(action.icon),
          makeLabel: (BuildContext context) => Text(action.label(strings)),
          onPressed: () =>
              _transformActiveBoard(action, strings: strings, session: session),
        ),
    ];
  }

  void _showBoardTransformSheet(
    BuildContext context, {
    required Key sheetKey,
    required String keyPrefix,
    S? strings,
    GameSession? session,
  }) {
    if (!mounted) {
      return;
    }
    final BuildContext sheetContext = _stableActionContext(context);
    final S effectiveStrings = strings ?? S.of(sheetContext);
    showLichessActionSheet<void>(
      context: sheetContext,
      sheetKey: sheetKey,
      title: Text(effectiveStrings.flipBoard),
      backgroundColor: _actionSheetBackground(sheetContext),
      foregroundColor: _actionSheetForeground(sheetContext),
      actions: _buildBoardTransformActions(
        keyPrefix: keyPrefix,
        strings: effectiveStrings,
        session: session,
      ),
    );
  }

  Future<void> _moveNowFromGameMenu(
    BuildContext context, {
    required String toolbar,
    required MoveNowMessages messages,
    GameSession? session,
  }) async {
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': toolbar, 'action': 'moveNow'},
    );
    await GameController().moveNow(
      context,
      messages: messages,
      session: session,
    );
  }

  bool get _shouldShowMoveNowMenuAction {
    final GameMode mode = GameController().gameInstance.gameMode;
    return mode == GameMode.humanVsAi || mode == GameMode.aiVsAi;
  }

  Future<void> _showResignConfirmation(BuildContext context) async {
    assert(_usesLichessHumanAiToolbar);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(S.of(dialogContext).confirmResignation),
          content: Text(S.of(dialogContext).areYouSureYouWantToResignThisGame),
          actions: <Widget>[
            TextButton(
              key: const Key('play_area_resign_cancel_button'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(S.of(dialogContext).cancel),
            ),
            TextButton(
              key: const Key('play_area_resign_confirm_button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(S.of(dialogContext).resign),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'lichessBottom', 'action': 'resign'},
    );
    GameController().requestResignation();
  }

  Future<void> _takeBackFromBottomBar(BuildContext context) async {
    assert(_usesLichessHumanAiToolbar);
    final int steps = _humanAiTakeBackStepCount;
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{
        'toolbar': 'lichessBottom',
        'action': 'takeBack',
        'steps': steps,
      },
    );
    await HistoryNavigator.takeBackN(context, steps, pop: false, toolbar: true);
  }

  Future<void> _showHintFromBottomBar(BuildContext context) async {
    assert(_usesLichessHumanAiToolbar);
    assert(!_isHintSearching, 'Hint search is already in progress.');

    setState(() {
      _isHintSearching = true;
    });
    try {
      RecordingService().recordEvent(
        RecordingEventType.toolbarAction,
        <String, dynamic>{'toolbar': 'lichessBottom', 'action': 'hint'},
      );
      await AnalysisService.showBestMoveHint(context);
    } finally {
      if (mounted) {
        setState(() {
          _isHintSearching = false;
        });
      }
    }
  }

  Future<void> _requestNewGameFromBottomBar(NavigatorState navigator) async {
    assert(_usesLichessHumanAiToolbar);
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'lichessBottom', 'action': 'newGame'},
    );
    await GameOptionsModal.showHumanAiNewGameSheet(navigator.context);
  }

  Future<void> _showRegularResignConfirmation(BuildContext context) async {
    assert(!_usesLichessHumanAiToolbar);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(S.of(dialogContext).confirmResignation),
          content: Text(S.of(dialogContext).areYouSureYouWantToResignThisGame),
          actions: <Widget>[
            TextButton(
              key: const Key('play_area_regular_resign_cancel_button'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(S.of(dialogContext).cancel),
            ),
            TextButton(
              key: const Key('play_area_regular_resign_confirm_button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(S.of(dialogContext).resign),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'regularBottom', 'action': 'resign'},
    );
    GameController().requestResignation();
  }

  void _showRegularGameResult() {
    assert(_isRegularGameOver);
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'regularBottom', 'action': 'showResult'},
    );
    GameController().gameResultNotifier.showResult(force: true);
  }

  void _showHumanAiGameResult() {
    assert(_isHumanAiGameOver);
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'lichessBottom', 'action': 'showResult'},
    );
    GameController().gameResultNotifier.showResult(force: true);
  }

  void _toggleAnalysisEngineLines() {
    assert(_isAnalysisMode, 'Engine line visibility is analysis-mode only.');
    RecordingService()
        .recordEvent(RecordingEventType.toolbarAction, <String, dynamic>{
          'toolbar': 'analysisMenu',
          'action': 'toggleEngineLines',
          'visible': !AnalysisMode.showEngineLines,
        });
    AnalysisMode.toggleEngineLines();
  }

  Future<void> _showAnalysisSettingsSheet(
    BuildContext context, {
    required S strings,
  }) {
    assert(_isAnalysisMode, 'Analysis settings are analysis-mode only.');
    final BuildContext sheetContext = _stableActionContext(context);
    return showDialog<void>(
      context: sheetContext,
      builder: (BuildContext dialogContext) {
        final ThemeData theme = Theme.of(dialogContext);
        final ColorScheme colorScheme = theme.colorScheme;
        return Dialog(
          key: const Key('play_area_analysis_settings_sheet'),
          backgroundColor: colorScheme.surfaceContainerLow,
          surfaceTintColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(MediaQuery.sizeOf(dialogContext).width, 500),
            ),
            child: ValueListenableBuilder<bool>(
              valueListenable: AnalysisMode.stateNotifier,
              builder: (BuildContext context, _, Widget? child) {
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                strings.settings,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                            IconButton(
                              key: const Key(
                                'play_area_analysis_settings_close',
                              ),
                              tooltip: strings.close,
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      LichessListSection(
                        header: Text(strings.engine),
                        cardKey: const Key(
                          'play_area_analysis_settings_engine_card',
                        ),
                        children: <Widget>[
                          SwitchListTile.adaptive(
                            key: const Key(
                              'play_area_analysis_settings_engine_lines',
                            ),
                            secondary: const Icon(Icons.subtitles_outlined),
                            title: Text(strings.showEngineLines),
                            value: AnalysisMode.showEngineLines,
                            onChanged: (bool value) {
                              RecordingService().recordEvent(
                                RecordingEventType.toolbarAction,
                                <String, dynamic>{
                                  'toolbar': 'analysisSettings',
                                  'action': 'setEngineLines',
                                  'visible': value,
                                },
                              );
                              AnalysisMode.setShowEngineLines(value);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showRegularGameMenu() {
    assert(!_usesLichessHumanAiToolbar);
    final BuildContext hostContext = context;
    final BuildContext actionContext = _stableActionContext(hostContext);
    final S strings = S.of(hostContext);
    final MoveNowMessages moveNowMessages = MoveNowMessages.of(hostContext);
    final NavigatorState hostNavigator = Navigator.of(hostContext);
    final GameSession? hostSession =
        GameSessionScope.sessionOf(hostContext) ??
        GameController().activeNativeMillSession;
    final NativeMillGameSession? nativeHostSession =
        hostSession is NativeMillGameSession
        ? hostSession
        : GameController().activeNativeMillSession;
    assert(
      !_isAnalysisMode || nativeHostSession != null,
      'Analysis menu requires a native Mill session.',
    );
    showLichessActionSheet<void>(
      context: hostContext,
      sheetKey: const Key('play_area_regular_game_menu_sheet'),
      backgroundColor: _actionSheetBackground(hostContext),
      foregroundColor: _actionSheetForeground(hostContext),
      actions: <LichessActionSheetAction>[
        LichessActionSheetAction(
          key: const Key('play_area_regular_game_menu_flip_board'),
          leading: const Icon(Icons.flip_camera_android_outlined),
          trailing: const Icon(Icons.chevron_right),
          makeLabel: (BuildContext context) => Text(S.of(context).flipBoard),
          onPressed: () => _showBoardTransformSheet(
            actionContext,
            sheetKey: const Key('play_area_regular_board_transform_sheet'),
            keyPrefix: 'play_area_regular_board_transform',
            strings: strings,
            session: hostSession,
          ),
        ),
        if (!_isAnalysisMode)
          LichessActionSheetAction(
            key: const Key('play_area_toolbar_item_game'),
            leading: const Icon(Icons.add_circle_outline),
            makeLabel: (BuildContext context) => Text(S.of(context).newGame),
            onPressed: () => _requestRegularNewGame(hostNavigator),
          ),
        if (!_isAnalysisMode)
          LichessActionSheetAction(
            key: const Key('play_area_toolbar_item_move'),
            leading: const Icon(Icons.format_list_numbered),
            makeLabel: (BuildContext context) => Text(S.of(context).moveList),
            onPressed: () => _openMovesWithNavigator(hostNavigator),
          ),
        if (_isAnalysisMode)
          LichessActionSheetAction(
            key: const Key('play_area_regular_game_menu_analysis_settings'),
            leading: const Icon(Icons.settings_outlined),
            trailing: const Icon(Icons.chevron_right),
            makeLabel: (BuildContext context) => Text(strings.settings),
            onPressed: () =>
                _showAnalysisSettingsSheet(actionContext, strings: strings),
          ),
        if (_isAnalysisMode)
          LichessActionSheetAction(
            key: const Key('play_area_regular_game_menu_toggle_engine_lines'),
            leading: Icon(
              AnalysisMode.showEngineLines
                  ? Icons.subtitles_outlined
                  : Icons.subtitles_off_outlined,
            ),
            makeLabel: (BuildContext context) => Text(
              AnalysisMode.showEngineLines
                  ? strings.hideEngineLines
                  : strings.showEngineLines,
            ),
            onPressed: _toggleAnalysisEngineLines,
          ),
        if (_isAnalysisMode)
          LichessActionSheetAction(
            key: const Key('play_area_regular_game_menu_board_editor'),
            leading: const Icon(Icons.dashboard_customize_outlined),
            makeLabel: (BuildContext context) =>
                Text(S.of(context).boardEditor),
            onPressed: _openBoardEditorFromAnalysis,
          ),
        if (_isAnalysisMode && nativeHostSession != null)
          LichessActionSheetAction(
            key: const Key('play_area_regular_game_menu_continue_from_here'),
            leading: const Icon(Icons.play_circle_outline),
            trailing: const Icon(Icons.chevron_right),
            makeLabel: (BuildContext context) =>
                Text(S.of(context).continueFromHere),
            onPressed: () => _showContinueFromHereMenu(
              actionContext,
              session: nativeHostSession,
              navigator: hostNavigator,
              strings: strings,
            ),
          ),
        if (_isAnalysisMode)
          LichessActionSheetAction(
            key: const Key('play_area_regular_game_menu_share_export'),
            leading: const Icon(Icons.ios_share_outlined),
            trailing: const Icon(Icons.chevron_right),
            makeLabel: (BuildContext context) => Text(strings.shareAndExport),
            onPressed: () =>
                _showAnalysisShareExportMenu(actionContext, strings: strings),
          ),
        if (_canStepBackFromRegularBottomBar)
          LichessActionSheetAction(
            key: const Key('play_area_regular_game_menu_previous'),
            leading: const Icon(CupertinoIcons.chevron_back),
            makeLabel: (BuildContext context) => Text(S.of(context).previous),
            onPressed: () =>
                unawaited(_stepBackFromRegularBottomBar(actionContext)),
          ),
        if (_canStepForwardFromRegularBottomBar)
          LichessActionSheetAction(
            key: const Key('play_area_regular_game_menu_next'),
            leading: const Icon(CupertinoIcons.chevron_forward),
            makeLabel: (BuildContext context) =>
                Text(S.of(context).stepForward),
            onPressed: () => unawaited(
              HistoryNavigator.stepForward(
                actionContext,
                pop: false,
                toolbar: true,
              ),
            ),
          ),
        if (_shouldShowMoveNowMenuAction)
          LichessActionSheetAction(
            key: const Key('play_area_regular_game_menu_move_now'),
            leading: const Icon(FluentIcons.play_24_regular),
            makeLabel: (BuildContext context) => Text(S.of(context).moveNow),
            onPressed: () => unawaited(
              _moveNowFromGameMenu(
                actionContext,
                toolbar: 'regularBottom',
                messages: moveNowMessages,
                session: hostSession,
              ),
            ),
          ),
        if (_shouldShowAiChatMenuAction)
          LichessActionSheetAction(
            key: const Key('play_area_regular_game_menu_ai_chat'),
            leading: const Icon(FluentIcons.chat_24_regular),
            makeLabel: (BuildContext context) =>
                Text(S.of(context).aiChatButtonTooltip),
            onPressed: () => _showAiChatDialog(actionContext),
          ),
        if (_canTakeBackFromRegularBottomBar)
          LichessActionSheetAction(
            key: const Key('play_area_regular_game_menu_take_back'),
            leading: const Icon(CupertinoIcons.arrow_uturn_left),
            makeLabel: (BuildContext context) => Text(S.of(context).takeBack),
            onPressed: () =>
                unawaited(_takeBackFromRegularBottomBar(actionContext)),
          ),
        if (_isRegularGameOver)
          LichessActionSheetAction(
            key: const Key('play_area_regular_game_menu_result'),
            leading: const Icon(Icons.info_outline),
            makeLabel: (BuildContext context) => Text(S.of(context).results),
            onPressed: _showRegularGameResult,
          )
        else if (_canResignFromRegularBottomBar)
          LichessActionSheetAction(
            key: const Key('play_area_regular_game_menu_resign'),
            leading: const Icon(CupertinoIcons.flag),
            makeLabel: (BuildContext context) => Text(S.of(context).resign),
            onPressed: () =>
                unawaited(_showRegularResignConfirmation(actionContext)),
          ),
        LichessActionSheetAction(
          key: const Key('play_area_toolbar_item_options'),
          leading: const Icon(Icons.settings_outlined),
          makeLabel: (BuildContext context) => Text(S.of(context).options),
          onPressed: () => _navigateToSettings(actionContext),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_toolbar_item_info'),
          leading: const Icon(Icons.info_outline),
          makeLabel: (BuildContext context) => Text(S.of(context).info),
          onPressed: () => _openDialog(actionContext, const InfoDialog()),
        ),
      ],
    );
  }

  void _showHumanAiGameMenu() {
    assert(_usesLichessHumanAiToolbar);
    final BuildContext hostContext = context;
    final BuildContext actionContext = _stableActionContext(hostContext);
    final S strings = S.of(hostContext);
    final MoveNowMessages moveNowMessages = MoveNowMessages.of(hostContext);
    final NavigatorState hostNavigator = Navigator.of(hostContext);
    final GameSession? hostSession =
        GameSessionScope.sessionOf(hostContext) ??
        GameController().activeNativeMillSession;
    showLichessActionSheet<void>(
      context: hostContext,
      sheetKey: const Key('play_area_game_menu_sheet'),
      backgroundColor: _actionSheetBackground(hostContext),
      foregroundColor: _actionSheetForeground(hostContext),
      actions: <LichessActionSheetAction>[
        LichessActionSheetAction(
          key: const Key('play_area_game_menu_flip_board'),
          leading: const Icon(Icons.flip_camera_android_outlined),
          trailing: const Icon(Icons.chevron_right),
          makeLabel: (BuildContext context) => Text(S.of(context).flipBoard),
          onPressed: () => _showBoardTransformSheet(
            actionContext,
            sheetKey: const Key('play_area_board_transform_sheet'),
            keyPrefix: 'play_area_board_transform',
            strings: strings,
            session: hostSession,
          ),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_game_menu_move_list'),
          leading: const Icon(Icons.format_list_numbered),
          makeLabel: (BuildContext context) => Text(S.of(context).moveList),
          onPressed: () => _openMovesWithNavigator(hostNavigator),
        ),
        if (_shouldShowMoveNowMenuAction)
          LichessActionSheetAction(
            key: const Key('play_area_game_menu_move_now'),
            leading: const Icon(FluentIcons.play_24_regular),
            makeLabel: (BuildContext context) => Text(S.of(context).moveNow),
            onPressed: () => unawaited(
              _moveNowFromGameMenu(
                actionContext,
                toolbar: 'lichessBottom',
                messages: moveNowMessages,
                session: hostSession,
              ),
            ),
          ),
        if (_shouldShowAiChatMenuAction)
          LichessActionSheetAction(
            key: const Key('play_area_game_menu_ai_chat'),
            leading: const Icon(FluentIcons.chat_24_regular),
            makeLabel: (BuildContext context) =>
                Text(S.of(context).aiChatButtonTooltip),
            onPressed: () => _showAiChatDialog(actionContext),
          ),
        if (_isHumanAiGameOver)
          LichessActionSheetAction(
            key: const Key('play_area_game_menu_result'),
            leading: const Icon(Icons.info_outline),
            makeLabel: (BuildContext context) => Text(S.of(context).results),
            onPressed: _showHumanAiGameResult,
          )
        else if (_canResignFromBottomBar)
          LichessActionSheetAction(
            key: const Key('play_area_game_menu_resign'),
            leading: const Icon(CupertinoIcons.flag),
            makeLabel: (BuildContext context) => Text(S.of(context).resign),
            onPressed: () => unawaited(_showResignConfirmation(actionContext)),
          ),
        LichessActionSheetAction(
          key: const Key('play_area_game_menu_new_game'),
          leading: const Icon(Icons.add_circle_outline),
          makeLabel: (BuildContext context) => Text(S.of(context).newGame),
          onPressed: () =>
              unawaited(_requestNewGameFromBottomBar(hostNavigator)),
        ),
      ],
    );
  }

  /// Builds a list of toolbar items by expanding each [ToolbarItem].
  List<Widget> _buildToolbarItems(
    BuildContext context,
    List<ToolbarItem> items,
  ) {
    return items.map((ToolbarItem item) => Expanded(child: item)).toList();
  }

  /// Builds the move modal bottom sheet.
  Widget _buildMoveModal(BuildContext context) {
    if (DB().displaySettings.isHistoryNavigationToolbarShown) {
      // Delay the opening to the next frame, then show the MoveListDialog.
      Future<void>.delayed(const Duration(milliseconds: 100), () {
        if (context.mounted) {
          _openDialog(context, const MoveListDialog());
        }
      });
      // Placeholder to keep the function signature uniform.
      return const SizedBox.shrink();
    }
    return MoveOptionsModal(mainContext: context);
  }

  /// Retrieves the history navigation toolbar items.
  List<ToolbarItem> _getHistoryNavToolbarItems(BuildContext context) {
    final String takeBackAccepted = S.of(context).takeBackAccepted;
    final String takeBackRejected = S.of(context).takeBackRejected;
    return <ToolbarItem>[
      ToolbarItem(
        key: const Key('play_area_history_nav_take_back_all'),
        child: Icon(
          FluentIcons.arrow_previous_24_regular,
          semanticLabel: S.of(context).takeBackAll,
        ),
        onPressed: () =>
            HistoryNavigator.takeBackAll(context, pop: false, toolbar: true),
      ),
      ToolbarItem(
        key: const Key('play_area_history_nav_take_back'),
        child: Icon(
          FluentIcons.chevron_left_24_regular,
          semanticLabel: S.of(context).takeBack,
        ),
        onPressed: () async {
          // If the game is humanVsLAN, request a LAN take-back instead.
          if (GameController().gameInstance.gameMode == GameMode.humanVsLAN) {
            final ScaffoldMessengerState messenger = ScaffoldMessenger.of(
              context,
            );
            final bool accepted = await GameController().requestLanTakeBack(
              _lanTakeBackStepCount,
            );
            if (!mounted) {
              return;
            }
            if (accepted) {
              messenger.showSnackBar(SnackBar(content: Text(takeBackAccepted)));
            } else {
              messenger.showSnackBar(SnackBar(content: Text(takeBackRejected)));
            }
          } else {
            HistoryNavigator.takeBack(context, pop: false, toolbar: true);
          }
        },
      ),
      if (!Constants.isSmallScreen(context))
        ToolbarItem(
          key: const Key('play_area_history_nav_move_now'),
          onPressed: () {
            RecordingService().recordEvent(
              RecordingEventType.toolbarAction,
              <String, dynamic>{'toolbar': 'history', 'action': 'moveNow'},
            );
            GameController().moveNow(context);
          },
          child: Icon(
            FluentIcons.play_24_regular,
            semanticLabel: S.of(context).moveNow,
          ),
        ),
      ToolbarItem(
        key: const Key('play_area_history_nav_step_forward'),
        child: Icon(
          FluentIcons.chevron_right_24_regular,
          semanticLabel: S.of(context).stepForward,
        ),
        onPressed: () =>
            HistoryNavigator.stepForward(context, pop: false, toolbar: true),
      ),
      ToolbarItem(
        key: const Key('play_area_history_nav_step_forward_all'),
        child: Icon(
          FluentIcons.arrow_next_24_regular,
          semanticLabel: S.of(context).stepForwardAll,
        ),
        onPressed: () =>
            HistoryNavigator.stepForwardAll(context, pop: false, toolbar: true),
      ),
    ];
  }

  /// Returns a string of '●' characters based on [count].
  String _getPiecesText(int count) {
    return "●" * count;
  }

  /// Builds the row displaying the piece count in hand (if enabled).
  Widget _buildPieceCountRow() {
    final MillBoardView view = GameController().activeBoardView;
    final bool aiMovesFirst = DB().generalSettings.aiMovesFirst;
    final PieceColor humanColor = aiMovesFirst
        ? PieceColor.black
        : PieceColor.white;
    final PieceColor aiColor = aiMovesFirst
        ? PieceColor.white
        : PieceColor.black;
    final int humanInHand = view.pieceInHandCountFor(humanColor);
    final int aiOnBoard = view.pieceOnBoardCountFor(aiColor);
    final int aiInHand = view.pieceInHandCountFor(aiColor);
    return Row(
      key: const Key('play_area_piece_count_row'),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Semantics(
          label: S
              .of(context)
              .inHand(
                aiMovesFirst ? S.of(context).player2 : S.of(context).player1,
                humanInHand,
              ),
          child: Text(
            _getPiecesText(humanInHand),
            key: const Key('play_area_piece_count_text_hand'),
            style: TextStyle(
              color: aiMovesFirst
                  ? DB().colorSettings.blackPieceColor
                  : DB().colorSettings.whitePieceColor,
              shadows: const <Shadow>[
                Shadow(
                  offset: Offset(1.0, 1.0),
                  blurRadius: 3.0,
                  color: Color.fromARGB(255, 128, 128, 128),
                ),
              ],
            ),
          ),
        ),
        Semantics(
          label: S.of(context).welcome,
          child: Text(
            _getPiecesText(
              DB().ruleSettings.piecesCount - aiInHand - aiOnBoard,
            ),
            key: const Key('play_area_piece_count_text_remaining'),
            style: TextStyle(
              color: aiMovesFirst
                  ? DB().colorSettings.whitePieceColor.withValues(alpha: 0.8)
                  : DB().colorSettings.blackPieceColor.withValues(alpha: 0.8),
              shadows: const <Shadow>[
                Shadow(
                  offset: Offset(1.0, 1.0),
                  blurRadius: 3.0,
                  color: Color.fromARGB(255, 128, 128, 128),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Builds the row displaying the removed piece count (if enabled).
  Widget _buildRemovedPieceCountRow() {
    final MillBoardView view = GameController().activeBoardView;
    final bool aiMovesFirst = DB().generalSettings.aiMovesFirst;
    final PieceColor humanColor = aiMovesFirst
        ? PieceColor.black
        : PieceColor.white;
    final PieceColor aiColor = aiMovesFirst
        ? PieceColor.white
        : PieceColor.black;
    final int humanOnBoard = view.pieceOnBoardCountFor(humanColor);
    final int humanInHand = view.pieceInHandCountFor(humanColor);
    final int aiInHand = view.pieceInHandCountFor(aiColor);
    return Row(
      key: const Key('play_area_removed_piece_count_row'),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Semantics(
          label: S.of(context).welcome,
          child: Text(
            _getPiecesText(
              DB().ruleSettings.piecesCount - humanInHand - humanOnBoard,
            ),
            key: const Key('play_area_removed_piece_count_text_remaining'),
            style: TextStyle(
              color: aiMovesFirst
                  ? DB().colorSettings.blackPieceColor.withValues(alpha: 0.8)
                  : DB().colorSettings.whitePieceColor.withValues(alpha: 0.8),
              shadows: const <Shadow>[
                Shadow(
                  offset: Offset(1.0, 1.0),
                  blurRadius: 3.0,
                  color: Color.fromARGB(255, 128, 128, 128),
                ),
              ],
            ),
          ),
        ),
        Semantics(
          label: S
              .of(context)
              .inHand(
                aiMovesFirst ? S.of(context).player1 : S.of(context).player2,
                aiInHand,
              ),
          child: Text(
            _getPiecesText(aiInHand),
            key: const Key('play_area_removed_piece_count_text_hand'),
            style: TextStyle(
              color: aiMovesFirst
                  ? DB().colorSettings.whitePieceColor
                  : DB().colorSettings.blackPieceColor,
              shadows: const <Shadow>[
                Shadow(
                  offset: Offset(1.0, 1.0),
                  blurRadius: 3.0,
                  color: Color.fromARGB(255, 128, 128, 128),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBoardScreenshot() {
    final GameMode mode = GameController().gameInstance.gameMode;
    final bool isGameSurface =
        mode != GameMode.setupPosition && mode != GameMode.puzzle;
    final bool showAdvantageIndicator =
        isGameSurface &&
        DB().displaySettings.isPositionalAdvantageIndicatorShown;
    final int advantageValue = advantageData.isEmpty
        ? _getCurrentAdvantageValue()
        : advantageData.last;
    return NativeScreenshot(
      key: const Key('play_area_native_screenshot'),
      controller: ScreenshotService.screenshotController,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Container(
            key: const Key('play_area_game_board_container'),
            alignment: Alignment.center,
            child: RotatedBox(
              key: const Key('play_area_board_orientation'),
              quarterTurns: _isBoardFlipped ? 2 : 0,
              child: widget.child,
            ),
          ),
          if (showAdvantageIndicator)
            PositionedDirectional(
              key: const Key('play_area_advantage_indicator_positioned'),
              start: -_kAdvantageIndicatorWidth - _kAdvantageIndicatorGap,
              top: 0,
              bottom: 0,
              width: _kAdvantageIndicatorWidth,
              child: _PositionalAdvantageIndicator(value: advantageValue),
            ),
        ],
      ),
    );
  }

  Widget _buildMoveListForHumanAi(BuildContext context) {
    return _withMoveListTopInset(
      context,
      const _InlineMoveList(
        key: Key('play_area_human_ai_move_list'),
        wrapKey: Key('play_area_human_ai_move_list_wrap'),
        roundKeyPrefix: 'play_area_human_ai_round_',
        moveKeyPrefix: 'play_area_human_ai_move_',
        layout: _InlineMoveListLayout.horizontal,
        groupByRound: true,
      ),
    );
  }

  Widget _buildMoveListForRegularGame(BuildContext context) {
    return _withMoveListTopInset(
      context,
      _InlineMoveList(
        key: const Key('play_area_regular_move_list'),
        wrapKey: const Key('play_area_regular_move_list_wrap'),
        roundKeyPrefix: 'play_area_regular_round_',
        moveKeyPrefix: 'play_area_regular_move_',
        onMoveTap: (BuildContext context, PgnNode<ExtMove> node) {
          return HistoryNavigator.gotoNode(context, node, pop: false);
        },
        showMovePreview: true,
        layout: _InlineMoveListLayout.horizontal,
        groupByRound: true,
      ),
    );
  }

  Widget _buildHumanAiMainContent({
    required BuildContext context,
    required bool showPieceCountRows,
  }) {
    final bool showAdvantageGraph = _shouldShowAdvantageGraph(
      isGameSurface: true,
    );

    return SizedBox(
      key: const Key('play_area_human_ai_main_content'),
      child: SafeArea(
        top: MediaQuery.of(context).orientation == Orientation.portrait,
        bottom: false,
        right: false,
        left: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Widget moveList = _buildMoveListForHumanAi(context);
            const Widget topTable = _HumanAiPlayerPanel(
              key: Key('play_area_human_ai_robot_panel'),
              isRobot: true,
            );
            final List<Widget> boardChildren = <Widget>[
              if (showPieceCountRows)
                _isBoardFlipped
                    ? _buildRemovedPieceCountRow()
                    : _buildPieceCountRow(),
              SizedBox.square(
                dimension: constraints.maxWidth,
                child: _buildBoardScreenshot(),
              ),
              if (showPieceCountRows)
                _isBoardFlipped
                    ? _buildPieceCountRow()
                    : _buildRemovedPieceCountRow(),
            ];
            final List<Widget> bottomChildren = <Widget>[
              const _HumanAiPlayerPanel(
                key: Key('play_area_human_ai_player_panel'),
                isRobot: false,
              ),
              if (showAdvantageGraph)
                SizedBox(
                  key: const Key('play_area_advantage_graph'),
                  height: 112,
                  width: double.infinity,
                  child: CustomPaint(
                    key: const Key('play_area_custom_paint_advantage_graph'),
                    painter: AdvantageGraphPainter(advantageData),
                  ),
                ),
            ];

            final double moveListHeight = _inlineMoveListHeightForRoute(
              context,
            );
            final double boardRowsHeight = showPieceCountRows
                ? _pieceRowsHeightForLayout(context)
                : 0;
            final double boardBlockHeight =
                constraints.maxWidth + boardRowsHeight;
            final double topPanelHeight = _humanAiPlayerPanelHeightForLayout(
              context,
            );
            final double bottomPanelHeight =
                _humanAiPlayerPanelHeightForLayout(context) +
                (showAdvantageGraph ? 112 : 0);
            final double estimatedRequiredHeight =
                moveListHeight +
                boardBlockHeight +
                topPanelHeight +
                bottomPanelHeight;
            final bool canBalance =
                constraints.hasBoundedHeight &&
                constraints.maxHeight >=
                    estimatedRequiredHeight + _kBalancedLayoutSafetyMargin;

            if (canBalance) {
              final double freeHeight = math.max(
                0,
                constraints.maxHeight - estimatedRequiredHeight,
              );
              final double topSpacerHeight = freeHeight * 0.42;
              final double bottomSpacerHeight = freeHeight - topSpacerHeight;
              return SizedBox(
                height: constraints.maxHeight,
                child: Column(
                  key: const Key('play_area_human_ai_column'),
                  children: <Widget>[
                    moveList,
                    SizedBox(
                      height: topPanelHeight + topSpacerHeight,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: topTable,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: boardChildren,
                    ),
                    SizedBox(
                      height: bottomPanelHeight + bottomSpacerHeight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: bottomChildren,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return SingleChildScrollView(
              key: const Key('play_area_human_ai_scroll_view'),
              child: Column(
                key: const Key('play_area_human_ai_column'),
                children: <Widget>[
                  moveList,
                  topTable,
                  ...boardChildren,
                  ...bottomChildren,
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHumanAiBottomBar(BuildContext context) {
    return ValueListenableBuilder<bool>(
      key: const Key('play_area_lichess_bottom_bar_builder'),
      valueListenable: AnalysisMode.stateNotifier,
      builder: (BuildContext context, _, _) {
        return _LichessGameBottomBar(
          onMenuPressed: _showHumanAiGameMenu,
          onResignOrResultPressed: _isHumanAiGameOver
              ? _showHumanAiGameResult
              : _canResignFromBottomBar
              ? () => _showResignConfirmation(context)
              : null,
          onTakeBackPressed: _canTakeBackFromBottomBar
              ? () => _takeBackFromBottomBar(context)
              : null,
          onHintPressed: _canShowHintFromBottomBar
              ? () => _showHintFromBottomBar(context)
              : null,
          isShowingResult: _isHumanAiGameOver,
          isHintHighlighted: AnalysisMode.isHint,
        );
      },
    );
  }

  Widget _buildRegularBottomBar(BuildContext context) {
    return ValueListenableBuilder<int>(
      key: const Key('play_area_regular_bottom_bar_builder'),
      valueListenable: GameController().gameRecorder.moveCountNotifier,
      builder: (BuildContext context, _, _) {
        return ValueListenableBuilder<PlayerTimerStatus>(
          valueListenable: PlayerTimer().statusNotifier,
          builder: (BuildContext context, PlayerTimerStatus status, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: AnalysisMode.stateNotifier,
              builder: (BuildContext context, _, _) {
                return _RegularGameBottomBar(
                  onMenuPressed: _showRegularGameMenu,
                  onResignOrResultPressed: _isRegularGameOver
                      ? _showRegularGameResult
                      : _canResignFromRegularBottomBar
                      ? () => _showRegularResignConfirmation(context)
                      : null,
                  onAnalyzePressed: _isAnalysisMode
                      ? () => unawaited(AnalysisService.toggle(context))
                      : null,
                  onAnalyzeLongPressed: _isAnalysisMode
                      ? () => unawaited(
                          _showAnalysisSettingsSheet(
                            context,
                            strings: S.of(context),
                          ),
                        )
                      : null,
                  showClockControl: _shouldShowRegularClockControl,
                  isClockPaused: status == PlayerTimerStatus.paused,
                  isAnalysisMode: _isAnalysisMode,
                  isAnalysisHighlighted: AnalysisMode.isFullAnalysis,
                  isShowingResult: _isRegularGameOver,
                  onClockPressed: _regularClockControlAction(status),
                  onTakeBackPressed: _canTakeBackFromRegularBottomBar
                      ? () => _takeBackFromRegularBottomBar(context)
                      : null,
                  onPreviousPressed:
                      _isAnalysisMode && _canStepBackFromRegularBottomBar
                      ? () => unawaited(_stepBackFromRegularBottomBar(context))
                      : null,
                  onNextPressed:
                      _isAnalysisMode && _canStepForwardFromRegularBottomBar
                      ? () => unawaited(
                          HistoryNavigator.stepForward(
                            context,
                            pop: false,
                            toolbar: true,
                          ),
                        )
                      : null,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildAnalysisMainContent({
    required BuildContext context,
    required bool showPieceCountRows,
  }) {
    return ValueListenableBuilder<bool>(
      valueListenable: AnalysisMode.stateNotifier,
      builder: (BuildContext context, _, _) {
        final bool hasEngineLinesSlot =
            AnalysisMode.showEngineLines &&
            (AnalysisMode.isAnalyzing ||
                (AnalysisMode.isFullAnalysis &&
                    AnalysisMode.analysisResults.isNotEmpty));

        return SafeArea(
          top: MediaQuery.of(context).orientation == Orientation.portrait,
          bottom: false,
          right: false,
          left: false,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double maxHeight = constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : MediaQuery.sizeOf(context).height;
              final double engineLinesReserve = hasEngineLinesSlot
                  ? _kAnalysisEngineLinesReserveHeight
                  : 0;
              const double tabPanelMinHeight = 174;
              final double pieceRowsHeight = showPieceCountRows
                  ? _pieceRowsHeightForLayout(context)
                  : AppTheme.boardMargin * 2;
              final double boardHeightBudget =
                  maxHeight -
                  engineLinesReserve -
                  tabPanelMinHeight -
                  pieceRowsHeight -
                  _kBalancedLayoutSafetyMargin;
              final double boardSize = math.max(
                0,
                math.min(constraints.maxWidth, boardHeightBudget),
              );

              return Column(
                key: const Key('play_area_analysis_column'),
                children: <Widget>[
                  _buildAnalysisEngineLines(context),
                  if (showPieceCountRows)
                    _isBoardFlipped
                        ? _buildRemovedPieceCountRow()
                        : _buildPieceCountRow()
                  else
                    const SizedBox(height: AppTheme.boardMargin),
                  SizedBox.square(
                    key: const Key('play_area_analysis_board'),
                    dimension: boardSize,
                    child: _buildBoardScreenshot(),
                  ),
                  if (showPieceCountRows)
                    _isBoardFlipped
                        ? _buildPieceCountRow()
                        : _buildRemovedPieceCountRow()
                  else
                    const SizedBox(height: AppTheme.boardMargin),
                  Expanded(child: _buildAnalysisTabs(context)),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildAnalysisTabs(BuildContext context) {
    final GameSession? session = GameSessionScope.sessionOf(context);
    return _AnalysisPanel(
      explorer: OpeningExplorerPage(
        session: session,
        startFromSession: true,
        embedded: true,
        showBoard: false,
      ),
      moves: _InlineMoveList(
        key: const Key('play_area_analysis_moves'),
        wrapKey: const Key('play_area_analysis_moves_wrap'),
        roundKeyPrefix: 'play_area_analysis_round_',
        moveKeyPrefix: 'play_area_analysis_move_',
        onMoveTap: (BuildContext context, PgnNode<ExtMove> node) {
          return HistoryNavigator.gotoNode(context, node, pop: false);
        },
        showMovePreview: true,
        layout: _InlineMoveListLayout.stacked,
        groupByRound: true,
      ),
    );
  }

  Widget _buildAnalysisEngineLines(BuildContext context) {
    return ValueListenableBuilder<bool>(
      key: const Key('play_area_analysis_engine_lines_builder'),
      valueListenable: AnalysisMode.stateNotifier,
      builder: (BuildContext context, _, _) {
        if (!AnalysisMode.showEngineLines) {
          return const SizedBox.shrink(
            key: Key('play_area_analysis_engine_lines_hidden'),
          );
        }

        if (AnalysisMode.isAnalyzing) {
          final Color color = DB().colorSettings.messageColor;
          return Padding(
            key: const Key('play_area_analysis_engine_lines_loading'),
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            child: Row(
              children: <Widget>[
                SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  S.of(context).analyzing,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: color),
                ),
              ],
            ),
          );
        }

        final List<MoveAnalysisResult> results = AnalysisMode.analysisResults;
        if (!AnalysisMode.isFullAnalysis || results.isEmpty) {
          return const SizedBox.shrink(
            key: Key('play_area_analysis_engine_lines_empty'),
          );
        }

        return _AnalysisEngineLines(
          key: const Key('play_area_analysis_engine_lines'),
          results: results.take(3).toList(growable: false),
          onMoveTap: (String move) => _applyAnalysisMove(context, move),
        );
      },
    );
  }

  Widget _buildRegularMainContent({
    required BuildContext context,
    required bool isSetupPosition,
    required bool isPuzzle,
    required bool showPieceCountRows,
  }) {
    final bool isPlayableGame = !isSetupPosition && !isPuzzle;
    final bool showAdvantageGraph = _shouldShowAdvantageGraph(
      isGameSurface: isPlayableGame,
    );

    return SafeArea(
      top: MediaQuery.of(context).orientation == Orientation.portrait,
      bottom: false,
      right: false,
      left: false,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget moveList = _buildMoveListForRegularGame(context);
          final Widget topTable = GameHeader(
            key: const Key('play_area_game_header'),
          );
          final double topPanelHeight =
              kToolbarHeight +
              DB().displaySettings.boardTop +
              AppTheme.boardMargin;
          final List<Widget> boardChildren = <Widget>[
            if (showPieceCountRows)
              _isBoardFlipped
                  ? _buildRemovedPieceCountRow()
                  : _buildPieceCountRow()
            else
              const SizedBox(height: AppTheme.boardMargin),
            SizedBox.square(
              dimension: constraints.maxWidth,
              child: _buildBoardScreenshot(),
            ),
            if (showPieceCountRows)
              _isBoardFlipped
                  ? _buildPieceCountRow()
                  : _buildRemovedPieceCountRow()
            else
              const SizedBox(height: AppTheme.boardMargin),
          ];
          final List<Widget> bottomChildren = <Widget>[
            if (showAdvantageGraph)
              SizedBox(
                key: const Key('play_area_advantage_graph'),
                height: 150,
                width: double.infinity,
                child: CustomPaint(
                  key: const Key('play_area_custom_paint_advantage_graph'),
                  painter: AdvantageGraphPainter(advantageData),
                ),
              ),
            const SizedBox(height: AppTheme.boardMargin),
          ];

          final double estimatedRequiredHeight =
              constraints.maxWidth +
              (isPlayableGame ? _inlineMoveListHeightForRoute(context) : 0) +
              topPanelHeight +
              (showPieceCountRows
                  ? _pieceRowsHeightForLayout(context)
                  : AppTheme.boardMargin * 2) +
              (showAdvantageGraph ? 150 : 0) +
              AppTheme.boardMargin;
          final bool canBalance =
              isPlayableGame &&
              constraints.hasBoundedHeight &&
              constraints.maxHeight >=
                  estimatedRequiredHeight + _kBalancedLayoutSafetyMargin;

          if (canBalance) {
            return SizedBox(
              height: constraints.maxHeight,
              child: Column(
                key: const Key('play_area_column'),
                children: <Widget>[
                  moveList,
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: topTable,
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: boardChildren,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: bottomChildren,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            key: const Key('play_area_single_child_scroll_view'),
            child: Column(
              key: const Key('play_area_column'),
              children: <Widget>[
                if (isPlayableGame) moveList,
                topTable,
                ...boardChildren,
                ...bottomChildren,
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnalysisLandscapeContent({
    required BuildContext context,
    required BoxConstraints constraints,
    required bool showPieceCountRows,
  }) {
    assert(
      constraints.hasBoundedHeight,
      'Analysis landscape layout requires bounded height.',
    );
    final Size viewport = constraints.biggest;
    const double horizontalPadding = AppStyles.bodyPadding;
    const double verticalPadding = 8;
    const double gap = AppStyles.bodyPadding;
    const double pieceRowHeight = 24;
    final double availableWidth = math.max(
      0,
      viewport.width - horizontalPadding * 2,
    );
    final double availableHeight = math.max(
      0,
      viewport.height - kLichessBottomBarHeight - verticalPadding * 2,
    );
    final double boardHeightAllowance = math.max(
      0,
      availableHeight - (showPieceCountRows ? pieceRowHeight * 2 : 0),
    );
    final double boardSize = math.min(
      boardHeightAllowance,
      math.max(0, availableWidth * 0.52),
    );

    return SizedBox(
      key: const Key('play_area_analysis_landscape_content'),
      width: viewport.width,
      height: viewport.height,
      child: SafeArea(
        bottom: false,
        right: false,
        left: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      key: const Key('play_area_analysis_landscape_board_pane'),
                      width: boardSize,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          if (showPieceCountRows)
                            SizedBox(
                              height: pieceRowHeight,
                              child: _isBoardFlipped
                                  ? _buildRemovedPieceCountRow()
                                  : _buildPieceCountRow(),
                            ),
                          SizedBox.square(
                            key: const Key(
                              'play_area_analysis_landscape_board',
                            ),
                            dimension: boardSize,
                            child: _buildBoardScreenshot(),
                          ),
                          if (showPieceCountRows)
                            SizedBox(
                              height: pieceRowHeight,
                              child: _isBoardFlipped
                                  ? _buildPieceCountRow()
                                  : _buildRemovedPieceCountRow(),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: gap),
                    Expanded(
                      child: Column(
                        key: const Key(
                          'play_area_analysis_landscape_side_panel',
                        ),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          _buildAnalysisEngineLines(context),
                          Expanded(child: _buildAnalysisTabs(context)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildRegularBottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHumanAiLandscapeContent({
    required BuildContext context,
    required BoxConstraints constraints,
    required Widget? humanDatabaseStatsStrip,
    required bool showPieceCountRows,
  }) {
    assert(
      constraints.hasBoundedHeight,
      'Human vs AI landscape layout requires bounded height.',
    );
    final Size viewport = constraints.biggest;
    const double horizontalPadding = AppStyles.bodyPadding;
    const double verticalPadding = 8;
    const double gap = AppStyles.bodyPadding;
    const double pieceRowHeight = 24;
    final double availableWidth = math.max(
      0,
      viewport.width - horizontalPadding * 2,
    );
    final double bottomReservedHeight =
        kLichessBottomBarHeight +
        (humanDatabaseStatsStrip == null ? 0 : _kHumanDatabaseStatsStripHeight);
    final double availableHeight = math.max(
      0,
      viewport.height - bottomReservedHeight - verticalPadding * 2,
    );
    const double targetSidePanelWidth = 280;
    final double boardHeightAllowance = math.max(
      0,
      availableHeight - (showPieceCountRows ? pieceRowHeight * 2 : 0),
    );
    final double boardWidthWithPanel = math.max(
      0,
      availableWidth - targetSidePanelWidth - gap,
    );
    final double boardSize = math.min(
      boardHeightAllowance,
      boardWidthWithPanel > 0 ? boardWidthWithPanel : availableWidth * 0.58,
    );

    return SizedBox(
      key: const Key('play_area_human_ai_landscape_content'),
      width: viewport.width,
      height: viewport.height,
      child: SafeArea(
        bottom: false,
        right: false,
        left: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      key: const Key('play_area_human_ai_landscape_board_pane'),
                      width: boardSize,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          if (showPieceCountRows)
                            SizedBox(
                              height: pieceRowHeight,
                              child: _isBoardFlipped
                                  ? _buildRemovedPieceCountRow()
                                  : _buildPieceCountRow(),
                            ),
                          SizedBox.square(
                            key: const Key(
                              'play_area_human_ai_landscape_board',
                            ),
                            dimension: boardSize,
                            child: _buildBoardScreenshot(),
                          ),
                          if (showPieceCountRows)
                            SizedBox(
                              height: pieceRowHeight,
                              child: _isBoardFlipped
                                  ? _buildPieceCountRow()
                                  : _buildRemovedPieceCountRow(),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: gap),
                    Expanded(
                      child: Column(
                        key: const Key(
                          'play_area_human_ai_landscape_side_panel',
                        ),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const _HumanAiPlayerPanel(
                            key: Key(
                              'play_area_human_ai_landscape_robot_panel',
                            ),
                            isRobot: true,
                          ),
                          const Expanded(
                            child: _InlineMoveList(
                              key: Key(
                                'play_area_human_ai_landscape_move_list',
                              ),
                              wrapKey: Key(
                                'play_area_human_ai_landscape_move_list_wrap',
                              ),
                              roundKeyPrefix:
                                  'play_area_human_ai_landscape_round_',
                              moveKeyPrefix:
                                  'play_area_human_ai_landscape_move_',
                              layout: _InlineMoveListLayout.stacked,
                              groupByRound: true,
                            ),
                          ),
                          const SizedBox(height: verticalPadding),
                          const _HumanAiPlayerPanel(
                            key: Key(
                              'play_area_human_ai_landscape_player_panel',
                            ),
                            isRobot: false,
                          ),
                          if (_shouldShowAdvantageGraph(isGameSurface: true))
                            SizedBox(
                              key: const Key(
                                'play_area_human_ai_landscape_advantage_graph',
                              ),
                              height: 80,
                              width: double.infinity,
                              child: CustomPaint(
                                key: const Key(
                                  'play_area_human_ai_landscape_advantage_paint',
                                ),
                                painter: AdvantageGraphPainter(advantageData),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ?humanDatabaseStatsStrip,
            _buildHumanAiBottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildRegularLandscapeContent({
    required BuildContext context,
    required BoxConstraints constraints,
    required Widget? humanDatabaseStatsStrip,
    required bool showPieceCountRows,
  }) {
    assert(
      constraints.hasBoundedHeight,
      'Regular landscape layout requires bounded height.',
    );
    final Size viewport = constraints.biggest;
    const double horizontalPadding = AppStyles.bodyPadding;
    const double verticalPadding = 8;
    const double gap = AppStyles.bodyPadding;
    const double pieceRowHeight = 24;
    const double targetSidePanelWidth = 300;
    final double availableWidth = math.max(
      0,
      viewport.width - horizontalPadding * 2,
    );
    final double bottomReservedHeight =
        kLichessBottomBarHeight +
        (humanDatabaseStatsStrip == null ? 0 : _kHumanDatabaseStatsStripHeight);
    final double availableHeight = math.max(
      0,
      viewport.height - bottomReservedHeight - verticalPadding * 2,
    );
    final double boardHeightAllowance = math.max(
      0,
      availableHeight - (showPieceCountRows ? pieceRowHeight * 2 : 0),
    );
    final double boardWidthWithPanel = math.max(
      0,
      availableWidth - targetSidePanelWidth - gap,
    );
    final double boardSize = math.min(
      boardHeightAllowance,
      boardWidthWithPanel > 0 ? boardWidthWithPanel : availableWidth * 0.58,
    );

    return SizedBox(
      key: const Key('play_area_regular_landscape_content'),
      width: viewport.width,
      height: viewport.height,
      child: SafeArea(
        bottom: false,
        right: false,
        left: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      key: const Key('play_area_regular_landscape_board_pane'),
                      width: boardSize,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          if (showPieceCountRows)
                            SizedBox(
                              height: pieceRowHeight,
                              child: _isBoardFlipped
                                  ? _buildRemovedPieceCountRow()
                                  : _buildPieceCountRow(),
                            ),
                          SizedBox.square(
                            key: const Key('play_area_regular_landscape_board'),
                            dimension: boardSize,
                            child: _buildBoardScreenshot(),
                          ),
                          if (showPieceCountRows)
                            SizedBox(
                              height: pieceRowHeight,
                              child: _isBoardFlipped
                                  ? _buildPieceCountRow()
                                  : _buildRemovedPieceCountRow(),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: gap),
                    Expanded(
                      child: Column(
                        key: const Key(
                          'play_area_regular_landscape_side_panel',
                        ),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          GameHeader(
                            key: const Key(
                              'play_area_regular_landscape_header',
                            ),
                          ),
                          Expanded(
                            child: _InlineMoveList(
                              key: const Key(
                                'play_area_regular_landscape_move_list',
                              ),
                              wrapKey: const Key(
                                'play_area_regular_landscape_move_list_wrap',
                              ),
                              roundKeyPrefix:
                                  'play_area_regular_landscape_round_',
                              moveKeyPrefix:
                                  'play_area_regular_landscape_move_',
                              onMoveTap:
                                  (
                                    BuildContext context,
                                    PgnNode<ExtMove> node,
                                  ) {
                                    return HistoryNavigator.gotoNode(
                                      context,
                                      node,
                                      pop: false,
                                    );
                                  },
                              showMovePreview: true,
                              layout: _InlineMoveListLayout.stacked,
                              groupByRound: true,
                            ),
                          ),
                          if (_shouldShowAdvantageGraph(isGameSurface: true))
                            SizedBox(
                              key: const Key(
                                'play_area_regular_landscape_advantage_graph',
                              ),
                              height: 80,
                              width: double.infinity,
                              child: CustomPaint(
                                key: const Key(
                                  'play_area_regular_landscape_advantage_paint',
                                ),
                                painter: AdvantageGraphPainter(advantageData),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ?humanDatabaseStatsStrip,
            _buildRegularBottomBar(context),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: const Key('play_area_layout_builder'),
      builder: (BuildContext context, BoxConstraints constraints) {
        final double dimension =
            (constraints.maxWidth) *
            (MediaQuery.of(context).orientation == Orientation.portrait
                ? 1.0
                : 0.65);

        // While editing a setup position the regular history / analysis /
        // main toolbars are replaced by the dedicated setup toolbar.
        final bool isSetupPosition =
            GameController().gameInstance.gameMode == GameMode.setupPosition;

        // Hide the regular history / main toolbars in puzzle mode to keep the
        // interface clean; the PuzzlePage provides its own puzzle controls.
        final bool isPuzzle =
            GameController().gameInstance.gameMode == GameMode.puzzle;
        final bool isAnalysisMode = _isAnalysisMode;
        final bool usesLichessHumanAiToolbar =
            _usesLichessHumanAiToolbar && !isSetupPosition && !isPuzzle;
        final bool showPieceCountRows =
            DB().displaySettings.isUnplacedAndRemovedPiecesShown;

        // Human vs AI mirrors the Lichess offline-computer screen: one
        // bottom bar with menu, takeback, resign, and hint. Other game modes
        // also keep their toolbars at the bottom for a consistent shell.
        final Widget? humanDatabaseStatsStrip = _buildHumanDatabaseStatsStrip(
          context,
        );
        final Widget? bottomHumanDatabaseStatsStrip =
            !isSetupPosition && !isPuzzle && !isAnalysisMode
            ? humanDatabaseStatsStrip
            : null;
        final bool useHumanAiLandscapeLayout =
            usesLichessHumanAiToolbar &&
            constraints.hasBoundedHeight &&
            constraints.maxWidth > constraints.maxHeight;

        if (useHumanAiLandscapeLayout) {
          return _buildHumanAiLandscapeContent(
            context: context,
            constraints: constraints,
            humanDatabaseStatsStrip: bottomHumanDatabaseStatsStrip,
            showPieceCountRows: showPieceCountRows,
          );
        }
        final bool useAnalysisLandscapeLayout =
            isAnalysisMode &&
            constraints.hasBoundedHeight &&
            constraints.maxWidth > constraints.maxHeight;

        if (useAnalysisLandscapeLayout) {
          return _buildAnalysisLandscapeContent(
            context: context,
            constraints: constraints,
            showPieceCountRows: showPieceCountRows,
          );
        }
        final bool useRegularLandscapeLayout =
            !usesLichessHumanAiToolbar &&
            !isAnalysisMode &&
            !isSetupPosition &&
            !isPuzzle &&
            constraints.hasBoundedHeight &&
            constraints.maxWidth > constraints.maxHeight;

        if (useRegularLandscapeLayout) {
          return _buildRegularLandscapeContent(
            context: context,
            constraints: constraints,
            humanDatabaseStatsStrip: bottomHumanDatabaseStatsStrip,
            showPieceCountRows: showPieceCountRows,
          );
        }

        // Main content without bottom toolbars:
        final Widget mainContent = SizedBox(
          key: const Key('play_area_main_content'),
          width: dimension,
          child: usesLichessHumanAiToolbar
              ? _buildHumanAiMainContent(
                  context: context,
                  showPieceCountRows: showPieceCountRows,
                )
              : isAnalysisMode
              ? _buildAnalysisMainContent(
                  context: context,
                  showPieceCountRows: showPieceCountRows,
                )
              : _buildRegularMainContent(
                  context: context,
                  isSetupPosition: isSetupPosition,
                  isPuzzle: isPuzzle,
                  showPieceCountRows: showPieceCountRows,
                ),
        );

        return SizedBox(
          key: const Key('play_area_sized_box_toolbar_bottom'),
          width: dimension,
          child: SafeArea(
            top: false,
            right: false,
            left: false,
            child: Column(
              key: const Key('play_area_column_toolbar_bottom'),
              children: <Widget>[
                Expanded(child: mainContent),

                ?bottomHumanDatabaseStatsStrip,

                // History navigation toolbar if enabled
                if (DB().displaySettings.isHistoryNavigationToolbarShown &&
                    !isSetupPosition &&
                    !isPuzzle &&
                    !usesLichessHumanAiToolbar)
                  GamePageToolbar(
                    key: const Key('play_area_history_nav_toolbar_bottom'),
                    backgroundColor:
                        DB().colorSettings.navigationToolbarBackgroundColor,
                    itemColor: DB().colorSettings.navigationToolbarIconColor,
                    children: _buildToolbarItems(
                      context,
                      _getHistoryNavToolbarItems(context),
                    ),
                  ),

                // Main toolbar (or setup-position toolbar)
                if (usesLichessHumanAiToolbar)
                  _buildHumanAiBottomBar(context)
                else if (isSetupPosition)
                  const SetupPositionToolbar(
                    key: Key('play_area_setup_position_toolbar_bottom'),
                  )
                else if (!isPuzzle)
                  _buildRegularBottomBar(context),

                if (!usesLichessHumanAiToolbar)
                  const SizedBox(height: AppTheme.boardMargin),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InlineMoveList extends StatefulWidget {
  const _InlineMoveList({
    super.key,
    required this.wrapKey,
    required this.moveKeyPrefix,
    this.roundKeyPrefix,
    this.onMoveTap,
    this.showMovePreview = false,
    this.layout = _InlineMoveListLayout.wrap,
    this.groupByRound = false,
  }) : assert(
         !groupByRound || roundKeyPrefix != null,
         'Grouped inline move lists require a round key prefix.',
       );

  final Key wrapKey;
  final String moveKeyPrefix;
  final String? roundKeyPrefix;
  final Future<void> Function(BuildContext context, PgnNode<ExtMove> node)?
  onMoveTap;
  final bool showMovePreview;
  final _InlineMoveListLayout layout;
  final bool groupByRound;

  @override
  State<_InlineMoveList> createState() => _InlineMoveListState();
}

class _InlineMoveListState extends State<_InlineMoveList> {
  final GlobalKey _currentMoveKey = GlobalKey();
  PgnNode<ExtMove>? _lastAutoScrolledNode;

  List<PgnNode<ExtMove>> _currentPathNodes() {
    final List<PgnNode<ExtMove>> nodes = <PgnNode<ExtMove>>[];
    PgnNode<ExtMove>? node = GameController().gameRecorder.activeNode;
    while (node != null && node.data != null) {
      nodes.insert(0, node);
      node = node.parent;
    }
    return nodes;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: GameController().gameRecorder.moveCountNotifier,
      builder: (BuildContext context, _, _) {
        final List<PgnNode<ExtMove>> nodes = _currentPathNodes();
        final PgnNode<ExtMove>? activeNode =
            GameController().gameRecorder.activeNode;
        _scheduleCurrentMoveAutoScroll(activeNode);

        return Container(
          key: widget.wrapKey,
          width: double.infinity,
          constraints: switch (widget.layout) {
            _InlineMoveListLayout.horizontal => const BoxConstraints.tightFor(
              height: 40,
            ),
            _InlineMoveListLayout.wrap || _InlineMoveListLayout.stacked =>
              const BoxConstraints(minHeight: 40),
          },
          padding: widget.layout == _InlineMoveListLayout.horizontal
              ? const EdgeInsets.only(left: 5)
              : const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: nodes.isEmpty
              ? const SizedBox(height: 30)
              : _buildMoves(context: context, nodes: nodes),
        );
      },
    );
  }

  void _scheduleCurrentMoveAutoScroll(PgnNode<ExtMove>? activeNode) {
    if (widget.layout != _InlineMoveListLayout.horizontal ||
        activeNode == null ||
        identical(_lastAutoScrolledNode, activeNode)) {
      return;
    }

    _lastAutoScrolledNode = activeNode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final BuildContext? currentMoveContext = _currentMoveKey.currentContext;
      if (currentMoveContext == null) {
        return;
      }
      Scrollable.ensureVisible(
        currentMoveContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeIn,
      );
    });
  }

  Widget _buildMoves({
    required BuildContext context,
    required List<PgnNode<ExtMove>> nodes,
  }) {
    if (widget.groupByRound) {
      assert(
        widget.layout == _InlineMoveListLayout.horizontal ||
            widget.layout == _InlineMoveListLayout.stacked,
        'Grouped inline move lists require horizontal or stacked layout.',
      );
      return _buildGroupedMoves(context: context, nodes: nodes);
    }

    final List<Widget> chips = <Widget>[
      for (int i = 0; i < nodes.length; i++) _buildMoveChip(context, nodes, i),
    ];

    return switch (widget.layout) {
      _InlineMoveListLayout.wrap => Wrap(
        spacing: 4,
        runSpacing: 4,
        children: chips,
      ),
      _InlineMoveListLayout.stacked => SingleChildScrollView(
        key: const Key('play_area_inline_move_list_scroll_view'),
        child: Wrap(spacing: 4, runSpacing: 4, children: chips),
      ),
      _InlineMoveListLayout.horizontal => SingleChildScrollView(
        key: const Key('play_area_inline_move_list_scroll_view'),
        scrollDirection: Axis.horizontal,
        child: Row(children: _spaceMoveChips(chips)),
      ),
    };
  }

  Widget _buildGroupedMoves({
    required BuildContext context,
    required List<PgnNode<ExtMove>> nodes,
  }) {
    final List<_InlineMoveRound> rounds = _buildMoveRounds(nodes);
    final List<Widget> children = <Widget>[
      for (final _InlineMoveRound round in rounds)
        _buildMoveRound(context, round),
    ];

    return switch (widget.layout) {
      _InlineMoveListLayout.horizontal => SingleChildScrollView(
        key: const Key('play_area_inline_move_list_scroll_view'),
        scrollDirection: Axis.horizontal,
        child: Row(children: _spaceMoveChips(children)),
      ),
      _InlineMoveListLayout.stacked => SingleChildScrollView(
        key: const Key('play_area_inline_move_list_scroll_view'),
        child: Wrap(spacing: 10, runSpacing: 6, children: children),
      ),
      _InlineMoveListLayout.wrap => Wrap(
        spacing: 10,
        runSpacing: 6,
        children: children,
      ),
    };
  }

  List<_InlineMoveRound> _buildMoveRounds(List<PgnNode<ExtMove>> nodes) {
    final List<_InlineMoveRound> rounds = <_InlineMoveRound>[];
    PieceColor? firstSide;
    PieceColor? previousSide;
    int computedRound = 1;

    for (int i = 0; i < nodes.length; i++) {
      final ExtMove? move = nodes[i].data;
      assert(move != null, 'Inline move list nodes must carry move data.');
      final PieceColor side = move!.side;
      assert(
        side == PieceColor.white || side == PieceColor.black,
        'Inline move list requires a playable side, got $side.',
      );

      firstSide ??= side;
      if (previousSide != null &&
          side == firstSide &&
          previousSide != firstSide) {
        computedRound++;
      }
      previousSide = side;

      final int roundNumber = move.roundIndex ?? computedRound;
      final _InlineMoveRound round;
      if (rounds.isNotEmpty && rounds.last.number == roundNumber) {
        round = rounds.last;
      } else {
        round = _InlineMoveRound(roundNumber);
        rounds.add(round);
      }

      final _InlineMoveSegment segment;
      if (round.segments.isNotEmpty && round.segments.last.side == side) {
        segment = round.segments.last;
      } else {
        segment = _InlineMoveSegment(side: side);
        round.segments.add(segment);
      }
      segment.nodes.add(_IndexedMoveNode(index: i, node: nodes[i]));
    }

    return rounds;
  }

  Widget _buildMoveRound(BuildContext context, _InlineMoveRound round) {
    final String roundKeyPrefix = widget.roundKeyPrefix!;
    return Row(
      key: Key('$roundKeyPrefix${round.number}'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _InlineMoveCount(count: round.number),
        for (final _InlineMoveSegment segment in round.segments)
          _buildMoveSegment(context, segment),
      ],
    );
  }

  Widget _buildMoveSegment(BuildContext context, _InlineMoveSegment segment) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final PgnNode<ExtMove>? activeNode =
        GameController().gameRecorder.activeNode;
    final bool selected = segment.nodes.any(
      (_IndexedMoveNode indexed) => indexed.node == activeNode,
    );
    final _IndexedMoveNode lastNode = segment.nodes.last;
    final String label = segment.nodes
        .map((_IndexedMoveNode indexed) => indexed.node.data!.notation)
        .join(' ');
    final PgnNode<ExtMove> targetNode = lastNode.node;
    final Widget chip = _GameMoveChip(
      key: Key('${widget.moveKeyPrefix}${lastNode.index + 1}'),
      label: label,
      selected: selected,
      selectedColor: colorScheme.primaryContainer,
      selectedTextColor: colorScheme.onPrimaryContainer,
      textStyle: theme.textTheme.bodySmall,
      style: _GameMoveChipStyle.inlineText,
      onTap: widget.onMoveTap == null
          ? null
          : () => unawaited(widget.onMoveTap!(context, targetNode)),
      onLongPress: widget.showMovePreview && _hasPreviewBoard(targetNode)
          ? () => _showMovePreview(context, targetNode, lastNode.index + 1)
          : null,
    );

    if (selected) {
      return KeyedSubtree(key: _currentMoveKey, child: chip);
    }
    return chip;
  }

  Widget _buildMoveChip(
    BuildContext context,
    List<PgnNode<ExtMove>> nodes,
    int index,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final PgnNode<ExtMove> node = nodes[index];
    final PgnNode<ExtMove>? activeNode =
        GameController().gameRecorder.activeNode;
    final bool selected = node == activeNode;
    final Widget chip = _GameMoveChip(
      key: Key('${widget.moveKeyPrefix}${index + 1}'),
      label: '${index + 1}. ${node.data!.notation}',
      selected: selected,
      selectedColor: colorScheme.primaryContainer,
      selectedTextColor: colorScheme.onPrimaryContainer,
      textStyle: theme.textTheme.bodySmall,
      style: widget.layout == _InlineMoveListLayout.horizontal
          ? _GameMoveChipStyle.inlineText
          : _GameMoveChipStyle.filled,
      onTap: widget.onMoveTap == null
          ? null
          : () => unawaited(widget.onMoveTap!(context, node)),
      onLongPress: widget.showMovePreview && _hasPreviewBoard(node)
          ? () => _showMovePreview(context, node, index + 1)
          : null,
    );

    if (widget.layout == _InlineMoveListLayout.horizontal && selected) {
      return KeyedSubtree(key: _currentMoveKey, child: chip);
    }
    return chip;
  }

  List<Widget> _spaceMoveChips(List<Widget> chips) {
    final List<Widget> spaced = <Widget>[];
    for (int i = 0; i < chips.length; i++) {
      if (i > 0) {
        spaced.add(const SizedBox(width: 10));
      }
      spaced.add(chips[i]);
    }
    return spaced;
  }

  bool _hasPreviewBoard(PgnNode<ExtMove> node) {
    final String? boardLayout = node.data?.boardLayout;
    return boardLayout != null && boardLayout.isNotEmpty;
  }

  Future<void> _showMovePreview(
    BuildContext context,
    PgnNode<ExtMove> node,
    int moveNumber,
  ) {
    final ExtMove? move = node.data;
    assert(move != null, 'Move preview requires node data.');
    final String? boardLayout = move?.boardLayout;
    assert(
      boardLayout != null && boardLayout.isNotEmpty,
      'Move preview requires a board layout.',
    );

    return showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (BuildContext dialogContext) {
        final ThemeData theme = Theme.of(dialogContext);
        final ColorScheme colorScheme = theme.colorScheme;
        final String label = '$moveNumber. ${move!.notation}';

        return Dialog(
          key: const Key('play_area_move_preview_dialog'),
          child: Padding(
            padding: const EdgeInsets.all(AppStyles.bodyPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: AppStyles.sectionTitle.copyWith(
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      key: const Key('play_area_move_preview_go_button'),
                      tooltip: S.of(dialogContext).moveList,
                      icon: const Icon(Icons.my_location_rounded),
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        unawaited(
                          HistoryNavigator.gotoNode(context, node, pop: false),
                        );
                      },
                    ),
                    IconButton(
                      key: const Key('play_area_move_preview_close_button'),
                      tooltip: S.of(dialogContext).close,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 300,
                    maxHeight: 300,
                  ),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: MiniBoard(
                      key: const Key('play_area_move_preview_board'),
                      boardLayout: boardLayout!,
                      extMove: move,
                      node: node,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PositionalAdvantageIndicator extends StatelessWidget {
  const _PositionalAdvantageIndicator({required this.value})
    : assert(value >= -100 && value <= 100);

  final int value;

  @override
  Widget build(BuildContext context) {
    final Color whiteColor = DB().colorSettings.whitePieceColor;
    final Color blackColor = DB().colorSettings.blackPieceColor;
    final double whiteFraction = ((value + 100) / 200).clamp(0.0, 1.0);

    return Semantics(
      key: const Key('play_area_advantage_indicator'),
      label: S.of(context).showPositionalAdvantageIndicator,
      value: value.toString(),
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.74),
            border: Border.all(
              color: DB().colorSettings.messageColor.withValues(alpha: 0.78),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double height = constraints.maxHeight;
                final double whiteHeight = height * whiteFraction;
                final double blackHeight = height - whiteHeight;
                return Column(
                  children: <Widget>[
                    SizedBox(
                      height: blackHeight,
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: blackColor.withValues(alpha: 0.88),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 1,
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: DB().colorSettings.messageColor.withValues(
                            alpha: 0.65,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: math.max(0.0, whiteHeight - 1),
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: whiteColor.withValues(alpha: 0.88),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineMoveRound {
  _InlineMoveRound(this.number);

  final int number;
  final List<_InlineMoveSegment> segments = <_InlineMoveSegment>[];
}

class _InlineMoveSegment {
  _InlineMoveSegment({required this.side});

  final PieceColor side;
  final List<_IndexedMoveNode> nodes = <_IndexedMoveNode>[];
}

class _IndexedMoveNode {
  const _IndexedMoveNode({required this.index, required this.node});

  final int index;
  final PgnNode<ExtMove> node;
}

enum _InlineMoveListLayout { wrap, horizontal, stacked }

enum _GameMoveChipStyle { filled, inlineText }

class _InlineMoveCount extends StatelessWidget {
  const _InlineMoveCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final Color color = DB().colorSettings.messageColor.withValues(alpha: 0.8);
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Text(
        '$count.',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _GameMoveChip extends StatelessWidget {
  const _GameMoveChip({
    super.key,
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.selectedTextColor,
    required this.textStyle,
    this.style = _GameMoveChipStyle.filled,
    this.onTap,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final Color selectedTextColor;
  final TextStyle? textStyle;
  final _GameMoveChipStyle style;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color messageColor = DB().colorSettings.messageColor;
    final BorderRadius borderRadius = BorderRadius.circular(
      AppStyles.compactRadius,
    );
    final TextStyle moveTextStyle =
        textStyle?.copyWith(
          color: switch (style) {
            _GameMoveChipStyle.filled =>
              selected ? selectedTextColor : colorScheme.onSurfaceVariant,
            _GameMoveChipStyle.inlineText =>
              selected ? messageColor : messageColor.withValues(alpha: 0.8),
          },
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ) ??
        TextStyle(
          color: selected ? messageColor : messageColor.withValues(alpha: 0.8),
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        );
    final Widget labelText = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: moveTextStyle,
    );

    final Widget content = switch (style) {
      _GameMoveChipStyle.filled => DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? selectedColor : colorScheme.surfaceContainerHighest,
          borderRadius: borderRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: labelText,
        ),
      ),
      _GameMoveChipStyle.inlineText => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: labelText,
      ),
    };
    return Semantics(
      selected: selected,
      button: onTap != null || onLongPress != null,
      child: onTap == null && onLongPress == null
          ? content
          : Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: borderRadius,
                onTap: onTap,
                onLongPress: onLongPress,
                child: content,
              ),
            ),
    );
  }
}

class _HumanAiPlayerPanel extends StatelessWidget {
  const _HumanAiPlayerPanel({super.key, required this.isRobot});

  final bool isRobot;

  @override
  Widget build(BuildContext context) {
    if (isRobot) {
      return ValueListenableBuilder<bool>(
        valueListenable: GameController().engineActivityNotifier,
        builder: (BuildContext context, bool isThinking, Widget? child) {
          return _buildPanel(context, isThinking: isThinking);
        },
      );
    }
    return _buildPanel(context, isThinking: false);
  }

  Widget _buildPanel(BuildContext context, {required bool isThinking}) {
    final ThemeData theme = Theme.of(context);
    final Color messageColor = DB().colorSettings.messageColor;
    final int level = DB().generalSettings.skillLevel;
    final int rating = isRobot
        ? EloRatingService.getFixedAiEloRating(level)
        : DB().statsSettings.humanStats.rating;
    final String title = isRobot
        ? S.of(context).humanAiRobotLevel(level)
        : S.of(context).humanAiPlayer;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        key: Key(
          isRobot
              ? 'play_area_human_ai_robot_row'
              : 'play_area_human_ai_player_row',
        ),
        children: <Widget>[
          SizedBox.square(
            dimension: 44,
            child: Icon(
              isRobot ? Icons.smart_toy_outlined : Icons.person_outline,
              size: 32,
              color: messageColor.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        title,
                        key: Key(
                          isRobot
                              ? 'play_area_human_ai_robot_title'
                              : 'play_area_human_ai_player_title',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: messageColor,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    if (isThinking) ...<Widget>[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.hourglass_top,
                        key: const Key(
                          'play_area_human_ai_robot_thinking_icon',
                        ),
                        size: 16,
                        color: messageColor.withValues(alpha: 0.72),
                      ),
                    ],
                  ],
                ),
                Text(
                  '$rating ELO',
                  key: Key(
                    isRobot
                        ? 'play_area_human_ai_robot_elo'
                        : 'play_area_human_ai_player_elo',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: messageColor.withValues(alpha: 0.72),
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisPanel extends StatelessWidget {
  const _AnalysisPanel({required this.explorer, required this.moves});

  final Widget explorer;
  final Widget moves;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final S strings = S.of(context);

    return DefaultTabController(
      length: 2,
      child: DecoratedBox(
        key: const Key('play_area_analysis_panel'),
        decoration: BoxDecoration(color: colorScheme.surfaceContainerLowest),
        child: Column(
          children: <Widget>[
            Material(
              color: colorScheme.surface,
              child: TabBar(
                key: const Key('play_area_analysis_tabs'),
                tabs: <Widget>[
                  Tab(
                    icon: Icon(
                      Icons.explore_outlined,
                      semanticLabel: strings.openingExplorer,
                    ),
                  ),
                  Tab(
                    icon: Icon(
                      Icons.account_tree_outlined,
                      semanticLabel: strings.moveList,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                key: const Key('play_area_analysis_tab_view'),
                children: <Widget>[explorer, moves],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysisEngineLines extends StatelessWidget {
  const _AnalysisEngineLines({
    super.key,
    required this.results,
    required this.onMoveTap,
  });

  final List<MoveAnalysisResult> results;
  final Future<void> Function(String move) onMoveTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Column(
        key: const Key('play_area_analysis_engine_lines_column'),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final (int index, MoveAnalysisResult result) in results.indexed)
            _AnalysisEngineLine(
              key: Key('play_area_analysis_engine_line_$index'),
              result: result,
              onTap: () => unawaited(onMoveTap(result.move)),
            ),
        ],
      ),
    );
  }
}

class _AnalysisEngineLine extends StatelessWidget {
  const _AnalysisEngineLine({
    super.key,
    required this.result,
    required this.onTap,
  });

  final MoveAnalysisResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final Color outcomeColor = AnalysisMode.getColorForOutcome(result.outcome);
    final Color chipTextColor =
        ThemeData.estimateBrightnessForColor(outcomeColor) == Brightness.dark
        ? Colors.white
        : Colors.black;

    return InkWell(
      borderRadius: BorderRadius.circular(AppStyles.compactRadius),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: <Widget>[
              Container(
                constraints: const BoxConstraints(minWidth: 34),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: outcomeColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _evalLabel(result.outcome),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: chipTextColor,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${result.move}  ${result.outcome.displayString}',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _evalLabel(AnalysisOutcome outcome) {
    if (outcome.stepCount != null && outcome.stepCount! > 0) {
      return '${outcome.name.substring(0, 1).toUpperCase()}${outcome.stepCount}';
    }
    if (outcome.valueStr != null && outcome.valueStr!.isNotEmpty) {
      return outcome.valueStr!;
    }
    return switch (outcome.name) {
      'win' => 'W',
      'draw' => '=',
      'loss' => 'L',
      'advantage' => '+',
      'disadvantage' => '-',
      _ => '?',
    };
  }
}

class _ContinueFromHereGameRoute extends StatefulWidget {
  const _ContinueFromHereGameRoute({required this.mode});

  final GameMode mode;

  @override
  State<_ContinueFromHereGameRoute> createState() =>
      _ContinueFromHereGameRouteState();
}

class _ContinueFromHereGameRouteState
    extends State<_ContinueFromHereGameRoute> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.mode != GameMode.humanVsAi) {
        return;
      }
      final GameController controller = GameController();
      if (controller.gameInstance.isAiSideToMove) {
        unawaited(controller.engineToGo(context, isMoveNow: false));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GamePage(widget.mode);
  }
}

class _RegularGameBottomBar extends StatelessWidget {
  const _RegularGameBottomBar({
    required this.onMenuPressed,
    required this.onResignOrResultPressed,
    required this.onAnalyzePressed,
    required this.onAnalyzeLongPressed,
    required this.showClockControl,
    required this.isClockPaused,
    required this.isAnalysisMode,
    required this.isAnalysisHighlighted,
    required this.isShowingResult,
    required this.onClockPressed,
    required this.onTakeBackPressed,
    required this.onPreviousPressed,
    required this.onNextPressed,
  });

  final VoidCallback onMenuPressed;
  final VoidCallback? onResignOrResultPressed;
  final VoidCallback? onAnalyzePressed;
  final VoidCallback? onAnalyzeLongPressed;
  final bool showClockControl;
  final bool isClockPaused;
  final bool isAnalysisMode;
  final bool isAnalysisHighlighted;
  final bool isShowingResult;
  final VoidCallback? onClockPressed;
  final VoidCallback? onTakeBackPressed;
  final VoidCallback? onPreviousPressed;
  final VoidCallback? onNextPressed;

  @override
  Widget build(BuildContext context) {
    final Color messageColor = DB().colorSettings.messageColor;

    return LichessBottomBar(
      key: const Key('play_area_main_toolbar_bottom'),
      backgroundColor: Colors.transparent,
      foregroundColor: messageColor,
      children: <Widget>[
        LichessBottomBarButton(
          key: const Key('play_area_regular_bottom_bar_menu'),
          icon: Icons.menu,
          label: S.of(context).menu,
          onTap: onMenuPressed,
          withShadow: true,
        ),
        if (isAnalysisMode)
          _AnalysisEngineBottomBarButton(
            key: const Key('play_area_regular_bottom_bar_engine'),
            label: S.of(context).engine,
            onTap: onAnalyzePressed,
            onLongPress: onAnalyzeLongPressed,
            highlighted: isAnalysisHighlighted,
          )
        else
          LichessBottomBarButton(
            key: const Key('play_area_regular_bottom_bar_resign_result'),
            icon: isShowingResult ? Icons.info_outline : CupertinoIcons.flag,
            label: isShowingResult
                ? S.of(context).results
                : S.of(context).resign,
            onTap: onResignOrResultPressed,
            highlighted: isShowingResult,
            withShadow: true,
          ),
        if (showClockControl)
          LichessBottomBarButton(
            key: const Key('play_area_regular_bottom_bar_clock'),
            icon: isClockPaused ? CupertinoIcons.play : CupertinoIcons.pause,
            label: isClockPaused ? S.of(context).resume : S.of(context).pause,
            onTap: onClockPressed,
            withShadow: true,
          ),
        if (isAnalysisMode) ...<Widget>[
          LichessBottomBarButton(
            key: const Key('play_area_regular_bottom_bar_previous'),
            icon: CupertinoIcons.chevron_back,
            label: S.of(context).previous,
            onTap: onPreviousPressed,
            withShadow: true,
          ),
          LichessBottomBarButton(
            key: const Key('play_area_regular_bottom_bar_next'),
            icon: CupertinoIcons.chevron_forward,
            label: S.of(context).next,
            onTap: onNextPressed,
            withShadow: true,
          ),
        ] else
          LichessBottomBarButton(
            key: const Key('play_area_regular_bottom_bar_take_back'),
            icon: CupertinoIcons.arrow_uturn_left,
            label: S.of(context).takeBack,
            onTap: onTakeBackPressed,
            withShadow: true,
          ),
      ],
    );
  }
}

class _AnalysisEngineBottomBarButton extends StatelessWidget {
  const _AnalysisEngineBottomBarButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.onLongPress,
    required this.highlighted,
  });

  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool highlighted;

  bool get _enabled => onTap != null;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color foreground =
        IconTheme.of(context).color ??
        DefaultTextStyle.of(context).style.color ??
        colorScheme.onSurface;
    final Color activeColor = colorScheme.primary;
    final Color chipColor = highlighted || AnalysisMode.isAnalyzing
        ? activeColor
        : foreground.withValues(alpha: 0.72);
    final Color textColor = highlighted || AnalysisMode.isAnalyzing
        ? activeColor
        : foreground;
    final String chipText = _chipText;

    return Semantics(
      container: true,
      button: true,
      enabled: _enabled,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        excludeFromSemantics: true,
        message: label,
        triggerMode: TooltipTriggerMode.longPress,
        child: InkWell(
          borderRadius: BorderRadius.zero,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Opacity(
            opacity: _enabled ? 1 : 0.4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SizedBox.square(
                  dimension: 28,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      CustomPaint(
                        size: const Size.square(28),
                        painter: _AnalysisEngineChipPainter(chipColor),
                      ),
                      Text(
                        chipText,
                        key: const Key(
                          'play_area_regular_bottom_bar_engine_value',
                        ),
                        style: TextStyle(
                          color: textColor,
                          fontSize: chipText.length > 2 ? 9 : 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                          shadows: <Shadow>[
                            Shadow(
                              color: textColor.computeLuminance() < 0.5
                                  ? Colors.white.withValues(alpha: 0.48)
                                  : Colors.black.withValues(alpha: 0.48),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'DB',
                  key: const Key('play_area_regular_bottom_bar_engine_label'),
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.82),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _chipText {
    if (AnalysisMode.isAnalyzing) {
      return '...';
    }
    if (!AnalysisMode.isFullAnalysis) {
      return '-';
    }
    final int count = AnalysisMode.analysisResults.length;
    assert(count > 0, 'Full analysis mode must have at least one line.');
    return math.min(99, count).toString();
  }
}

class _AnalysisEngineChipPainter extends CustomPainter {
  const _AnalysisEngineChipPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final Paint fill = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;

    final Rect body = Rect.fromLTWH(5, 5, size.width - 10, size.height - 10);
    final RRect outer = RRect.fromRectAndRadius(body, const Radius.circular(5));
    final RRect inner = RRect.fromRectAndRadius(
      body.deflate(4),
      const Radius.circular(2),
    );
    canvas.drawRRect(outer, fill);
    canvas.drawRRect(outer, stroke);
    canvas.drawRRect(inner, stroke..strokeWidth = 1);

    const double pinLength = 3;
    final double pinStep = body.height / 4;
    for (int i = 1; i <= 3; i++) {
      final double y = body.top + pinStep * i;
      canvas.drawLine(Offset(1, y), Offset(1 + pinLength, y), stroke);
      canvas.drawLine(
        Offset(size.width - 1 - pinLength, y),
        Offset(size.width - 1, y),
        stroke,
      );
      final double x = body.left + pinStep * i;
      canvas.drawLine(Offset(x, 1), Offset(x, 1 + pinLength), stroke);
      canvas.drawLine(
        Offset(x, size.height - 1 - pinLength),
        Offset(x, size.height - 1),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_AnalysisEngineChipPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _TakeBackRequesterSwatch extends StatelessWidget {
  const _TakeBackRequesterSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: const SizedBox.square(dimension: 24),
    );
  }
}

class _LichessGameBottomBar extends StatelessWidget {
  const _LichessGameBottomBar({
    required this.onMenuPressed,
    required this.onResignOrResultPressed,
    required this.onTakeBackPressed,
    required this.onHintPressed,
    required this.isShowingResult,
    required this.isHintHighlighted,
  });

  final VoidCallback onMenuPressed;
  final VoidCallback? onResignOrResultPressed;
  final VoidCallback? onTakeBackPressed;
  final VoidCallback? onHintPressed;
  final bool isShowingResult;
  final bool isHintHighlighted;

  @override
  Widget build(BuildContext context) {
    final Color messageColor = DB().colorSettings.messageColor;

    return LichessBottomBar(
      key: const Key('play_area_lichess_bottom_bar'),
      backgroundColor: Colors.transparent,
      foregroundColor: messageColor,
      children: <Widget>[
        LichessBottomBarButton(
          key: const Key('play_area_bottom_bar_menu'),
          icon: Icons.menu,
          label: S.of(context).menu,
          onTap: onMenuPressed,
          withShadow: true,
        ),
        LichessBottomBarButton(
          key: const Key('play_area_bottom_bar_resign'),
          icon: isShowingResult ? Icons.info_outline : CupertinoIcons.flag,
          label: isShowingResult ? S.of(context).results : S.of(context).resign,
          onTap: onResignOrResultPressed,
          highlighted: isShowingResult,
          withShadow: true,
        ),
        LichessBottomBarButton(
          key: const Key('play_area_bottom_bar_take_back'),
          icon: CupertinoIcons.arrow_uturn_left,
          label: S.of(context).takeBack,
          onTap: onTakeBackPressed,
          withShadow: true,
        ),
        LichessBottomBarButton(
          key: const Key('play_area_bottom_bar_hint'),
          icon: CupertinoIcons.lightbulb,
          label: S.of(context).getAHint,
          onTap: onHintPressed,
          highlighted: isHintHighlighted,
          withShadow: true,
        ),
      ],
    );
  }
}
