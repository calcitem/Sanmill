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

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:native_screenshot_widget/native_screenshot_widget.dart';

import '../../appearance_settings/models/display_settings.dart';
import '../../custom_drawer/custom_drawer.dart';
import '../../game_page/services/mill.dart';
import '../../general_settings/models/general_settings.dart';
import '../../general_settings/widgets/general_settings_page.dart';
import '../../generated/intl/l10n.dart';
import '../../main.dart';
import '../../rule_settings/widgets/rule_settings_page.dart';
import '../../shared/config/constants.dart';
import '../../shared/database/database.dart';
import '../../shared/services/environment_config.dart';
import '../../shared/services/logger.dart';
import '../../shared/services/screenshot_service.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/themes/ui_colors.dart';
import '../../shared/utils/helpers/string_helpers/string_buffer_helper.dart';
import '../../shared/widgets/custom_spacer.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../services/painters/painters.dart';
import 'toolbars/game_toolbar.dart';

part 'board_semantics.dart';
part 'dialogs/game_result_alert_dialog.dart';
part 'dialogs/info_dialog.dart';
part 'dialogs/move_list_dialog.dart';
part 'game_board.dart';
part 'game_header.dart';
part 'game_page_action_sheet.dart';
part 'modals/game_options_modal.dart';
part 'modals/move_options_modal.dart';

class GamePage extends StatelessWidget {
  GamePage(this.gameMode, {super.key}) {
    Position.resetScore();
  }

  final GameMode gameMode;

