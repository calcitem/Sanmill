// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// play_area.dart

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:native_screenshot_widget/native_screenshot_widget.dart';

import '../../experience_recording/models/recording_models.dart';
import '../../experience_recording/services/recording_service.dart';
import '../../games/mill/mill_board_transform_actions.dart';
import '../../general_settings/widgets/general_settings_page.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/config/constants.dart';
import '../../shared/database/database.dart';
import '../../shared/services/screenshot_service.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/widgets/lichess_action_sheet.dart';
import '../../shared/widgets/lichess_bottom_bar.dart';
import '../services/analysis/analysis_service.dart';
import '../services/analysis_mode.dart';
import '../services/mill.dart';
import '../services/painters/advantage_graph_painter.dart';
import 'game_page.dart';
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

  void _openMoves(BuildContext context) {
    if (DB().generalSettings.screenReaderSupport) {
      // On screen readers, use a bottom sheet.
      _openModal(context, _buildMoveModal(context));
      return;
    }

    // Complete all ongoing animations before navigating to ensure pieces are
    // in their final positions when the user returns.
    GameController().animationManager.completeAllAnimations();
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/movesList'),
        builder: (BuildContext context) => const MovesListPage(),
      ),
    );
  }

  bool get _usesLichessHumanAiToolbar =>
      GameController().gameInstance.gameMode == GameMode.humanVsAi;

  bool get _canResignFromBottomBar {
    final Phase phase = GameController().activeBoardView.phase;
    return _usesLichessHumanAiToolbar &&
        GameController().gameRecorder.currentPath.length >= 2 &&
        phase != Phase.ready &&
        phase != Phase.gameOver;
  }

  bool get _canTakeBackFromBottomBar {
    return _usesLichessHumanAiToolbar &&
        GameController().gameRecorder.currentPath.isNotEmpty &&
        !GameController().isEngineRunning &&
        !GameController().isEngineInDelay;
  }

  int get _humanAiTakeBackStepCount {
    assert(_usesLichessHumanAiToolbar);
    final int moveCount = GameController().gameRecorder.currentPath.length;
    assert(moveCount > 0, 'Cannot take back without a move history.');
    if (moveCount == 1) {
      return 1;
    }

    final PieceColor sideToMove = GameController().activeBoardView.sideToMove;
    assert(
      sideToMove == PieceColor.white || sideToMove == PieceColor.black,
      'Human vs AI takeback requires a playable side to move.',
    );
    return GameController().gameInstance.isHumanToMove ? 2 : 1;
  }

  bool get _canShowHintFromBottomBar {
    final Phase phase = GameController().activeBoardView.phase;
    final PieceColor sideToMove = GameController().activeBoardView.sideToMove;
    return _usesLichessHumanAiToolbar &&
        phase != Phase.gameOver &&
        (sideToMove == PieceColor.white || sideToMove == PieceColor.black) &&
        GameController().gameInstance.isHumanToMove &&
        !GameController().isEngineRunning &&
        !GameController().isEngineInDelay &&
        !AnalysisMode.isAnalyzing &&
        !_isHintSearching;
  }

  bool get _canResignFromRegularBottomBar {
    final Phase phase = GameController().activeBoardView.phase;
    return !_usesLichessHumanAiToolbar &&
        GameController().gameRecorder.currentPath.length >= 2 &&
        phase != Phase.ready &&
        phase != Phase.gameOver;
  }

  bool get _isRegularGameOver {
    return !_usesLichessHumanAiToolbar &&
        GameController().activeBoardView.phase == Phase.gameOver;
  }

  bool get _canStepBackFromRegularBottomBar {
    return !_usesLichessHumanAiToolbar &&
        GameController().gameRecorder.activeNode?.parent != null &&
        !GameController().isEngineRunning &&
        !GameController().isEngineInDelay;
  }

  bool get _canStepForwardFromRegularBottomBar {
    return !_usesLichessHumanAiToolbar &&
        (GameController().gameRecorder.activeNode ??
                GameController().gameRecorder.pgnRoot)
            .children
            .isNotEmpty &&
        !GameController().isEngineRunning &&
        !GameController().isEngineInDelay;
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
      for (final MillBoardTransformAction action
          in millBoardTransformFullActions)
        LichessActionSheetAction(
          key: Key('${keyPrefix}_${action.id}'),
          leading: Icon(action.icon),
          makeLabel: (BuildContext context) => Text(action.label(strings)),
          onPressed: () => _transformActiveBoard(context, action),
        ),
    ];
  }

  Future<void> _openAnalysisPanelFromBottomBar(BuildContext context) async {
    assert(_usesLichessHumanAiToolbar);
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'lichessBottom', 'action': 'analysisPanel'},
    );
    AnalysisMode.disable();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/movesList'),
        builder: (BuildContext context) => const MovesListPage.analysisPanel(),
      ),
    );
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

  void _showRegularGameMenu(BuildContext context) {
    assert(!_usesLichessHumanAiToolbar);
    showLichessActionSheet<void>(
      context: context,
      sheetKey: const Key('play_area_regular_game_menu_sheet'),
      actions: <LichessActionSheetAction>[
        LichessActionSheetAction(
          key: const Key('play_area_regular_game_menu_flip_board'),
          leading: const Icon(Icons.flip_camera_android_outlined),
          makeLabel: (BuildContext context) => Text(S.of(context).flipBoard),
          onPressed: () => _toggleBoardFlipped(context),
        ),
        ..._buildBoardTransformActions(
          context,
          keyPrefix: 'play_area_regular_game_menu_transform',
        ),
        LichessActionSheetAction(
          key: const Key('play_area_toolbar_item_game'),
          leading: const Icon(Icons.add_circle_outline),
          makeLabel: (BuildContext context) => Text(S.of(context).game),
          onPressed: () => _openGameOptions(context),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_toolbar_item_move'),
          leading: const Icon(Icons.format_list_numbered),
          makeLabel: (BuildContext context) => Text(S.of(context).move),
          onPressed: () => _openMoves(context),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_toolbar_item_options'),
          leading: const Icon(Icons.settings_outlined),
          makeLabel: (BuildContext context) => Text(S.of(context).options),
          onPressed: () => _navigateToSettings(context),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_toolbar_item_info'),
          leading: const Icon(Icons.info_outline),
          makeLabel: (BuildContext context) => Text(S.of(context).info),
          onPressed: () => _openDialog(context, const InfoDialog()),
        ),
      ],
    );
  }

  void _showHumanAiGameMenu(BuildContext context) {
    assert(_usesLichessHumanAiToolbar);
    showLichessActionSheet<void>(
      context: context,
      sheetKey: const Key('play_area_game_menu_sheet'),
      actions: <LichessActionSheetAction>[
        LichessActionSheetAction(
          key: const Key('play_area_game_menu_flip_board'),
          leading: const Icon(Icons.flip_camera_android_outlined),
          makeLabel: (BuildContext context) => Text(S.of(context).flipBoard),
          onPressed: () => _toggleBoardFlipped(context),
        ),
        ..._buildBoardTransformActions(
          context,
          keyPrefix: 'play_area_game_menu_transform',
        ),
        LichessActionSheetAction(
          key: const Key('play_area_game_menu_analysis'),
          leading: const Icon(Icons.analytics_outlined),
          makeLabel: (BuildContext context) => Text(S.of(context).analysis),
          onPressed: () => unawaited(_openAnalysisPanelFromBottomBar(context)),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_game_menu_new_game'),
          leading: const Icon(Icons.add_circle_outline),
          makeLabel: (BuildContext context) => Text(S.of(context).newGame),
          onPressed: () => unawaited(_requestNewGameFromBottomBar(context)),
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
            final bool accepted = await GameController().requestLanTakeBack(1);
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
            DB().displaySettings.isUnplacedAndRemovedPiecesShown &&
            !(Constants.isSmallScreen(context) == true &&
                DB().ruleSettings.piecesCount > 9);

        // Human vs AI mirrors the Lichess offline-computer screen: one
        // bottom bar with menu, resign, takeback, and hint. Other game modes
        // also keep their toolbars at the bottom for a consistent shell.
        final Widget? humanDatabaseStatsStrip = _buildHumanDatabaseStatsStrip(
          context,
        );

        // Main content without bottom toolbars:
        final Widget mainContent = SizedBox(
          key: const Key('play_area_main_content'),
          width: dimension,
          child: SafeArea(
            top: MediaQuery.of(context).orientation == Orientation.portrait,
            bottom: false,
            right: false,
            left: false,
            child: SingleChildScrollView(
              key: const Key('play_area_single_child_scroll_view'),
              child: Column(
                key: const Key('play_area_column'),
                children: <Widget>[
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
                  NativeScreenshot(
                    key: const Key('play_area_native_screenshot'),
                    controller: ScreenshotService.screenshotController,
                    child: Container(
                      key: const Key('play_area_game_board_container'),
                      alignment: Alignment.center,
                      // The 'child' from the constructor is the GameBoard:
                      child: RotatedBox(
                        key: const Key('play_area_board_orientation'),
                        quarterTurns: _isBoardFlipped ? 2 : 0,
                        child: widget.child,
                      ),
                    ),
                  ),

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

                  // ──────────────────────────────────────────────────────────
                  // NOTE: The bottom black Annotation Toolbar is removed.
                  //       All annotation features are now in the center overlay.
                  // ──────────────────────────────────────────────────────────
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
                  ValueListenableBuilder<bool>(
                    key: const Key('play_area_lichess_bottom_bar_builder'),
                    valueListenable: AnalysisMode.stateNotifier,
                    builder: (BuildContext context, _, _) {
                      return _LichessGameBottomBar(
                        onMenuPressed: () => _showHumanAiGameMenu(context),
                        onResignPressed: _canResignFromBottomBar
                            ? () => _showResignConfirmation(context)
                            : null,
                        onTakeBackPressed: _canTakeBackFromBottomBar
                            ? () => _takeBackFromBottomBar(context)
                            : null,
                        onHintPressed: _canShowHintFromBottomBar
                            ? () => _showHintFromBottomBar(context)
                            : null,
                        isHintHighlighted: AnalysisMode.isHint,
                      );
                    },
                  )
                else if (isSetupPosition)
                  const SetupPositionToolbar(
                    key: Key('play_area_setup_position_toolbar_bottom'),
                  )
                else if (!isPuzzle)
                  ValueListenableBuilder<int>(
                    key: const Key('play_area_regular_bottom_bar_builder'),
                    valueListenable:
                        GameController().gameRecorder.moveCountNotifier,
                    builder: (BuildContext context, _, _) {
                      return _RegularGameBottomBar(
                        onMenuPressed: () => _showRegularGameMenu(context),
                        onResignOrResultPressed: _isRegularGameOver
                            ? _showRegularGameResult
                            : _canResignFromRegularBottomBar
                            ? () => _showRegularResignConfirmation(context)
                            : null,
                        isShowingResult: _isRegularGameOver,
                        onPreviousPressed: _canStepBackFromRegularBottomBar
                            ? () => HistoryNavigator.takeBack(
                                context,
                                pop: false,
                                toolbar: true,
                              )
                            : null,
                        onNextPressed: _canStepForwardFromRegularBottomBar
                            ? () => HistoryNavigator.stepForward(
                                context,
                                pop: false,
                                toolbar: true,
                              )
                            : null,
                      );
                    },
                  ),

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

class _RegularGameBottomBar extends StatelessWidget {
  const _RegularGameBottomBar({
    required this.onMenuPressed,
    required this.onResignOrResultPressed,
    required this.isShowingResult,
    required this.onPreviousPressed,
    required this.onNextPressed,
  });

  final VoidCallback onMenuPressed;
  final VoidCallback? onResignOrResultPressed;
  final bool isShowingResult;
  final VoidCallback? onPreviousPressed;
  final VoidCallback? onNextPressed;

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
        LichessBottomBarButton(
          key: const Key('play_area_regular_bottom_bar_resign_result'),
          icon: isShowingResult ? Icons.info_outline : CupertinoIcons.flag,
          label: isShowingResult ? S.of(context).results : S.of(context).resign,
          onTap: onResignOrResultPressed,
          highlighted: isShowingResult,
        ),
        LichessBottomBarButton(
          key: const Key('play_area_regular_bottom_bar_previous'),
          icon: CupertinoIcons.chevron_back,
          label: S.of(context).takeBack,
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
      ],
    );
  }
}

class _LichessGameBottomBar extends StatelessWidget {
  const _LichessGameBottomBar({
    required this.onMenuPressed,
    required this.onResignPressed,
    required this.onTakeBackPressed,
    required this.onHintPressed,
    required this.isHintHighlighted,
  });

  final VoidCallback onMenuPressed;
  final VoidCallback? onResignPressed;
  final VoidCallback? onTakeBackPressed;
  final VoidCallback? onHintPressed;
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
          icon: CupertinoIcons.flag,
          label: S.of(context).resign,
          onTap: onResignPressed,
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
