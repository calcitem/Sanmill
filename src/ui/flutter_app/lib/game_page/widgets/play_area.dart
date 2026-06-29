// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// play_area.dart

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:native_screenshot_widget/native_screenshot_widget.dart';

import '../../experience_recording/models/recording_models.dart';
import '../../experience_recording/services/recording_service.dart';
import '../../general_settings/widgets/general_settings_page.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/config/constants.dart';
import '../../shared/database/database.dart';
import '../../shared/services/screenshot_service.dart';
import '../../shared/themes/app_theme.dart';
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

  bool get _usesLichessHumanAiToolbar =>
      GameController().gameInstance.gameMode == GameMode.humanVsAi;

  bool get _canResignFromBottomBar {
    final Phase phase = GameController().activeBoardView.phase;
    return _usesLichessHumanAiToolbar &&
        phase != Phase.ready &&
        phase != Phase.gameOver;
  }

  bool get _canTakeBackFromBottomBar {
    return _usesLichessHumanAiToolbar &&
        GameController().gameRecorder.mainlineMoves.isNotEmpty &&
        !GameController().isEngineRunning;
  }

  bool get _canToggleHintFromBottomBar {
    final Phase phase = GameController().activeBoardView.phase;
    return _usesLichessHumanAiToolbar &&
        phase != Phase.gameOver &&
        !AnalysisMode.isAnalyzing;
  }

  void _toggleBoardFlipped(BuildContext context) {
    assert(_usesLichessHumanAiToolbar);
    setState(() {
      _isBoardFlipped = !_isBoardFlipped;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(S.of(context).flipBoard)));
  }

  Future<void> _toggleAnalysisFromBottomBar(
    BuildContext context, {
    required String source,
  }) async {
    assert(_usesLichessHumanAiToolbar);
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'lichessBottom', 'action': source},
    );
    await AnalysisService.toggle(context);
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
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'lichessBottom', 'action': 'takeBack'},
    );
    await HistoryNavigator.takeBack(context, pop: false, toolbar: true);
  }

  Future<void> _requestNewGameFromBottomBar(BuildContext context) async {
    assert(_usesLichessHumanAiToolbar);
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'lichessBottom', 'action': 'newGame'},
    );
    await GameOptionsModal.requestNewGame(context);
  }

  void _showHumanAiGameMenu(BuildContext context) {
    assert(_usesLichessHumanAiToolbar);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          key: const Key('play_area_game_menu_sheet'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _GameMenuActionTile(
                key: const Key('play_area_game_menu_flip_board'),
                icon: Icons.flip_camera_android_outlined,
                label: S.of(sheetContext).flipBoard,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _toggleBoardFlipped(context);
                },
              ),
              _GameMenuActionTile(
                key: const Key('play_area_game_menu_analysis'),
                icon: Icons.analytics_outlined,
                label: S.of(sheetContext).analysis,
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _toggleAnalysisFromBottomBar(
                    context,
                    source: 'analysis',
                  );
                },
              ),
              _GameMenuActionTile(
                key: const Key('play_area_game_menu_new_game'),
                icon: Icons.add_circle_outline,
                label: S.of(sheetContext).newGame,
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _requestNewGameFromBottomBar(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Builds a list of toolbar items by expanding each [ToolbarItem].
  List<Widget> _buildToolbarItems(
    BuildContext context,
    List<ToolbarItem> items,
  ) {
    return items.map((ToolbarItem item) => Expanded(child: item)).toList();
  }

  /// Retrieves the main toolbar items for the game page.
  List<ToolbarItem> _getMainToolbarItems(BuildContext context) {
    return <ToolbarItem>[
      ToolbarItem.icon(
        key: const Key('play_area_toolbar_item_game'),
        onPressed: () => _openModal(
          context,
          GameOptionsModal(
            onTriggerScreenshot: () => _takeScreenshot("gallery"),
          ),
        ),
        icon: const Icon(FluentIcons.table_simple_24_regular),
        label: Text(
          S.of(context).game,
          key: const Key('play_area_toolbar_item_game_label'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      ToolbarItem.icon(
        key: const Key('play_area_toolbar_item_options'),
        onPressed: () => _navigateToSettings(context),
        icon: const Icon(FluentIcons.settings_24_regular),
        label: Text(
          S.of(context).options,
          key: const Key('play_area_toolbar_item_options_label'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      ToolbarItem.icon(
        key: const Key('play_area_toolbar_item_move'),
        onPressed: () {
          if (DB().generalSettings.screenReaderSupport) {
            // On screen readers, use a bottom sheet.
            _openModal(context, _buildMoveModal(context));
          } else {
            // Complete all ongoing animations before navigating to ensure
            // pieces are in their final positions when user returns
            GameController().animationManager.completeAllAnimations();

            // Otherwise, open a dedicated MovesListPage.
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: '/movesList'),
                builder: (BuildContext context) => const MovesListPage(),
              ),
            );
          }
        },
        icon: const Icon(FluentIcons.calendar_agenda_24_regular),
        label: Text(
          S.of(context).move,
          key: const Key('play_area_toolbar_item_move_label'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      ToolbarItem.icon(
        key: const Key('play_area_toolbar_item_info'),
        onPressed: () => _openDialog(context, const InfoDialog()),
        icon: const Icon(FluentIcons.book_information_24_regular),
        label: Text(
          S.of(context).info,
          key: const Key('play_area_toolbar_item_info_label'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ];
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

        // Human vs AI mirrors the Lichess offline-computer screen: one
        // bottom bar with menu, resign, takeback, and hint.
        final bool isToolbarAtBottom =
            DB().displaySettings.isToolbarAtBottom || usesLichessHumanAiToolbar;
        final Widget? humanDatabaseStatsStrip = _buildHumanDatabaseStatsStrip(
          context,
        );

        // Main content without bottom toolbars:
        final Widget mainContent = SizedBox(
          key: const Key('play_area_main_content'),
          width: dimension,
          child: SafeArea(
            top: MediaQuery.of(context).orientation == Orientation.portrait,
            bottom: !isToolbarAtBottom,
            // If toolbars are at bottom, we skip the bottom safe area
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
                  if (DB().displaySettings.isUnplacedAndRemovedPiecesShown &&
                      !(Constants.isSmallScreen(context) == true &&
                          DB().ruleSettings.piecesCount > 9))
                    _buildPieceCountRow()
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
                  if (DB().displaySettings.isUnplacedAndRemovedPiecesShown &&
                      !(Constants.isSmallScreen(context) == true &&
                          DB().ruleSettings.piecesCount > 9))
                    _buildRemovedPieceCountRow()
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

                  // History navigation toolbar if enabled and not at bottom
                  if (DB().displaySettings.isHistoryNavigationToolbarShown &&
                      !isToolbarAtBottom &&
                      !isSetupPosition &&
                      !isPuzzle &&
                      !usesLichessHumanAiToolbar)
                    GamePageToolbar(
                      key: const Key('play_area_history_nav_toolbar'),
                      backgroundColor:
                          DB().colorSettings.navigationToolbarBackgroundColor,
                      itemColor: DB().colorSettings.navigationToolbarIconColor,
                      children: _buildToolbarItems(
                        context,
                        _getHistoryNavToolbarItems(context),
                      ),
                    ),

                  // ──────────────────────────────────────────────────────────
                  // NOTE: The bottom black Annotation Toolbar is removed.
                  //       All annotation features are now in the center overlay.
                  // ──────────────────────────────────────────────────────────

                  // Main toolbar (or setup-position toolbar) if not at bottom
                  if (!isToolbarAtBottom)
                    if (isSetupPosition)
                      const SetupPositionToolbar(
                        key: Key('play_area_setup_position_toolbar'),
                      )
                    else if (!isPuzzle && !usesLichessHumanAiToolbar)
                      GamePageToolbar(
                        key: const Key('play_area_main_toolbar'),
                        backgroundColor:
                            DB().colorSettings.mainToolbarBackgroundColor,
                        itemColor: DB().colorSettings.mainToolbarIconColor,
                        children: _buildToolbarItems(
                          context,
                          _getMainToolbarItems(context),
                        ),
                      ),

                  if (!usesLichessHumanAiToolbar)
                    const SizedBox(height: AppTheme.boardMargin),
                ],
              ),
            ),
          ),
        );

        // If toolbars are pinned to the bottom, place them after main content.
        if (isToolbarAtBottom) {
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
                          onHintPressed: _canToggleHintFromBottomBar
                              ? () => _toggleAnalysisFromBottomBar(
                                  context,
                                  source: 'hint',
                                )
                              : null,
                          isHintHighlighted: AnalysisMode.isEnabled,
                        );
                      },
                    )
                  else if (isSetupPosition)
                    const SetupPositionToolbar(
                      key: Key('play_area_setup_position_toolbar_bottom'),
                    )
                  else if (!isPuzzle)
                    GamePageToolbar(
                      key: const Key('play_area_main_toolbar_bottom'),
                      backgroundColor:
                          DB().colorSettings.mainToolbarBackgroundColor,
                      itemColor: DB().colorSettings.mainToolbarIconColor,
                      children: _buildToolbarItems(
                        context,
                        _getMainToolbarItems(context),
                      ),
                    ),

                  if (!usesLichessHumanAiToolbar)
                    const SizedBox(height: AppTheme.boardMargin),
                ],
              ),
            ),
          );
        }

        // If toolbars are not at the bottom, return main content as is.
        return mainContent;
      },
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
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.4,
      child: BottomAppBar(
        key: const Key('play_area_lichess_bottom_bar'),
        color: colorScheme.surface,
        elevation: 3,
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: <Widget>[
            _LichessBottomBarButton(
              key: const Key('play_area_bottom_bar_menu'),
              icon: Icons.menu,
              label: S.of(context).menu,
              onPressed: onMenuPressed,
            ),
            _LichessBottomBarButton(
              key: const Key('play_area_bottom_bar_resign'),
              icon: Icons.outlined_flag,
              label: S.of(context).resign,
              onPressed: onResignPressed,
            ),
            _LichessBottomBarButton(
              key: const Key('play_area_bottom_bar_take_back'),
              icon: Icons.undo,
              label: S.of(context).takeBack,
              onPressed: onTakeBackPressed,
            ),
            _LichessBottomBarButton(
              key: const Key('play_area_bottom_bar_hint'),
              icon: Icons.lightbulb_outline,
              label: S.of(context).hint,
              onPressed: onHintPressed,
              highlighted: isHintHighlighted,
            ),
          ],
        ),
      ),
    );
  }
}

class _LichessBottomBarButton extends StatelessWidget {
  const _LichessBottomBarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color enabledColor = highlighted
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    final Color iconColor = onPressed == null
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : enabledColor;

    return Expanded(
      child: Tooltip(
        message: label,
        child: Semantics(
          button: true,
          enabled: onPressed != null,
          label: label,
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon),
            color: iconColor,
          ),
        ),
      ),
    );
  }
}

class _GameMenuActionTile extends StatelessWidget {
  const _GameMenuActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: colorScheme.onSurfaceVariant),
      title: Text(label),
      onTap: onTap,
    );
  }
}
