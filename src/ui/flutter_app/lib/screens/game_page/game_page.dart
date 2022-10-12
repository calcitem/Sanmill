// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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
import 'dart:ui';

import 'package:catcher/catcher.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/main.dart';
import 'package:sanmill/models/general_settings.dart';
import 'package:sanmill/screens/general_settings/general_settings_page.dart';
import 'package:sanmill/screens/rule_settings/rule_settings_page.dart';
import 'package:sanmill/services/database/database.dart';
import 'package:sanmill/services/environment_config.dart';
import 'package:sanmill/services/logger.dart';
import 'package:sanmill/services/mill/mill.dart';
import 'package:sanmill/shared/constants.dart';
import 'package:sanmill/shared/custom_drawer/custom_drawer.dart';
import 'package:sanmill/shared/custom_spacer.dart';
import 'package:sanmill/shared/game_toolbar/game_toolbar.dart';
import 'package:sanmill/shared/number_picker.dart';
import 'package:sanmill/shared/painters/painters.dart';
import 'package:sanmill/shared/scaffold_messenger.dart';
import 'package:sanmill/shared/string_buffer_helper.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

part './board.dart';
part './game_options_modal.dart';
part './header.dart';
part './info_dialog.dart';
part './move_list_dialog.dart';
part './move_options_modal.dart';
part './result_alert.dart';
part 'game_page_action_sheet.dart';

class GamePage extends StatelessWidget {
  final GameMode gameMode;

  final bool isSettingsPosition = true;

  GamePage(this.gameMode, {Key? key}) : super(key: key) {
    Position.resetScore();
  }

  @override
  Widget build(BuildContext context) {
    final controller = MillController();

    controller.gameInstance.gameMode = gameMode;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DB().colorSettings.darkBackgroundColor,
      body: FutureBuilder(
        future: controller.start(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                //child: CircularProgressIndicator.adaptive(),
                );
          }

          return Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppTheme.boardMargin),
            child: LayoutBuilder(
              builder: (context, constraints) {
                var toolbarHeight =
                    GamePageToolBar.height + ButtonTheme.of(context).height;
                if (DB().displaySettings.isHistoryNavigationToolbarShown) {
                  toolbarHeight *= 2;
                }

                // Constraints of the game board but applied to the entire child
                final maxWidth = constraints.maxWidth;
                final maxHeight = constraints.maxHeight - toolbarHeight;
                final BoxConstraints constraint = BoxConstraints(
                  maxWidth: (maxHeight > 0 && maxHeight < maxWidth)
                      ? maxHeight
                      : maxWidth,
                );

                return Center(
                  child: ConstrainedBox(
                    constraints: constraint,
                    child: const SingleChildScrollView(child: _Game()),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// TODO: [Leptopoda] Change layout (landscape mode, padding on small devices)
class _Game extends StatefulWidget {
  const _Game({Key? key}) : super(key: key);
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
        MaterialPageRoute(builder: (_) => const GeneralSettingsPage()),
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
    final gameButton = ToolbarItem.icon(
      onPressed: () => _showGameModalBottomSheet(context),
      icon: const Icon(FluentIcons.table_simple_24_regular),
      label: Text(S.of(context).game),
    );

    final optionsButton = ToolbarItem.icon(
      onPressed: () => _showGeneralSettings(context),
      icon: const Icon(FluentIcons.settings_24_regular),
      label: Text(S.of(context).options),
    );

    final moveButton = ToolbarItem.icon(
      onPressed: () => _showMoveModalBottomSheet(context),
      icon: const Icon(FluentIcons.calendar_agenda_24_regular),
      label: Text(S.of(context).move),
    );

    final infoButton = ToolbarItem.icon(
      onPressed: () => _showInfoDialog(context),
      icon: const Icon(FluentIcons.book_information_24_regular),
      label: Text(S.of(context).info),
    );

    return <Widget>[
      gameButton,
      optionsButton,
      moveButton,
      infoButton,
    ];
  }

  List<Widget> historyNavToolbarItems(BuildContext context) {
    final takeBackAllButton = ToolbarItem(
      child: Icon(
        FluentIcons.arrow_previous_24_regular,
        semanticLabel: S.of(context).takeBackAll,
      ),
      onPressed: () => HistoryNavigator.takeBackAll(context, pop: false),
    );

    final takeBackButton = ToolbarItem(
      child: Icon(
        FluentIcons.chevron_left_24_regular,
        semanticLabel: S.of(context).takeBack,
      ),
      onPressed: () => HistoryNavigator.takeBack(context, pop: false),
    );

    final moveNowButton = ToolbarItem(
      child: Icon(
        FluentIcons.play_24_regular,
        semanticLabel: S.of(context).moveNow,
      ),
      onPressed: () => MillController().moveNow(context),
    );

    final stepForwardButton = ToolbarItem(
      child: Icon(
        FluentIcons.chevron_right_24_regular,
        semanticLabel: S.of(context).stepForward,
      ),
      onPressed: () => HistoryNavigator.stepForward(context, pop: false),
    );

    final stepForwardAllButton = ToolbarItem(
      child: Icon(
        FluentIcons.arrow_next_24_regular,
        semanticLabel: S.of(context).stepForwardAll,
      ),
      onPressed: () => HistoryNavigator.stepForwardAll(context, pop: false),
    );

    return <Widget>[
      takeBackAllButton,
      takeBackButton,
      moveNowButton,
      stepForwardButton,
      stepForwardAllButton,
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
    return Column(
      children: <Widget>[
        GameHeader(),
        //const SizedBox(height: AppTheme.boardMargin),
        Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                  getPiecesText(MillController().position.pieceInHandCount[
                      !DB().generalSettings.aiMovesFirst
                          ? PieceColor.black
                          : PieceColor.white]!),
                  style: TextStyle(
                      color: !DB().generalSettings.aiMovesFirst
                          ? DB().colorSettings.blackPieceColor
                          : DB().colorSettings.whitePieceColor)),
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
                          ? DB().colorSettings.whitePieceColor.withOpacity(0.8)
                          : DB()
                              .colorSettings
                              .blackPieceColor
                              .withOpacity(0.8)))
            ]),
        const Board(),
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
                          ? DB().colorSettings.blackPieceColor.withOpacity(0.8)
                          : DB()
                              .colorSettings
                              .whitePieceColor
                              .withOpacity(0.8))),
              Text(
                  getPiecesText(MillController().position.pieceInHandCount[
                      !DB().generalSettings.aiMovesFirst
                          ? PieceColor.white
                          : PieceColor.black]!),
                  style: TextStyle(
                      color: DB().generalSettings.aiMovesFirst
                          ? DB().colorSettings.blackPieceColor
                          : DB().colorSettings.whitePieceColor))
            ]),
        //const SizedBox(height: AppTheme.boardMargin),
        if (MillController().gameInstance.gameMode == GameMode.setupPosition)
          const SetupPositionToolBar(),
        if (DB().displaySettings.isHistoryNavigationToolbarShown &&
            MillController().gameInstance.gameMode != GameMode.setupPosition)
          GamePageToolBar(
            backgroundColor:
                DB().colorSettings.navigationToolbarBackgroundColor,
            itemColor: DB().colorSettings.navigationToolbarIconColor,
            children: historyNavToolbarItems(context),
          ),
        if (MillController().gameInstance.gameMode != GameMode.setupPosition)
          GamePageToolBar(
            backgroundColor: DB().colorSettings.mainToolbarBackgroundColor,
            itemColor: DB().colorSettings.mainToolbarIconColor,
            children: mainToolbarItems(context),
          ),
      ],
    );
  }
}
