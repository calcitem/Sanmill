// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

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
      if (GameController().gameRecorder.isEmpty) {
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
        onPressed: () => _openModal(
            context,
            GameOptionsModal(
                onTriggerScreenshot: () => _takeScreenshot("gallery"))),
        icon: const Icon(FluentIcons.table_simple_24_regular),
        label: Text(S.of(context).game,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      ToolbarItem.icon(
        onPressed: () => _navigateToSettings(context),
        icon: const Icon(FluentIcons.settings_24_regular),
        label: Text(S.of(context).options,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      ToolbarItem.icon(
        onPressed: () => _openModal(context, _buildMoveModal(context)),
        icon: const Icon(FluentIcons.calendar_agenda_24_regular),
        label: Text(S.of(context).move,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      ToolbarItem.icon(
        onPressed: () => _openDialog(context, const InfoDialog()),
        icon: const Icon(FluentIcons.book_information_24_regular),
        label: Text(S.of(context).info,
            maxLines: 1, overflow: TextOverflow.ellipsis),
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
        child: Icon(FluentIcons.arrow_previous_24_regular,
            semanticLabel: S.of(context).takeBackAll),
        onPressed: () =>
            HistoryNavigator.takeBackAll(context, pop: false, toolbar: true),
      ),
      ToolbarItem(
        child: Icon(FluentIcons.chevron_left_24_regular,
            semanticLabel: S.of(context).takeBack),
        onPressed: () =>
            HistoryNavigator.takeBack(context, pop: false, toolbar: true),
      ),
      if (!Constants.isSmallScreen(context))
        ToolbarItem(
          child: Icon(FluentIcons.play_24_regular,
              semanticLabel: S.of(context).moveNow),
          onPressed: () => GameController().moveNow(context),
        ),
      ToolbarItem(
        child: Icon(FluentIcons.chevron_right_24_regular,
            semanticLabel: S.of(context).stepForward),
        onPressed: () =>
            HistoryNavigator.stepForward(context, pop: false, toolbar: true),
      ),
      ToolbarItem(
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
            style: TextStyle(
              color: !DB().generalSettings.aiMovesFirst
                  ? DB().colorSettings.whitePieceColor.withOpacity(0.8)
                  : DB().colorSettings.blackPieceColor.withOpacity(0.8),
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
            style: TextStyle(
              color: !DB().generalSettings.aiMovesFirst
                  ? DB().colorSettings.blackPieceColor.withOpacity(0.8)
                  : DB().colorSettings.whitePieceColor.withOpacity(0.8),
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
          width: dimension,
          child: SafeArea(
            top: MediaQuery.of(context).orientation == Orientation.portrait,
            bottom:
                !isToolbarAtBottom, // Disable bottom safe area if toolbar is at bottom
            right: false,
            left: false,
            child: SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  GameHeader(),
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
                    controller: ScreenshotService.screenshotController,
                    child: Container(
                      alignment: Alignment.center,
                      child: GameBoard(
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
                      advantageData.isNotEmpty)
                    SizedBox(
                      height: 150,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: AdvantageGraphPainter(advantageData),
                      ),
                    ),

                  // Setup position toolbar if in setup mode and toolbar is not at bottom
                  if (GameController().gameInstance.gameMode ==
                          GameMode.setupPosition &&
                      !isToolbarAtBottom)
                    const SetupPositionToolbar(),

                  // History navigation toolbar if enabled, not in setup mode, and not at bottom
                  if (DB().displaySettings.isHistoryNavigationToolbarShown &&
                      GameController().gameInstance.gameMode !=
                          GameMode.setupPosition &&
                      !isToolbarAtBottom)
                    GamePageToolbar(
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
            width: dimension,
            child: SafeArea(
              top: MediaQuery.of(context).orientation == Orientation.portrait,
              right: false,
              left: false,
              child: Column(
                children: <Widget>[
                  Expanded(child: mainContent),

                  // Setup position toolbar if in setup mode
                  if (GameController().gameInstance.gameMode ==
                      GameMode.setupPosition)
                    const SetupPositionToolbar(),

                  // History navigation toolbar if enabled and not in setup mode
                  if (DB().displaySettings.isHistoryNavigationToolbarShown &&
                      GameController().gameInstance.gameMode !=
                          GameMode.setupPosition)
                    GamePageToolbar(
                      backgroundColor:
                          DB().colorSettings.navigationToolbarBackgroundColor,
                      itemColor: DB().colorSettings.navigationToolbarIconColor,
                      children: _buildToolbarItems(
                          context, _getHistoryNavToolbarItems(context)),
                    ),

                  // Analysis toolbar if enabled
                  if (DB().displaySettings.isAnalysisToolbarShown)
                    GamePageToolbar(
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
