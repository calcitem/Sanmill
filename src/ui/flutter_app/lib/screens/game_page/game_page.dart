// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:catcher/catcher.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

import '../../generated/intl/l10n.dart';
import '../../main.dart';
import '../../models/display_settings.dart';
import '../../models/general_settings.dart';
import '../../services/database/database.dart';
import '../../services/environment_config.dart';
import '../../services/logger.dart';
import '../../services/mill/mill.dart';
import '../../shared/constants.dart';
import '../../shared/custom_drawer/custom_drawer.dart';
import '../../shared/custom_spacer.dart';
import '../../shared/game_toolbar/game_toolbar.dart';
import '../../shared/number_picker.dart';
import '../../shared/painters/painters.dart';
import '../../shared/scaffold_messenger.dart';
import '../../shared/string_buffer_helper.dart';
import '../../shared/theme/app_theme.dart';
import '../general_settings/general_settings_page.dart';
import '../rule_settings/rule_settings_page.dart';

part './board.dart';
part './game_options_modal.dart';
part './header.dart';
part './info_dialog.dart';
part './move_list_dialog.dart';
part './move_options_modal.dart';
part './result_alert.dart';
part 'game_page_action_sheet.dart';

class GamePage extends StatelessWidget {
  GamePage(this.gameMode, {super.key}) {
    Position.resetScore();
  }

  final GameMode gameMode;

  final bool isSettingsPosition = true;

  @override
  Widget build(BuildContext context) {
    final MillController controller = MillController();

    controller.gameInstance.gameMode = gameMode;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DB().colorSettings.darkBackgroundColor,
      // ignore: always_specify_types
      body: Stack(
        children: <Widget>[
          Align(
            alignment:
                MediaQuery.of(context).orientation == Orientation.landscape
                    ? Alignment.center
                    : Alignment.topCenter,
            child: FutureBuilder<void>(
              future: controller.start(),
              builder: (BuildContext context, AsyncSnapshot<Object?> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      //child: CircularProgressIndicator.adaptive(),
                      );
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.boardMargin),
                  child: LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                      double toolbarHeight = GamePageToolBar.height +
                          ButtonTheme.of(context).height;
                      if (DB()
                          .displaySettings
                          .isHistoryNavigationToolbarShown) {
                        toolbarHeight *= 2;
                      }
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
          ),
          Align(
            alignment: AlignmentDirectional.topStart,
            child: SafeArea(child: DrawerIcon.of(context)!.icon),
          ),
        ],
      ),
    );
  }
}

// TODO: [Leptopoda] Change layout (landscape mode, padding on small devices)
class _Game extends StatefulWidget {
  const _Game();
  @override
  State<_Game> createState() => _GameState();
}

class _GameState extends State<_Game> {
  @override
  void initState() {
    super.initState();
    MillController().headerIconsNotifier.addListener(_showPieceIndicator);
  }

  @override
  void dispose() {
    MillController().headerIconsNotifier.removeListener(_showPieceIndicator);
    super.dispose();
  }

  void _showPieceIndicator() {
    setState(() {}); // TODO: Only refresh PieceIndicator.
  }

  void _showGameModalBottomSheet(BuildContext context) => showModalBottomSheet(
        context: context,
        backgroundColor: AppTheme.modalBottomSheetBackgroundColor,
        builder: (_) => const _GameOptionsModal(),
      );

  void _showGeneralSettings(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute<GeneralSettingsPage>(
            builder: (_) => const GeneralSettingsPage()),
      );

  void _showMoveModalBottomSheet(BuildContext context) => showModalBottomSheet(
        context: context,
        backgroundColor: AppTheme.modalBottomSheetBackgroundColor,
        builder: (_) => _MoveOptionsModal(mainContext: context),
      );