  @override
  Widget build(BuildContext context) {
    final GameController controller = GameController();
    controller.gameInstance.gameMode = gameMode;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: <Widget>[
          // Background image or color
          _buildBackground(),
          // Game board
          _buildGameBoard(context, controller),
          // Drawer icon
          Align(
            alignment: AlignmentDirectional.topStart,
            child: SafeArea(child: CustomDrawerIcon.of(context)!.drawerIcon),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    if (DB().displaySettings.backgroundImagePath.isEmpty) {
      return Container(
        color: DB().colorSettings.darkBackgroundColor,
      );
    } else {
      return Image.asset(
        DB().displaySettings.backgroundImagePath,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder:
            (BuildContext context, Object error, StackTrace? stackTrace) {
          return Container(
            color: DB().colorSettings.darkBackgroundColor,
          );
        },
      );
    }
  }

  Widget _buildGameBoard(BuildContext context, GameController controller) {
    return OrientationBuilder(
      builder: (BuildContext context, Orientation orientation) {
        final bool isLandscape = orientation == Orientation.landscape;

        return Align(
          alignment: isLandscape ? Alignment.center : Alignment.topCenter,
          child: FutureBuilder<void>(
            future: controller.startController(),
            builder: (BuildContext context, AsyncSnapshot<Object?> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center();
              }

              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.boardMargin),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double toolbarHeight =
                        _calculateToolbarHeight(context);

                    // Constraints of the game board but applied to the entire child
                    final double maxWidth = constraints.maxWidth;
                    final double maxHeight =
                        constraints.maxHeight - toolbarHeight;
                    final BoxConstraints constraint = BoxConstraints(
                      maxWidth: (maxHeight > 0 && maxHeight < maxWidth)
                          ? maxHeight
                          : maxWidth,
                    );

                    return ConstrainedBox(
                      constraints: constraint,
                      child: const _Game(),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  double _calculateToolbarHeight(BuildContext context) {
    double toolbarHeight =
        GamePageToolbar.height + ButtonTheme.of(context).height;
    if (DB().displaySettings.isHistoryNavigationToolbarShown) {
      toolbarHeight *= 2;
    } else if (DB().displaySettings.isAnalysisToolbarShown) {
      toolbarHeight *= 3;
    }
    return toolbarHeight;
  }
}

class _Game extends StatefulWidget {
  const _Game();

  @override
  _GameState createState() => _GameState();
}

class _GameState extends State<_Game> {
  @override
  void initState() {
    super.initState();
    GameController().headerIconsNotifier.addListener(_showPieceIndicator);
  }

  @override
  void dispose() {
    GameController().headerIconsNotifier.removeListener(_showPieceIndicator);
    super.dispose();
  }

  void _showPieceIndicator() {
    setState(() {});
  }

  Future<void> _triggerScreenshot(String storageLocation,
      [String? filename]) async {
    await ScreenshotService.takeScreenshot(storageLocation, filename);
  }

  void _showGameModalBottomSheet(BuildContext context) {
    logger.i("Game modal bottom sheet opened");
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.modalBottomSheetBackgroundColor,
      builder: (_) => _GameOptionsModal(
        onTriggerScreenshot: () => _triggerScreenshot("gallery"),
      ),
    );
  }

  void _showGeneralSettings(BuildContext context) {
    logger.i("General settings page opened");
    Navigator.push(
      context,
      MaterialPageRoute<GeneralSettingsPage>(
          builder: (_) => const GeneralSettingsPage()),
    );
  }

  void _showMoveModalBottomSheet(BuildContext context) {
    logger.i("Move modal bottom sheet opened");
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.modalBottomSheetBackgroundColor,
      builder: (_) => _MoveOptionsModal(mainContext: context),
    );
  }

  void _showInfoDialog(BuildContext context) {
    logger.i("Info dialog opened");
    showDialog(
      context: context,
      builder: (_) => const _InfoDialog(),
    );
  }

  List<Widget> _buildMainToolbarItems(BuildContext context) {
    final ToolbarItem gameButton = ToolbarItem.icon(
      onPressed: () => _showGameModalBottomSheet(context),
      icon: const Icon(FluentIcons.table_simple_24_regular),
      label: Text(
        S.of(context).game,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final ToolbarItem optionsButton = ToolbarItem.icon(
      onPressed: () => _showGeneralSettings(context),
      icon: const Icon(FluentIcons.settings_24_regular),
      label: Text(
        S.of(context).options,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final ToolbarItem moveButton = ToolbarItem.icon(
      onPressed: () {
        if (DB().displaySettings.isHistoryNavigationToolbarShown) {
          Future<void>.delayed(const Duration(milliseconds: 100), () {
            if (!context.mounted) {
              return;
            }
            showDialog<void>(
              context: context,
              builder: (BuildContext context) => const _MoveListDialog(),
            );
          });
        } else {
          _showMoveModalBottomSheet(context);
        }
      },
      icon: const Icon(FluentIcons.calendar_agenda_24_regular),
      label: Text(
        S.of(context).move,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final ToolbarItem infoButton = ToolbarItem.icon(
      onPressed: () => _showInfoDialog(context),
      icon: const Icon(FluentIcons.book_information_24_regular),
      label: Text(
        S.of(context).info,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return <Widget>[
      Expanded(child: gameButton),
      Expanded(child: optionsButton),
      Expanded(child: moveButton),
      Expanded(child: infoButton),
    ];
  }

  List<Widget> _buildHistoryNavToolbarItems(BuildContext context) {
    final ToolbarItem takeBackAllButton = ToolbarItem(
      child: Icon(
        FluentIcons.arrow_previous_24_regular,
        semanticLabel: S.of(context).takeBackAll,
      ),
      onPressed: () =>
          HistoryNavigator.takeBackAll(context, pop: false, toolbar: true),
    );

    final ToolbarItem takeBackButton = ToolbarItem(
      child: Icon(
        FluentIcons.chevron_left_24_regular,
        semanticLabel: S.of(context).takeBack,
      ),
      onPressed: () =>
          HistoryNavigator.takeBack(context, pop: false, toolbar: true),
    );

    final ToolbarItem moveNowButton = ToolbarItem(
      child: Icon(
        FluentIcons.play_24_regular,
        semanticLabel: S.of(context).moveNow,
      ),
      onPressed: () => GameController().moveNow(context),
    );

    final ToolbarItem stepForwardButton = ToolbarItem(
      child: Icon(
        FluentIcons.chevron_right_24_regular,
        semanticLabel: S.of(context).stepForward,
      ),
      onPressed: () =>
          HistoryNavigator.stepForward(context, pop: false, toolbar: true),
    );

    final ToolbarItem stepForwardAllButton = ToolbarItem(
      child: Icon(
        FluentIcons.arrow_next_24_regular,
        semanticLabel: S.of(context).stepForwardAll,
      ),
      onPressed: () =>
          HistoryNavigator.stepForwardAll(context, pop: false, toolbar: true),
    );

    return <Widget>[
      Expanded(child: takeBackAllButton),
      Expanded(child: takeBackButton),
      if (Constants.isSmallScreen(context) == false)
        Expanded(child: moveNowButton),
      Expanded(child: stepForwardButton),
      Expanded(child: stepForwardAllButton),
    ];
  }

  List<Widget> _buildAnalysisToolbarItems(BuildContext context) {
    final ToolbarItem captureBoardImageButton = ToolbarItem(
      child: Icon(
        FluentIcons.camera_24_regular,
        semanticLabel: S.of(context).welcome, // TODO: Update semantic label
      ),
      onPressed: () => _triggerScreenshot("gallery"),
    );

    return <Widget>[
      Expanded(child: captureBoardImageButton),
    ];
  }

  String _getPiecesText(int count) {
    return "●" * count;
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
                      children: _buildHistoryNavToolbarItems(context),
                    ),
                  if (DB().displaySettings.isAnalysisToolbarShown)
                    GamePageToolbar(
                      backgroundColor:
                          DB().colorSettings.analysisToolbarBackgroundColor,
                      itemColor: DB().colorSettings.analysisToolbarIconColor,
                      children: _buildAnalysisToolbarItems(context),
                    ),
                  if (GameController().gameInstance.gameMode !=
                      GameMode.setupPosition)
                    GamePageToolbar(
                      backgroundColor:
                          DB().colorSettings.mainToolbarBackgroundColor,
                      itemColor: DB().colorSettings.mainToolbarIconColor,
                      children: _buildMainToolbarItems(context),
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
                        : PieceColor.white]!,
              ),
          child: Text(
            _getPiecesText(
              GameController().position.pieceInHandCount[
                  !DB().generalSettings.aiMovesFirst
                      ? PieceColor.black
                      : PieceColor.white]!,
            ),
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
          label: S.of(context).welcome, // TODO: Removed pieces count
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
          label: S.of(context).welcome, // TODO: Removed pieces count
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
                        : PieceColor.black]!,
              ),
          child: Text(
            _getPiecesText(
              GameController().position.pieceInHandCount[
                  !DB().generalSettings.aiMovesFirst
                      ? PieceColor.white
                      : PieceColor.black]!,
            ),
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
}
