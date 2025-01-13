// This file is part of Sanmill.
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)
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
import '../../appearance_settings/widgets/appearance_settings_page.dart';
import '../../custom_drawer/custom_drawer.dart';
import '../../game_page/services/mill.dart';
import '../../general_settings/models/general_settings.dart';
import '../../generated/intl/l10n.dart';
import '../../main.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../rule_settings/widgets/rule_settings_page.dart';
import '../../shared/config/constants.dart';
import '../../shared/database/database.dart';
import '../../shared/services/environment_config.dart';
import '../../shared/services/logger.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/themes/ui_colors.dart';
import '../../shared/utils/helpers/string_helpers/string_buffer_helper.dart';
import '../../shared/widgets/custom_spacer.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../services/animation/animation_manager.dart';
import '../services/painters/animations/piece_effect_animation.dart';
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

  /// Builds the background widget based on user selection.
  ///
  /// - If a custom image is selected, it displays the custom image.
  /// - If a built-in image is selected, it displays the built-in image.
  /// - If no image is selected, it displays a solid color background.
  Widget _buildBackground() {
    // Retrieve the current display settings from the database
    final DisplaySettings displaySettings = DB().displaySettings;

    // Obtain the appropriate ImageProvider based on the backgroundImagePath
    final ImageProvider? backgroundImage =
        getBackgroundImageProvider(displaySettings);

    if (backgroundImage == null) {
      // No image selected, use a solid color background
      return Container(
        color: DB().colorSettings.darkBackgroundColor,
      );
    } else {
      // Image selected, display it with error handling
      return Image(
        image: backgroundImage,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        // Handle any errors that occur while loading the image
        errorBuilder:
            (BuildContext context, Object error, StackTrace? stackTrace) {
          // Fallback to a solid color background if the image fails to load
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
                      child: ValueListenableBuilder<Box<DisplaySettings>>(
                        valueListenable: DB().listenDisplaySettings,
                        builder: (BuildContext context,
                            Box<DisplaySettings> box, Widget? child) {
                          final DisplaySettings displaySettings = box.get(
                            DB.displaySettingsKey,
                            defaultValue: const DisplaySettings(),
                          )!;

                          return PlayArea(
                            boardImage: getBoardImageProvider(
                                displaySettings), // Pass the ImageProvider
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
