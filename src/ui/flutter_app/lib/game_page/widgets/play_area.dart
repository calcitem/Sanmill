// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// play_area.dart

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:native_screenshot_widget/native_screenshot_widget.dart';

import '../../general_settings/widgets/general_settings_page.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/config/constants.dart';
import '../../shared/database/database.dart';
import '../../shared/services/screenshot_service.dart';
import '../../shared/themes/app_theme.dart';
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
  const PlayArea({super.key, required this.boardImage});

  /// The ImageProvider for the selected board image.
  final ImageProvider? boardImage;

  @override
  PlayAreaState createState() => PlayAreaState();
}

class PlayAreaState extends State<PlayArea> {
  /// A list to store historical advantage values.
  List<int> advantageData = <int>[];

  @override
  void initState() {
    super.initState();
    // Listen to changes in header icons (usually triggered after a move).
    GameController().headerIconsNotifier.addListener(_updateUI);

    // Optionally, initialize advantageData with the current value if needed:
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
    final int value =
        GameController().value == null ? 0 : int.parse(GameController().value!);
    return value;
  }

  /// Updates the UI by calling setState.
  /// Also append the current advantage value to the list so that
  /// after each move, the chart will reflect the latest advantage trend.
  void _updateUI() {
    setState(() {
      if (GameController().gameRecorder.mainlineMoves.isEmpty) {
        advantageData.clear();
        advantageData.add(_getCurrentAdvantageValue());
      }

      // AdvantageData is updated only when the AI has an evaluation value returned and the flag is true
      if (GameController().lastMoveFromAI &&
          GameController().value != null &&
          GameController().aiMoveType != AiMoveType.unknown) {
        advantageData.add(_getCurrentAdvantageValue());
        GameController().lastMoveFromAI = false; // Reset the flag
      }
      // If the call is not triggered by the completion of the AI's move, advantageData will not be updated
    });
  }

  /// Takes a screenshot and saves it to the specified [storageLocation] with an optional [filename].
  Future<void> _takeScreenshot(String storageLocation,
      [String? filename]) async {
    await ScreenshotService.takeScreenshot(storageLocation, filename);
  }

