// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// play_area.dart

import 'dart:async';
import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:native_screenshot_widget/native_screenshot_widget.dart';

import '../../experience_recording/models/recording_models.dart';
import '../../experience_recording/services/recording_service.dart';
import '../../game_platform/game_session.dart' show GameAction, PlayerSeat;
import '../../games/mill/mill_action_codec.dart';
import '../../games/mill/mill_board_transform_actions.dart';
import '../../games/mill/native_mill_rules_port.dart';
import '../../general_settings/widgets/general_settings_page.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/config/constants.dart';
import '../../shared/database/database.dart';
import '../../shared/services/screenshot_service.dart';
import '../../shared/themes/app_styles.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/widgets/lichess_action_sheet.dart';
import '../../shared/widgets/lichess_bottom_bar.dart';
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

    final ThemeData theme = Theme.of(context);
    final Color stripBackgroundColor = Color.alphaBlend(
      DB().colorSettings.boardLineColor.withValues(alpha: 0.14),
      DB().colorSettings.boardBackgroundColor,
    );
    final bool isDarkStrip =
        ThemeData.estimateBrightnessForColor(stripBackgroundColor) ==
        Brightness.dark;
    final Color contentBaseColor = isDarkStrip ? Colors.white : Colors.black;
    final Color contentColor = contentBaseColor.withValues(
      alpha: stats == null ? 0.58 : 0.78,
    );
    final Color borderColor = contentBaseColor.withValues(
      alpha: isDarkStrip ? 0.18 : 0.14,
    );
    final String statsText = stats == null
        ? S.of(context).humanGameDatabaseStatsUnavailable
        : S
              .of(context)
              .humanGameDatabaseStatsLine(
                stats.notation,
                stats.winPercent.toStringAsFixed(1),
                stats.drawPercent.toStringAsFixed(1),
                stats.lossPercent.toStringAsFixed(1),
                stats.total,
              );

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
            color: stripBackgroundColor,
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
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: contentColor,
                        ),
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
        GameController().gameRecorder.currentPath.length >= 2 &&
        _activePhase != Phase.ready &&
        _activePhase != Phase.gameOver;
  }

  bool get _isRegularGameOver {
    return !_usesLichessHumanAiToolbar && _activePhase == Phase.gameOver;
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

  void _toggleBoardFlipped(BuildContext context) {
    setState(() {
      _isBoardFlipped = !_isBoardFlipped;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(S.of(context).flipBoard)));
  }

  void _transformActiveBoard(
    BuildContext context,
    MillBoardTransformAction action,
  ) {
    final bool transformed = GameController().transformActiveLocalGame(
      action.type,
    );
    if (transformed) {
      setState(() {
        _isBoardFlipped = false;
      });
      if (_usesLichessHumanAiToolbar &&
          GameController().gameInstance.isAiSideToMove) {
        unawaited(GameController().engineToGo(context, isMoveNow: false));
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          transformed
              ? S.of(context).transformed
              : S.of(context).cannotTransform,
        ),
      ),
    );
  }

  List<LichessActionSheetAction> _buildBoardTransformActions(
    BuildContext context, {
    required String keyPrefix,
  }) {
    final S strings = S.of(context);
    return <LichessActionSheetAction>[
      for (final MillBoardTransformAction action in millBoardTransformActions)
        LichessActionSheetAction(
          key: Key('${keyPrefix}_${action.id}'),
          leading: Icon(action.icon),
          makeLabel: (BuildContext context) => Text(action.label(strings)),
          onPressed: () => _transformActiveBoard(context, action),
        ),
    ];
  }

  void _showBoardTransformSheet(
    BuildContext context, {
    required Key sheetKey,
    required String keyPrefix,
  }) {
    showLichessActionSheet<void>(
      context: context,
      sheetKey: sheetKey,
      title: Text(S.of(context).boardOrientation),
      actions: _buildBoardTransformActions(context, keyPrefix: keyPrefix),
    );
  }

  Future<void> _openAnalysisPanelFromBottomBar(
    NavigatorState navigator, {
    required String toolbar,
  }) async {
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': toolbar, 'action': 'analysisPanel'},
    );
    AnalysisMode.disable();
    await navigator.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/movesList'),
        builder: (BuildContext context) => const MovesListPage.analysisPanel(),
      ),
    );
  }

  Future<void> _moveNowFromGameMenu(
    BuildContext context, {
    required String toolbar,
  }) async {
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': toolbar, 'action': 'moveNow'},
    );
    await GameController().moveNow(context);
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

  Future<void> _requestNewGameFromBottomBar(BuildContext context) async {
    assert(_usesLichessHumanAiToolbar);
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'lichessBottom', 'action': 'newGame'},
    );
    await GameOptionsModal.showHumanAiNewGameSheet(context);
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

  void _showRegularGameMenu() {
    assert(!_usesLichessHumanAiToolbar);
    final BuildContext hostContext = context;
    final NavigatorState hostNavigator = Navigator.of(hostContext);
    showLichessActionSheet<void>(
      context: hostContext,
      sheetKey: const Key('play_area_regular_game_menu_sheet'),
      actions: <LichessActionSheetAction>[
        LichessActionSheetAction(
          key: const Key('play_area_regular_game_menu_flip_board'),
          leading: const Icon(Icons.flip_camera_android_outlined),
          makeLabel: (BuildContext context) => Text(S.of(context).flipBoard),
          onPressed: () => _toggleBoardFlipped(hostContext),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_regular_game_menu_board_orientation'),
          leading: const Icon(Icons.screen_rotation_alt_outlined),
          trailing: const Icon(Icons.chevron_right),
          makeLabel: (BuildContext context) =>
              Text(S.of(context).boardOrientation),
          onPressed: () => _showBoardTransformSheet(
            hostContext,
            sheetKey: const Key('play_area_regular_board_transform_sheet'),
            keyPrefix: 'play_area_regular_board_transform',
          ),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_regular_game_menu_analysis'),
          leading: const Icon(Icons.analytics_outlined),
          makeLabel: (BuildContext context) => Text(S.of(context).analysis),
          onPressed: () => unawaited(
            _openAnalysisPanelFromBottomBar(
              hostNavigator,
              toolbar: 'regularBottom',
            ),
          ),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_toolbar_item_game'),
          leading: const Icon(Icons.add_circle_outline),
          makeLabel: (BuildContext context) => Text(S.of(context).newGame),
          onPressed: () => _openGameOptions(hostContext),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_toolbar_item_move'),
          leading: const Icon(Icons.format_list_numbered),
          makeLabel: (BuildContext context) => Text(S.of(context).moveList),
          onPressed: () => _openMovesWithNavigator(hostNavigator),
        ),
        if (_shouldShowMoveNowMenuAction)
          LichessActionSheetAction(
            key: const Key('play_area_regular_game_menu_move_now'),
            leading: const Icon(FluentIcons.play_24_regular),
            makeLabel: (BuildContext context) => Text(S.of(context).moveNow),
            onPressed: () => unawaited(
              _moveNowFromGameMenu(hostContext, toolbar: 'regularBottom'),
            ),
          ),
        if (_shouldShowAiChatMenuAction)
          LichessActionSheetAction(
            key: const Key('play_area_regular_game_menu_ai_chat'),
            leading: const Icon(FluentIcons.chat_24_regular),
            makeLabel: (BuildContext context) =>
                Text(S.of(context).aiChatButtonTooltip),
            onPressed: () => _showAiChatDialog(hostContext),
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
                unawaited(_showRegularResignConfirmation(hostContext)),
          ),
        LichessActionSheetAction(
          key: const Key('play_area_toolbar_item_options'),
          leading: const Icon(Icons.settings_outlined),
          makeLabel: (BuildContext context) => Text(S.of(context).options),
          onPressed: () => _navigateToSettings(hostContext),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_toolbar_item_info'),
          leading: const Icon(Icons.info_outline),
          makeLabel: (BuildContext context) => Text(S.of(context).info),
          onPressed: () => _openDialog(hostContext, const InfoDialog()),
        ),
      ],
    );
  }

  void _showHumanAiGameMenu() {
    assert(_usesLichessHumanAiToolbar);
    final BuildContext hostContext = context;
    final NavigatorState hostNavigator = Navigator.of(hostContext);
    showLichessActionSheet<void>(
      context: hostContext,
      sheetKey: const Key('play_area_game_menu_sheet'),
      actions: <LichessActionSheetAction>[
        LichessActionSheetAction(
          key: const Key('play_area_game_menu_flip_board'),
          leading: const Icon(Icons.flip_camera_android_outlined),
          makeLabel: (BuildContext context) => Text(S.of(context).flipBoard),
          onPressed: () => _toggleBoardFlipped(hostContext),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_game_menu_board_orientation'),
          leading: const Icon(Icons.screen_rotation_alt_outlined),
          trailing: const Icon(Icons.chevron_right),
          makeLabel: (BuildContext context) =>
              Text(S.of(context).boardOrientation),
          onPressed: () => _showBoardTransformSheet(
            hostContext,
            sheetKey: const Key('play_area_board_transform_sheet'),
            keyPrefix: 'play_area_board_transform',
          ),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_game_menu_analysis'),
          leading: const Icon(Icons.analytics_outlined),
          makeLabel: (BuildContext context) => Text(S.of(context).analysis),
          onPressed: () => unawaited(
            _openAnalysisPanelFromBottomBar(
              hostNavigator,
              toolbar: 'lichessBottom',
            ),
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
              _moveNowFromGameMenu(hostContext, toolbar: 'lichessBottom'),
            ),
          ),
        if (_shouldShowAiChatMenuAction)
          LichessActionSheetAction(
            key: const Key('play_area_game_menu_ai_chat'),
            leading: const Icon(FluentIcons.chat_24_regular),
            makeLabel: (BuildContext context) =>
                Text(S.of(context).aiChatButtonTooltip),
            onPressed: () => _showAiChatDialog(hostContext),
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
            onPressed: () => unawaited(_showResignConfirmation(hostContext)),
          ),
        LichessActionSheetAction(
          key: const Key('play_area_game_menu_new_game'),
          leading: const Icon(Icons.add_circle_outline),
          makeLabel: (BuildContext context) => Text(S.of(context).newGame),
          onPressed: () => unawaited(_requestNewGameFromBottomBar(hostContext)),
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
    return NativeScreenshot(
      key: const Key('play_area_native_screenshot'),
      controller: ScreenshotService.screenshotController,
      child: Container(
        key: const Key('play_area_game_board_container'),
        alignment: Alignment.center,
        child: RotatedBox(
          key: const Key('play_area_board_orientation'),
          quarterTurns: _isBoardFlipped ? 2 : 0,
          child: widget.child,
        ),
      ),
    );
  }

  Widget _buildHumanAiMainContent({
    required BuildContext context,
    required Widget? humanDatabaseStatsStrip,
    required bool showPieceCountRows,
  }) {
    return SizedBox(
      key: const Key('play_area_human_ai_main_content'),
      child: SafeArea(
        top: MediaQuery.of(context).orientation == Orientation.portrait,
        bottom: false,
        right: false,
        left: false,
        child: SingleChildScrollView(
          key: const Key('play_area_human_ai_scroll_view'),
          child: Column(
            key: const Key('play_area_human_ai_column'),
            children: <Widget>[
              const _InlineMoveList(
                key: Key('play_area_human_ai_move_list'),
                wrapKey: Key('play_area_human_ai_move_list_wrap'),
                roundKeyPrefix: 'play_area_human_ai_round_',
                moveKeyPrefix: 'play_area_human_ai_move_',
                layout: _InlineMoveListLayout.horizontal,
                groupByRound: true,
              ),
              const _HumanAiPlayerPanel(
                key: Key('play_area_human_ai_robot_panel'),
                isRobot: true,
              ),
              ?humanDatabaseStatsStrip,
              if (showPieceCountRows)
                _isBoardFlipped
                    ? _buildRemovedPieceCountRow()
                    : _buildPieceCountRow(),
              _buildBoardScreenshot(),
              if (showPieceCountRows)
                _isBoardFlipped
                    ? _buildPieceCountRow()
                    : _buildRemovedPieceCountRow(),
              const _HumanAiPlayerPanel(
                key: Key('play_area_human_ai_player_panel'),
                isRobot: false,
              ),
              if (DB().displaySettings.isAdvantageGraphShown &&
                  advantageData.isNotEmpty)
                SizedBox(
                  key: const Key('play_area_advantage_graph'),
                  height: 112,
                  width: double.infinity,
                  child: CustomPaint(
                    key: const Key('play_area_custom_paint_advantage_graph'),
                    painter: AdvantageGraphPainter(advantageData),
                  ),
                ),
            ],
          ),
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
            return _RegularGameBottomBar(
              onMenuPressed: _showRegularGameMenu,
              showClockControl: _shouldShowRegularClockControl,
              isClockPaused: status == PlayerTimerStatus.paused,
              onClockPressed: _regularClockControlAction(status),
              onPreviousPressed: _canStepBackFromRegularBottomBar
                  ? () => _stepBackFromRegularBottomBar(context)
                  : null,
              onNextPressed: _canStepForwardFromRegularBottomBar
                  ? () => HistoryNavigator.stepForward(
                      context,
                      pop: false,
                      toolbar: true,
                    )
                  : null,
              onTakeBackPressed: _canTakeBackFromRegularBottomBar
                  ? () => _takeBackFromRegularBottomBar(context)
                  : null,
            );
          },
        );
      },
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
    final double availableHeight = math.max(
      0,
      viewport.height - verticalPadding * 2,
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
                      key: const Key('play_area_human_ai_landscape_board'),
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
                  key: const Key('play_area_human_ai_landscape_side_panel'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const _HumanAiPlayerPanel(
                      key: Key('play_area_human_ai_landscape_robot_panel'),
                      isRobot: true,
                    ),
                    ?humanDatabaseStatsStrip,
                    const Expanded(
                      child: _InlineMoveList(
                        key: Key('play_area_human_ai_landscape_move_list'),
                        wrapKey: Key(
                          'play_area_human_ai_landscape_move_list_wrap',
                        ),
                        roundKeyPrefix: 'play_area_human_ai_landscape_round_',
                        moveKeyPrefix: 'play_area_human_ai_landscape_move_',
                        layout: _InlineMoveListLayout.stacked,
                        groupByRound: true,
                      ),
                    ),
                    _buildHumanAiBottomBar(context),
                    const SizedBox(height: verticalPadding),
                    const _HumanAiPlayerPanel(
                      key: Key('play_area_human_ai_landscape_player_panel'),
                      isRobot: false,
                    ),
                    if (DB().displaySettings.isAdvantageGraphShown &&
                        advantageData.isNotEmpty)
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
    final double availableHeight = math.max(
      0,
      viewport.height - verticalPadding * 2,
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
                  key: const Key('play_area_regular_landscape_side_panel'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    GameHeader(
                      key: const Key('play_area_regular_landscape_header'),
                    ),
                    ?humanDatabaseStatsStrip,
                    Expanded(
                      child: _InlineMoveList(
                        key: const Key('play_area_regular_landscape_move_list'),
                        wrapKey: const Key(
                          'play_area_regular_landscape_move_list_wrap',
                        ),
                        roundKeyPrefix: 'play_area_regular_landscape_round_',
                        moveKeyPrefix: 'play_area_regular_landscape_move_',
                        onMoveTap:
                            (BuildContext context, PgnNode<ExtMove> node) {
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
                    _buildRegularBottomBar(context),
                    if (DB().displaySettings.isAdvantageGraphShown &&
                        advantageData.isNotEmpty)
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
        final bool useHumanAiLandscapeLayout =
            usesLichessHumanAiToolbar &&
            constraints.hasBoundedHeight &&
            constraints.maxWidth > constraints.maxHeight;

        if (useHumanAiLandscapeLayout) {
          return _buildHumanAiLandscapeContent(
            context: context,
            constraints: constraints,
            humanDatabaseStatsStrip: humanDatabaseStatsStrip,
            showPieceCountRows: showPieceCountRows,
          );
        }
        final bool useRegularLandscapeLayout =
            !usesLichessHumanAiToolbar &&
            !isSetupPosition &&
            !isPuzzle &&
            constraints.hasBoundedHeight &&
            constraints.maxWidth > constraints.maxHeight;

        if (useRegularLandscapeLayout) {
          return _buildRegularLandscapeContent(
            context: context,
            constraints: constraints,
            humanDatabaseStatsStrip: humanDatabaseStatsStrip,
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
                  humanDatabaseStatsStrip: humanDatabaseStatsStrip,
                  showPieceCountRows: showPieceCountRows,
                )
              : SafeArea(
                  top:
                      MediaQuery.of(context).orientation ==
                      Orientation.portrait,
                  bottom: false,
                  right: false,
                  left: false,
                  child: SingleChildScrollView(
                    key: const Key('play_area_single_child_scroll_view'),
                    child: Column(
                      key: const Key('play_area_column'),
                      children: <Widget>[
                        if (!isSetupPosition && !isPuzzle)
                          _InlineMoveList(
                            key: const Key('play_area_regular_move_list'),
                            wrapKey: const Key(
                              'play_area_regular_move_list_wrap',
                            ),
                            roundKeyPrefix: 'play_area_regular_round_',
                            moveKeyPrefix: 'play_area_regular_move_',
                            onMoveTap:
                                (BuildContext context, PgnNode<ExtMove> node) {
                                  return HistoryNavigator.gotoNode(
                                    context,
                                    node,
                                    pop: false,
                                  );
                                },
                            showMovePreview: true,
                            layout: _InlineMoveListLayout.horizontal,
                            groupByRound: true,
                          ),

                        // The top game header with hints, icons, etc.
                        GameHeader(key: const Key('play_area_game_header')),

                        ?humanDatabaseStatsStrip,

                        // Piece counts or spacing if not used
                        if (showPieceCountRows)
                          _isBoardFlipped
                              ? _buildRemovedPieceCountRow()
                              : _buildPieceCountRow()
                        else
                          const SizedBox(height: AppTheme.boardMargin),

                        // The main board wrapped with screenshot capturing
                        _buildBoardScreenshot(),

                        // Removed pieces row or spacing
                        if (showPieceCountRows)
                          _isBoardFlipped
                              ? _buildPieceCountRow()
                              : _buildRemovedPieceCountRow()
                        else
                          const SizedBox(height: AppTheme.boardMargin),

                        // Advantage graph if enabled
                        if (DB().displaySettings.isAdvantageGraphShown &&
                            advantageData.isNotEmpty)
                          SizedBox(
                            key: const Key('play_area_advantage_graph'),
                            height: 150,
                            width: double.infinity,
                            child: CustomPaint(
                              key: const Key(
                                'play_area_custom_paint_advantage_graph',
                              ),
                              painter: AdvantageGraphPainter(advantageData),
                            ),
                          ),

                        if (!usesLichessHumanAiToolbar)
                          const SizedBox(height: AppTheme.boardMargin),
                      ],
                    ),
                  ),
                ),
        );

        return SizedBox(
          key: const Key('play_area_sized_box_toolbar_bottom'),
          width: dimension,
          child: SafeArea(
            top: MediaQuery.of(context).orientation == Orientation.portrait,
            right: false,
            left: false,
            child: Column(
              key: const Key('play_area_column_toolbar_bottom'),
              children: <Widget>[
                Expanded(child: mainContent),

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
    final Color color = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.8);
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
    final BorderRadius borderRadius = BorderRadius.circular(
      AppStyles.compactRadius,
    );
    final TextStyle moveTextStyle =
        textStyle?.copyWith(
          color: switch (style) {
            _GameMoveChipStyle.filled =>
              selected ? selectedTextColor : colorScheme.onSurfaceVariant,
            _GameMoveChipStyle.inlineText =>
              selected
                  ? colorScheme.primary
                  : colorScheme.onSurface.withValues(alpha: 0.8),
          },
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ) ??
        TextStyle(
          color: selected ? colorScheme.primary : colorScheme.onSurface,
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
    final ColorScheme colorScheme = theme.colorScheme;
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
              color: isRobot ? colorScheme.secondary : colorScheme.primary,
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
                        color: colorScheme.onSurfaceVariant,
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
                    color: colorScheme.onSurfaceVariant,
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

class _RegularGameBottomBar extends StatelessWidget {
  const _RegularGameBottomBar({
    required this.onMenuPressed,
    required this.showClockControl,
    required this.isClockPaused,
    required this.onClockPressed,
    required this.onPreviousPressed,
    required this.onNextPressed,
    required this.onTakeBackPressed,
  });

  final VoidCallback onMenuPressed;
  final bool showClockControl;
  final bool isClockPaused;
  final VoidCallback? onClockPressed;
  final VoidCallback? onPreviousPressed;
  final VoidCallback? onNextPressed;
  final VoidCallback? onTakeBackPressed;

  @override
  Widget build(BuildContext context) {
    return LichessBottomBar(
      key: const Key('play_area_main_toolbar_bottom'),
      children: <Widget>[
        LichessBottomBarButton(
          key: const Key('play_area_regular_bottom_bar_menu'),
          icon: Icons.menu,
          label: S.of(context).menu,
          onTap: onMenuPressed,
        ),
        if (showClockControl)
          LichessBottomBarButton(
            key: const Key('play_area_regular_bottom_bar_clock'),
            icon: isClockPaused ? CupertinoIcons.play : CupertinoIcons.pause,
            label: isClockPaused ? S.of(context).resume : S.of(context).pause,
            onTap: onClockPressed,
          ),
        LichessBottomBarButton(
          key: const Key('play_area_regular_bottom_bar_previous'),
          icon: CupertinoIcons.chevron_back,
          label: S.of(context).previous,
          onTap: onPreviousPressed,
          showTooltip: false,
        ),
        LichessBottomBarButton(
          key: const Key('play_area_regular_bottom_bar_next'),
          icon: CupertinoIcons.chevron_forward,
          label: S.of(context).stepForward,
          onTap: onNextPressed,
          showTooltip: false,
        ),
        LichessBottomBarButton(
          key: const Key('play_area_regular_bottom_bar_take_back'),
          icon: CupertinoIcons.arrow_uturn_left,
          label: S.of(context).takeBack,
          onTap: onTakeBackPressed,
        ),
      ],
    );
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
    return LichessBottomBar(
      key: const Key('play_area_lichess_bottom_bar'),
      children: <Widget>[
        LichessBottomBarButton(
          key: const Key('play_area_bottom_bar_menu'),
          icon: Icons.menu,
          label: S.of(context).menu,
          onTap: onMenuPressed,
        ),
        LichessBottomBarButton(
          key: const Key('play_area_bottom_bar_resign'),
          icon: isShowingResult ? Icons.info_outline : CupertinoIcons.flag,
          label: isShowingResult ? S.of(context).results : S.of(context).resign,
          onTap: onResignOrResultPressed,
          highlighted: isShowingResult,
        ),
        LichessBottomBarButton(
          key: const Key('play_area_bottom_bar_take_back'),
          icon: CupertinoIcons.arrow_uturn_left,
          label: S.of(context).takeBack,
          onTap: onTakeBackPressed,
        ),
        LichessBottomBarButton(
          key: const Key('play_area_bottom_bar_hint'),
          icon: CupertinoIcons.lightbulb,
          label: S.of(context).getAHint,
          onTap: onHintPressed,
          highlighted: isHintHighlighted,
        ),
      ],
    );
  }
}
