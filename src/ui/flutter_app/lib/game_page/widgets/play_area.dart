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
import 'game_page.dart';
import 'modals/game_options_modal.dart';
import 'toolbars/game_toolbar.dart';

class PlayArea extends StatefulWidget {
  const PlayArea({super.key});

  @override
  PlayAreaState createState() => PlayAreaState();
}

class PlayAreaState extends State<PlayArea> {
  @override
  void initState() {
    super.initState();
    GameController().headerIconsNotifier.addListener(_updateUI);
  }

  @override
  void dispose() {
    GameController().headerIconsNotifier.removeListener(_updateUI);
    super.dispose();
  }

  void _updateUI() {
    setState(() {});
  }

  Future<void> _takeScreenshot(String storageLocation,
      [String? filename]) async {
    await ScreenshotService.takeScreenshot(storageLocation, filename);
  }

  void _openModal(BuildContext context, Widget modal) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.modalBottomSheetBackgroundColor,
      builder: (_) => modal,
    );
  }

  void _navigateToSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<GeneralSettingsPage>(
          builder: (_) => const GeneralSettingsPage()),
    );
  }

  void _openDialog(BuildContext context, Widget dialog) {
    showDialog(
      context: context,
      builder: (_) => dialog,
    );
  }

  List<Widget> _buildToolbarItems(
      BuildContext context, List<ToolbarItem> items) {
    return items.map((ToolbarItem item) => Expanded(child: item)).toList();
  }

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

  Widget _buildMoveModal(BuildContext context) {
    if (DB().displaySettings.isHistoryNavigationToolbarShown) {
      Future<void>.delayed(const Duration(milliseconds: 100), () {
        if (context.mounted) {
          _openDialog(context, const MoveListDialog());
        }
      });
      // Return a placeholder widget or something appropriate to maintain return type consistency
      return const SizedBox.shrink(); // Returns an empty widget
    }
    return MoveOptionsModal(mainContext: context);
  }

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

  List<ToolbarItem> _getAnalysisToolbarItems(BuildContext context) {
    return <ToolbarItem>[
      ToolbarItem(
        child: Icon(FluentIcons.camera_24_regular,
            semanticLabel: S.of(context).welcome),
        onPressed: () => _takeScreenshot("gallery"),
      ),
    ];
  }

  String _getPiecesText(int count) {
    return "●" * count;
  }

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
        final double dimension = (constraints.maxWidth) *
            (MediaQuery.of(context).orientation == Orientation.portrait
                ? 1.0
                : 0.65);

        return SizedBox(
          width: dimension,
          child: SafeArea(
            top: MediaQuery.of(context).orientation == Orientation.portrait,
            bottom: false,
            right: false,
            left: false,
            child: SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  GameHeader(),
                  if ((DB().displaySettings.isUnplacedAndRemovedPiecesShown ||
                          GameController().gameInstance.gameMode ==
                              GameMode.setupPosition) &&
                      !(Constants.isSmallScreen(context) == true &&
                          DB().ruleSettings.piecesCount > 9))
                    _buildPieceCountRow()
                  else
                    const SizedBox(height: AppTheme.boardMargin),
                  NativeScreenshot(
                    controller: ScreenshotService.screenshotController,
                    child: Container(
                      alignment: Alignment.center,
                      child: const GameBoard(),
                    ),
                  ),
                  if ((DB().displaySettings.isUnplacedAndRemovedPiecesShown ||
                          GameController().gameInstance.gameMode ==
                              GameMode.setupPosition) &&
                      !(Constants.isSmallScreen(context) == true &&
                          DB().ruleSettings.piecesCount > 9))
                    _buildRemovedPieceCountRow()
                  else
                    const SizedBox(height: AppTheme.boardMargin),
                  if (GameController().gameInstance.gameMode ==
                      GameMode.setupPosition)
                    const SetupPositionToolbar(),
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
                  if (DB().displaySettings.isAnalysisToolbarShown)
                    GamePageToolbar(
                      backgroundColor:
                          DB().colorSettings.analysisToolbarBackgroundColor,
                      itemColor: DB().colorSettings.analysisToolbarIconColor,
                      children: _buildToolbarItems(
                          context, _getAnalysisToolbarItems(context)),
                    ),
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
          ),
        );
      },
    );
  }
}