  /// Opens a modal bottom sheet with the provided [modal] widget.
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
          builder: (_) => const GeneralSettingsPage()),
    );
  }

  /// Opens a dialog with the provided [dialog] widget.
  void _openDialog(BuildContext context, Widget dialog) {
    showDialog(
      context: context,
      builder: (_) => dialog,
    );
  }

  /// Builds a list of toolbar items by expanding each [ToolbarItem].
  List<Widget> _buildToolbarItems(
      BuildContext context, List<ToolbarItem> items) {
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
                onTriggerScreenshot: () => _takeScreenshot("gallery"))),
        icon: const Icon(FluentIcons.table_simple_24_regular),
        label: Text(S.of(context).game,
            key: const Key('play_area_toolbar_item_game_label'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ),
      ToolbarItem.icon(
        key: const Key('play_area_toolbar_item_options'),
        onPressed: () => _navigateToSettings(context),
        icon: const Icon(FluentIcons.settings_24_regular),
        label: Text(S.of(context).options,
            key: const Key('play_area_toolbar_item_options_label'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ),
      ToolbarItem.icon(
        key: const Key('play_area_toolbar_item_move'),
        onPressed: () {
          if (DB().generalSettings.screenReaderSupport) {
            _openModal(context, _buildMoveModal(context));
          } else {
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const MovesListPage(),
              ),
            );
          }
        },
        icon: const Icon(FluentIcons.calendar_agenda_24_regular),
        label: Text(S.of(context).move,
            key: const Key('play_area_toolbar_item_move_label'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ),
      ToolbarItem.icon(
        key: const Key('play_area_toolbar_item_info'),
        onPressed: () => _openDialog(context, const InfoDialog()),
        icon: const Icon(FluentIcons.book_information_24_regular),
        label: Text(S.of(context).info,
            key: const Key('play_area_toolbar_item_info_label'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ),
    ];
  }

  /// Builds the move modal based on display settings.
  Widget _buildMoveModal(BuildContext context) {
    if (DB().displaySettings.isHistoryNavigationToolbarShown) {
      // Delay the dialog opening to ensure it happens after the current frame.
      Future<void>.delayed(const Duration(milliseconds: 100), () {
        if (context.mounted) {
          _openDialog(context, const MoveListDialog());
        }
      });
      // Return a placeholder widget to maintain return type consistency.
      return const SizedBox.shrink();
    }
    return MoveOptionsModal(mainContext: context);
  }

  /// Retrieves the history navigation toolbar items.
  List<ToolbarItem> _getHistoryNavToolbarItems(BuildContext context) {
    return <ToolbarItem>[
      ToolbarItem(
        key: const Key('play_area_history_nav_take_back_all'),
        child: Icon(FluentIcons.arrow_previous_24_regular,
            semanticLabel: S.of(context).takeBackAll),
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
          // If the game mode is humanVsLAN, request a LAN take-back
          if (GameController().gameInstance.gameMode == GameMode.humanVsLAN) {
            // Capture the ScaffoldMessenger now to use it later after await.
            final ScaffoldMessengerState scaffoldMessenger =
                ScaffoldMessenger.of(context);
            // Request a 1-step take-back and wait for the opponent's response.
            final bool accepted = await GameController().requestLanTakeBack(1);
            // Check if the widget is still mounted after the async gap.
            if (!mounted) {
              return;
            }
            if (accepted) {
              // Show a snackbar indicating the take-back was accepted.
              scaffoldMessenger.showSnackBar(
                const SnackBar(content: Text("Take back accepted")),
              );
            } else {
              // Show a snackbar indicating the take-back was rejected.
              scaffoldMessenger.showSnackBar(
                const SnackBar(content: Text("Take back rejected")),
              );
            }
          } else {
            // For non-LAN modes, simply perform the normal take-back action.
            HistoryNavigator.takeBack(context, pop: false, toolbar: true);
          }
        },
      ),
      if (!Constants.isSmallScreen(context))
        ToolbarItem(
          key: const Key('play_area_history_nav_move_now'),
          child: Icon(FluentIcons.play_24_regular,
              semanticLabel: S.of(context).moveNow),
          onPressed: () => GameController().moveNow(context),
        ),
      ToolbarItem(
        key: const Key('play_area_history_nav_step_forward'),
        child: Icon(FluentIcons.chevron_right_24_regular,
            semanticLabel: S.of(context).stepForward),
        onPressed: () =>
            HistoryNavigator.stepForward(context, pop: false, toolbar: true),
      ),
      ToolbarItem(
        key: const Key('play_area_history_nav_step_forward_all'),
        child: Icon(FluentIcons.arrow_next_24_regular,
            semanticLabel: S.of(context).stepForwardAll),
        onPressed: () =>
            HistoryNavigator.stepForwardAll(context, pop: false, toolbar: true),
      ),
    ];
  }

  /// Retrieves the analysis toolbar items.
  List<ToolbarItem> _getAnalysisToolbarItems(BuildContext context) {
    return <ToolbarItem>[
      ToolbarItem(
        key: const Key('play_area_analysis_toolbar_take_screenshot'),
        child: Icon(FluentIcons.camera_24_regular,
            semanticLabel: S.of(context).welcome),
        onPressed: () => _takeScreenshot("gallery"),
      ),
    ];
  }

  /// Generates a string of pieces based on the [count].
  String _getPiecesText(int count) {
    return "●" * count;
  }

  /// Builds the row displaying the count of pieces in hand.
  Widget _buildPieceCountRow() {
    return Row(
      key: const Key('play_area_piece_count_row'),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Semantics(
          label: S.of(context).inHand(
              !DB().generalSettings.aiMovesFirst
                  ? S.of(context).player2
                  : S.of(context).player1,
              GameController().position.pieceInHandCount[
                  !DB().generalSettings.aiMovesFirst
                      ? PieceColor.black
                      : PieceColor.white]!),
          child: Text(
            _getPiecesText(GameController().position.pieceInHandCount[
                !DB().generalSettings.aiMovesFirst
                    ? PieceColor.black
                    : PieceColor.white]!),
            key: const Key('play_area_piece_count_text_hand'),
            style: TextStyle(
              color: !DB().generalSettings.aiMovesFirst
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
              DB().ruleSettings.piecesCount -
                  GameController().position.pieceInHandCount[
                      !DB().generalSettings.aiMovesFirst
                          ? PieceColor.white
                          : PieceColor.black]! -
                  GameController().position.pieceOnBoardCount[
                      !DB().generalSettings.aiMovesFirst
                          ? PieceColor.white
                          : PieceColor.black]!,
            ),
            key: const Key('play_area_piece_count_text_remaining'),
            style: TextStyle(
              color: !DB().generalSettings.aiMovesFirst
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

  /// Builds the row displaying the count of removed pieces.
  Widget _buildRemovedPieceCountRow() {
    return Row(
      key: const Key('play_area_removed_piece_count_row'),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Semantics(
          label: S.of(context).welcome,
          child: Text(
            _getPiecesText(
              DB().ruleSettings.piecesCount -
                  GameController().position.pieceInHandCount[
                      !DB().generalSettings.aiMovesFirst
                          ? PieceColor.black
                          : PieceColor.white]! -
                  GameController().position.pieceOnBoardCount[
                      !DB().generalSettings.aiMovesFirst
                          ? PieceColor.black
                          : PieceColor.white]!,
            ),
            key: const Key('play_area_removed_piece_count_text_remaining'),
            style: TextStyle(
              color: !DB().generalSettings.aiMovesFirst
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
          label: S.of(context).inHand(
              !DB().generalSettings.aiMovesFirst
                  ? S.of(context).player1
                  : S.of(context).player2,
              GameController().position.pieceInHandCount[
                  !DB().generalSettings.aiMovesFirst
                      ? PieceColor.white
                      : PieceColor.black]!),
          child: Text(
            _getPiecesText(GameController().position.pieceInHandCount[
                !DB().generalSettings.aiMovesFirst
                    ? PieceColor.white
                    : PieceColor.black]!),
            key: const Key('play_area_removed_piece_count_text_hand'),
            style: TextStyle(
              color: !DB().generalSettings.aiMovesFirst
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
        // Calculate the dimension of the play area based on screen orientation.
        final double dimension = (constraints.maxWidth) *
            (MediaQuery.of(context).orientation == Orientation.portrait
                ? 1.0
                : 0.65);

        // Check if the toolbar should be displayed at the bottom.
        final bool isToolbarAtBottom = DB().displaySettings.isToolbarAtBottom;

        // The main column of the page content (without the bottom toolbars).
        final Widget mainContent = SizedBox(
          key: const Key('play_area_main_content'),
          width: dimension,
          child: SafeArea(
            top: MediaQuery.of(context).orientation == Orientation.portrait,
            bottom: !isToolbarAtBottom,
            // Disable bottom safe area if toolbar is at bottom
            right: false,
            left: false,
            child: SingleChildScrollView(
              key: const Key('play_area_single_child_scroll_view'),
              child: Column(
                key: const Key('play_area_column'),
                children: <Widget>[
                  GameHeader(key: const Key('play_area_game_header')),
                  // Display piece counts if needed
                  if ((DB().displaySettings.isUnplacedAndRemovedPiecesShown ||
                          GameController().gameInstance.gameMode ==
                              GameMode.setupPosition) &&
                      !(Constants.isSmallScreen(context) == true &&
                          DB().ruleSettings.piecesCount > 9))
                    _buildPieceCountRow()
                  else
                    const SizedBox(height: AppTheme.boardMargin),

                  // The game board
                  NativeScreenshot(
                    key: const Key('play_area_native_screenshot'),
                    controller: ScreenshotService.screenshotController,
                    child: Container(
                      key: const Key('play_area_game_board_container'),
                      alignment: Alignment.center,
                      child: GameBoard(
                        key: const Key('play_area_game_board'),
                        boardImage: widget.boardImage,
                      ),
                    ),
                  ),

                  // Display removed piece count if needed
                  if ((DB().displaySettings.isUnplacedAndRemovedPiecesShown ||
                          GameController().gameInstance.gameMode ==
                              GameMode.setupPosition) &&
                      !(Constants.isSmallScreen(context) == true &&
                          DB().ruleSettings.piecesCount > 9))
                    _buildRemovedPieceCountRow()
                  else
                    const SizedBox(height: AppTheme.boardMargin),

                  // Insert the advantage trend chart below the board and above the next toolbar rows.
                  // Only show if there's data.
                  if (DB().displaySettings.isAdvantageGraphShown &&
                      GameController().gameInstance.gameMode !=
                          GameMode.setupPosition &&
                      advantageData.isNotEmpty)
                    SizedBox(
                      key: const Key('play_area_advantage_graph'),
                      height: 150,
                      width: double.infinity,
                      child: CustomPaint(
                        key:
                            const Key('play_area_custom_paint_advantage_graph'),
                        painter: AdvantageGraphPainter(advantageData),
                      ),
                    ),

                  // Setup position toolbar if in setup mode and toolbar is not at bottom
                  if (GameController().gameInstance.gameMode ==
                          GameMode.setupPosition &&
                      !isToolbarAtBottom)
                    const SetupPositionToolbar(
                        key: Key('play_area_setup_position_toolbar')),

                  // History navigation toolbar if enabled, not in setup mode, and not at bottom
                  if (DB().displaySettings.isHistoryNavigationToolbarShown &&
                      GameController().gameInstance.gameMode !=
                          GameMode.setupPosition &&
                      !isToolbarAtBottom)
                    GamePageToolbar(
                      key: const Key('play_area_history_nav_toolbar'),
                      backgroundColor:
                          DB().colorSettings.navigationToolbarBackgroundColor,
                      itemColor: DB().colorSettings.navigationToolbarIconColor,
                      children: _buildToolbarItems(
                          context, _getHistoryNavToolbarItems(context)),
                    ),

                  // Analysis toolbar if enabled and not at bottom
                  if (DB().displaySettings.isAnalysisToolbarShown &&
                      !isToolbarAtBottom)
                    GamePageToolbar(
                      key: const Key('play_area_analysis_toolbar'),
                      backgroundColor:
                          DB().colorSettings.analysisToolbarBackgroundColor,
                      itemColor: DB().colorSettings.analysisToolbarIconColor,
                      children: _buildToolbarItems(
                          context, _getAnalysisToolbarItems(context)),
                    ),

                  // Main toolbar if not in setup mode and not at bottom
                  if (GameController().gameInstance.gameMode !=
                          GameMode.setupPosition &&
                      !isToolbarAtBottom)
                    GamePageToolbar(
                      key: const Key('play_area_main_toolbar'),
                      backgroundColor:
                          DB().colorSettings.mainToolbarBackgroundColor,
                      itemColor: DB().colorSettings.mainToolbarIconColor,
                      children: _buildToolbarItems(
                          context, _getMainToolbarItems(context)),
                    ),

                  const SizedBox(height: AppTheme.boardMargin),
                ],
              ),
            ),
          ),
        );

        // If toolbar should be at the bottom, separate them.
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

                  // Setup position toolbar if in setup mode
                  if (GameController().gameInstance.gameMode ==
                      GameMode.setupPosition)
                    const SetupPositionToolbar(
                        key: Key('play_area_setup_position_toolbar_bottom')),

                  // History navigation toolbar if enabled and not in setup mode
                  if (DB().displaySettings.isHistoryNavigationToolbarShown &&
                      GameController().gameInstance.gameMode !=
                          GameMode.setupPosition)
                    GamePageToolbar(
                      key: const Key('play_area_history_nav_toolbar_bottom'),
                      backgroundColor:
                          DB().colorSettings.navigationToolbarBackgroundColor,
                      itemColor: DB().colorSettings.navigationToolbarIconColor,
                      children: _buildToolbarItems(
                          context, _getHistoryNavToolbarItems(context)),
                    ),

                  // Analysis toolbar if enabled
                  if (DB().displaySettings.isAnalysisToolbarShown)
                    GamePageToolbar(
                      key: const Key('play_area_analysis_toolbar_bottom'),
                      backgroundColor:
                          DB().colorSettings.analysisToolbarBackgroundColor,
                      itemColor: DB().colorSettings.analysisToolbarIconColor,
                      children: _buildToolbarItems(
                          context, _getAnalysisToolbarItems(context)),
                    ),

                  // Main toolbar if not in setup mode
                  if (GameController().gameInstance.gameMode !=
                      GameMode.setupPosition)
                    GamePageToolbar(
                      key: const Key('play_area_main_toolbar_bottom'),
                      backgroundColor:
                          DB().colorSettings.mainToolbarBackgroundColor,
                      itemColor: DB().colorSettings.mainToolbarIconColor,
                      children: _buildToolbarItems(
                          context, _getMainToolbarItems(context)),
                    ),
                  const SizedBox(height: AppTheme.boardMargin),
                ],
              ),
            ),
          );
        }

        // If toolbar is not at the bottom, just return the main content.
        return mainContent;
      },
    );
  }
}
