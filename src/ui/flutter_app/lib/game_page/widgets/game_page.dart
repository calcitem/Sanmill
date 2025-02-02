// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_page.dart

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
import '../services/import_export/pgn.dart';
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
      key: const Key('game_page_scaffold'),
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Constraints of the game board but applied to the entire child
          final double maxWidth = constraints.maxWidth;
          final double maxHeight = constraints.maxHeight;
          final double boardDimension =
              (maxHeight > 0 && maxHeight < maxWidth) ? maxHeight : maxWidth;

          final Rect gameBoardRect = Rect.fromLTWH(
            (constraints.maxWidth - boardDimension) / 2,
            // Center the board horizontally
            0,
            boardDimension,
            boardDimension,
          );

          return Stack(
            key: const Key('game_page_stack'),
            children: <Widget>[
              // Background image or color
              _buildBackground(),

              // Game board
              _buildGameBoard(context, controller),
              // Drawer icon
              Align(
                key: const Key('game_page_drawer_icon_align'),
                alignment: AlignmentDirectional.topStart,
                child:
                    SafeArea(child: CustomDrawerIcon.of(context)!.drawerIcon),
              ),

              // Vignette overlay
              if (DB().displaySettings.vignetteEffectEnabled)
                VignetteOverlay(
                  key: const Key('game_page_vignette_overlay'),
                  gameBoardRect: gameBoardRect,
                ),
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
        key: const Key('game_page_background_container'),
        color: DB().colorSettings.darkBackgroundColor,
      );
    } else {
      // Image selected, display it with error handling
      return Image(
        key: const Key('game_page_background_image'),
        image: backgroundImage,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        // Handle any errors that occur while loading the image
        errorBuilder:
            (BuildContext context, Object error, StackTrace? stackTrace) {
          // Fallback to a solid color background if the image fails to load
          return Container(
            key: const Key('game_page_background_error_container'),
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
          key: const Key('game_page_align_gameboard'),
          alignment: isLandscape ? Alignment.center : Alignment.topCenter,
          child: FutureBuilder<void>(
            key: const Key('game_page_future_builder'),
            future: controller.startController(),
            builder: (BuildContext context, AsyncSnapshot<Object?> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  key: Key('game_page_center_loading'),
                );
              }

              return Padding(
                key: const Key('game_page_padding'),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.boardMargin),
                child: LayoutBuilder(
                  key: const Key('game_page_inner_layout_builder'),
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
                      key: const Key('game_page_constrained_box'),
                      constraints: constraint,
                      child: ValueListenableBuilder<Box<DisplaySettings>>(
                        key: const Key('game_page_value_listenable_builder'),
                        valueListenable: DB().listenDisplaySettings,
                        builder: (BuildContext context,
                            Box<DisplaySettings> box, Widget? child) {
                          final DisplaySettings displaySettings = box.get(
                            DB.displaySettingsKey,
                            defaultValue: const DisplaySettings(),
                          )!;

                          return PlayArea(
                            key: const Key('game_page_play_area'),
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