  void _showInfoDialog(BuildContext context) => showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => const _InfoDialog(),
      );

  // Icons: https://github.com/microsoft/fluentui-system-icons/blob/main/icons_regular.md

  List<Widget> mainToolbarItems(BuildContext context) {
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
      onPressed: () => _showMoveModalBottomSheet(context),
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

  List<Widget> historyNavToolbarItems(BuildContext context) {
    final ToolbarItem takeBackAllButton = ToolbarItem(
      child: Icon(
        FluentIcons.arrow_previous_24_regular,
        semanticLabel: S.of(context).takeBackAll,
      ),
      onPressed: () => HistoryNavigator.takeBackAll(context, pop: false),
    );

    final ToolbarItem takeBackButton = ToolbarItem(
      child: Icon(
        FluentIcons.chevron_left_24_regular,
        semanticLabel: S.of(context).takeBack,
      ),
      onPressed: () => HistoryNavigator.takeBack(context, pop: false),
    );

    final ToolbarItem moveNowButton = ToolbarItem(
      child: Icon(
        FluentIcons.play_24_regular,
        semanticLabel: S.of(context).moveNow,
      ),
      onPressed: () => MillController().moveNow(context),
    );

    final ToolbarItem stepForwardButton = ToolbarItem(
      child: Icon(
        FluentIcons.chevron_right_24_regular,
        semanticLabel: S.of(context).stepForward,
      ),
      onPressed: () => HistoryNavigator.stepForward(context, pop: false),
    );

    final ToolbarItem stepForwardAllButton = ToolbarItem(
      child: Icon(
        FluentIcons.arrow_next_24_regular,
        semanticLabel: S.of(context).stepForwardAll,
      ),
      onPressed: () => HistoryNavigator.stepForwardAll(context, pop: false),
    );

    return <Widget>[
      Expanded(child: takeBackAllButton),
      Expanded(child: takeBackButton),
      if (Constants.isSmallScreen == false) Expanded(child: moveNowButton),
      Expanded(child: stepForwardButton),
      Expanded(child: stepForwardAllButton),
    ];
  }

  String getPiecesText(int count) {
    String ret = "";
    for (int i = 0; i < count; i++) {
      ret = "$ret●";
    }
    return ret;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constrains) {
      final double dimension = (constrains.maxWidth) *
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
                        MillController().gameInstance.gameMode ==
                            GameMode.setupPosition) &&
                    !(Constants.isSmallScreen == true &&
                        DB().ruleSettings.piecesCount > 9))
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          getPiecesText(
                              MillController().position.pieceInHandCount[
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
                        Text(
                          getPiecesText(DB().ruleSettings.piecesCount -
                              MillController().position.pieceInHandCount[
                                  !DB().generalSettings.aiMovesFirst
                                      ? PieceColor.white
                                      : PieceColor.black]! -
                              MillController().position.pieceOnBoardCount[
                                  !DB().generalSettings.aiMovesFirst
                                      ? PieceColor.white
                                      : PieceColor.black]!),
                          style: TextStyle(
                            color: !DB().generalSettings.aiMovesFirst
                                ? DB()
                                    .colorSettings
                                    .whitePieceColor
                                    .withOpacity(0.8)
                                : DB()
                                    .colorSettings
                                    .blackPieceColor
                                    .withOpacity(0.8),
                            shadows: const <Shadow>[
                              Shadow(
                                offset: Offset(1.0, 1.0),
                                blurRadius: 3.0,
                                color: Color.fromARGB(255, 128, 128, 128),
                              ),
                            ],
                          ),
                        )
                      ])
                else
                  const SizedBox(height: AppTheme.boardMargin),
                const Board(),
                if ((DB().displaySettings.isUnplacedAndRemovedPiecesShown ||
                        MillController().gameInstance.gameMode ==
                            GameMode.setupPosition) &&
                    !(Constants.isSmallScreen == true &&
                        DB().ruleSettings.piecesCount > 9))
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                            getPiecesText(DB().ruleSettings.piecesCount -
                                MillController().position.pieceInHandCount[
                                    !DB().generalSettings.aiMovesFirst
                                        ? PieceColor.black
                                        : PieceColor.white]! -
                                MillController().position.pieceOnBoardCount[
                                    !DB().generalSettings.aiMovesFirst
                                        ? PieceColor.black
                                        : PieceColor.white]!),
                            style: TextStyle(
                              color: !DB().generalSettings.aiMovesFirst
                                  ? DB()
                                      .colorSettings
                                      .blackPieceColor
                                      .withOpacity(0.8)
                                  : DB()
                                      .colorSettings
                                      .whitePieceColor
                                      .withOpacity(0.8),
                              shadows: const <Shadow>[
                                Shadow(
                                  offset: Offset(1.0, 1.0),
                                  blurRadius: 3.0,
                                  color: Color.fromARGB(255, 128, 128, 128),
                                ),
                              ],
                            )),
                        Text(
                            getPiecesText(
                                MillController().position.pieceInHandCount[
                                    !DB().generalSettings.aiMovesFirst
                                        ? PieceColor.white
                                        : PieceColor.black]!),
                            style: TextStyle(
                              color: DB().generalSettings.aiMovesFirst
                                  ? DB().colorSettings.blackPieceColor
                                  : DB().colorSettings.whitePieceColor,
                              shadows: const <Shadow>[
                                Shadow(
                                  offset: Offset(1.0, 1.0),
                                  blurRadius: 3.0,
                                  color: Color.fromARGB(255, 128, 128, 128),
                                ),
                              ],
                            ))
                      ])
                else
                  const SizedBox(height: AppTheme.boardMargin),
                if (MillController().gameInstance.gameMode ==
                    GameMode.setupPosition)
                  const SetupPositionToolBar(),
                if (DB().displaySettings.isHistoryNavigationToolbarShown &&
                    MillController().gameInstance.gameMode !=
                        GameMode.setupPosition)
                  GamePageToolBar(
                    backgroundColor:
                        DB().colorSettings.navigationToolbarBackgroundColor,
                    itemColor: DB().colorSettings.navigationToolbarIconColor,
                    children: historyNavToolbarItems(context),
                  ),
                if (MillController().gameInstance.gameMode !=
                    GameMode.setupPosition)
                  GamePageToolBar(
                    backgroundColor:
                        DB().colorSettings.mainToolbarBackgroundColor,
                    itemColor: DB().colorSettings.mainToolbarIconColor,
                    children: mainToolbarItems(context),
                  ),
                const SizedBox(height: AppTheme.boardMargin),
              ],
            ),
          ),
        ),
      );
    });
  }
}
