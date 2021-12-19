/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/models/preferences.dart';
import 'package:sanmill/screens/game_settings/game_settings_page.dart';
import 'package:sanmill/services/environment_config.dart';
import 'package:sanmill/services/logger.dart';
import 'package:sanmill/services/mill/mill.dart';
import 'package:sanmill/services/mill/src/tap_handler.dart';
import 'package:sanmill/services/storage/storage.dart';
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
part './info_dialog.dart';
part './move_list_dialog.dart';
part './result_alert.dart';
part './game_options_modal.dart';
part './move_options_modal.dart';
part './header.dart';

// TODO: [Leptopoda] change layout (landscape mode, padding on small devices)
class GamePage extends StatelessWidget {
  final GameMode gameMode;

  const GamePage(this.gameMode, {Key? key}) : super(key: key);

  void _showGameOptions(BuildContext context) => showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => const GameOptionsModal(),
      );

  void _showSettings(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const GameSettingsPage()),
      );

  void _showMoveOptions(BuildContext context) => showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => const MoveOptionsModal(),
      );

  void _showInfo(BuildContext context) => showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => const _InfoDialog(),
      );

  double _getScreenPaddingH(BuildContext context) {
    // when screen's height/width rate is less than 16/9, limit width of board
    final windowSize = MediaQuery.of(context).size;
    final double height = windowSize.height;
    double width = windowSize.width;

    // TODO: [Leptopoda] maybe use windowSize.aspectRatio
    if (height / width < 16.0 / 9.0) {
      width = height * 9 / 16;
      return (windowSize.width - width) / 2 - AppTheme.boardMargin;
    } else {
      return AppTheme.boardScreenPaddingH;
    }
  }

  List<Widget> toolbarItems(BuildContext context) {
    final gameButton = ToolbarItem.icon(
      onPressed: () => _showGameOptions(context),
      icon: const Icon(FluentIcons.table_simple_24_regular),
      label: Text(S.of(context).game),
    );

    final optionsButton = ToolbarItem.icon(
      onPressed: () => _showSettings(context),
      icon: const Icon(FluentIcons.settings_24_regular),
      label: Text(S.of(context).options),
    );

    final moveButton = ToolbarItem.icon(
      onPressed: () => _showMoveOptions(context),
      icon: const Icon(FluentIcons.calendar_agenda_24_regular),
      label: Text(S.of(context).move_number(0)),
    );

    final infoButton = ToolbarItem.icon(
      onPressed: () => _showInfo(context),
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
      stepForwardButton,
      stepForwardAllButton,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final controller = MillController();

    controller.gameInstance.gameMode = gameMode;
    final screenPaddingH = _getScreenPaddingH(context);

    return Scaffold(
      appBar: AppBar(
        leading: DrawerIcon.of(context)?.icon,
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        iconTheme: const IconThemeData(
          color: AppTheme.drawerAnimationIconColor,
        ),
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: LocalDatabaseService.colorSettings.darkBackgroundColor,
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: screenPaddingH),
        child: FutureBuilder(
          future: controller.start(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator.adaptive(),
              );
            }
            final screenPaddingH = _getScreenPaddingH(context);
            final boardWidth =
                MediaQuery.of(context).size.width - screenPaddingH * 2;

            return Column(
              children: <Widget>[
                GameHeader(gameMode: gameMode),
                Container(
                  margin: const EdgeInsets.symmetric(
                    vertical: AppTheme.boardMargin,
                  ),
                  child: _Board(
                    width: boardWidth,
                  ),
                ),
                if (LocalDatabaseService
                    .display.isHistoryNavigationToolbarShown)
                  GamePageToolBar(
                    backgroundColor: LocalDatabaseService
                        .colorSettings.navigationToolbarBackgroundColor,
                    itemColor: LocalDatabaseService
                        .colorSettings.navigationToolbarIconColor,
                    children: historyNavToolbarItems(context),
                  ),
                GamePageToolBar(
                  backgroundColor: LocalDatabaseService
                      .colorSettings.mainToolbarBackgroundColor,
                  itemColor:
                      LocalDatabaseService.colorSettings.mainToolbarIconColor,
                  children: toolbarItems(context),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
