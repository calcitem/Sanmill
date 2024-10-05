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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

import '../../appearance_settings/models/display_settings.dart';
import '../../custom_drawer/custom_drawer.dart';
import '../../game_page/services/mill.dart';
import '../../general_settings/models/general_settings.dart';
import '../../generated/intl/l10n.dart';
import '../../main.dart';
import '../../rule_settings/widgets/rule_settings_page.dart';
import '../../shared/config/constants.dart';
import '../../shared/database/database.dart';
import '../../shared/services/environment_config.dart';
import '../../shared/services/llm.dart';
import '../../shared/services/logger.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/themes/ui_colors.dart';
import '../../shared/utils/helpers/string_helpers/string_buffer_helper.dart';
import '../../shared/widgets/custom_spacer.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../services/animation/animation_manager.dart';
import '../services/painters/painters.dart';
import 'play_area.dart';
import 'toolbars/game_toolbar.dart';
import 'vignette_overlay.dart';

part 'board_semantics.dart';
part 'dialogs/game_result_alert_dialog.dart';
part 'dialogs/info_dialog.dart';
part 'dialogs/move_list_dialog.dart';
part 'game_board.dart';
part 'game_header.dart';
part 'game_page_action_sheet.dart';
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
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Constraints of the game board but applied to the entire child
          final double maxWidth = constraints.maxWidth;
          final double maxHeight = constraints.maxHeight;
          final double boardDimension =
              (maxHeight > 0 && maxHeight < maxWidth) ? maxHeight : maxWidth;

          final Rect gameBoardRect = Rect.fromLTWH(
            (constraints.maxWidth - boardDimension) /
                2, // Center the board horizontally
            0,
            boardDimension,
            boardDimension,
          );

          return Stack(
            children: <Widget>[
              // Background image or color
              _buildBackground(),

              // Game board
              _buildGameBoard(context, controller),
              // Drawer icon
              Align(
                alignment: AlignmentDirectional.topStart,
                child:
                    SafeArea(child: CustomDrawerIcon.of(context)!.drawerIcon),
              ),

              // Vignette overlay
              if (DB().displaySettings.vignetteEffectEnabled)
                VignetteOverlay(gameBoardRect: gameBoardRect),
            ],
          );
        },
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
                      // Use ValueListenableBuilder to listen to DisplaySettings changes
                      child: ValueListenableBuilder<Box<DisplaySettings>>(
                        valueListenable: DB().listenDisplaySettings,
                        builder: (BuildContext context,
                            Box<DisplaySettings> box, Widget? child) {
                          final DisplaySettings displaySettings = box.get(
                            DB.displaySettingsKey,
                            defaultValue: const DisplaySettings(),
                          )!;

                          // Retrieve the selected board image path
                          final String boardImagePath =
                              displaySettings.boardImagePath;

                          return PlayArea(
                            // Pass the board image path to PlayArea
                            boardImagePath: boardImagePath,
                          );
                        },
                      ),
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
