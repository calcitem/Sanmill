// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_page.dart

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
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
import '../services/analysis_mode.dart';
import '../services/animation/animation_manager.dart';
import '../services/annotation/annotation_manager.dart';
import '../services/import_export/pgn.dart';
import '../services/painters/animations/piece_effect_animation.dart';
import '../services/painters/painters.dart';
import 'moves_list_page.dart';
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

/// Main GamePage widget that initializes the game controller and passes it
/// to a stateful inner widget managing annotation mode.
class GamePage extends StatelessWidget {
  GamePage(this.gameMode, {super.key}) {
    // Reset game score when creating a new game page.
    Position.resetScore();
  }

  final GameMode gameMode;

  @override
  Widget build(BuildContext context) {
    final GameController controller = GameController();
    controller.gameInstance.gameMode = gameMode;
    // Use a stateful inner widget to manage annotation mode state.
    return _GamePageInner(controller: controller);
  }
}

/// Stateful widget that holds the internal state for annotation mode.
class _GamePageInner extends StatefulWidget {
  const _GamePageInner({required this.controller});

  final GameController controller;

  @override
  State<_GamePageInner> createState() => _GamePageInnerState();
}

class _GamePageInnerState extends State<_GamePageInner> {
  // GlobalKey to reference the real board's RenderBox
  final GlobalKey _gameBoardKey = GlobalKey();

  bool _isAnnotationMode = false;
  late final AnnotationManager _annotationManager;

  @override
  void initState() {
    super.initState();
    // Initialize annotation manager from game controller.
    _annotationManager = widget.controller.annotationManager;

    // Listen for analysis mode state changes
    AnalysisMode.stateNotifier.addListener(_updateAnalysisButton);
  }

  // Method to update only the analysis button when state changes
  void _updateAnalysisButton() {
    // This will force a rebuild of only the analysis button area
    // without requiring a full board repaint
    setState(() {
      // No need to do anything in the setState body
      // The Icon will check AnalysisMode.isEnabled when rebuilding
    });
  }

  @override
  void dispose() {
    // Remove listener when the widget is disposed
    AnalysisMode.stateNotifier.removeListener(_updateAnalysisButton);
    super.dispose();
  }

  // Toggle annotation mode without rebuilding the entire widget tree.
  void _toggleAnnotationMode() {
    setState(() {
      if (_isAnnotationMode) {
        // Clear annotations when turning off annotation mode.
        _annotationManager.clear();
      }
      _isAnnotationMode = !_isAnnotationMode;
      widget.controller.isAnnotationMode = _isAnnotationMode;
    });
    debugPrint('Annotation mode is now: $_isAnnotationMode');
  }

  @override
  Widget build(BuildContext context) {
    // Build base content (game board, background, etc.)
    final Widget baseContent = Scaffold(
      key: const Key('game_page_scaffold'),
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Calculate board dimensions and game board rectangle.
          final double maxWidth = constraints.maxWidth;
          final double maxHeight = constraints.maxHeight;
          final double boardDimension =
              (maxHeight > 0 && maxHeight < maxWidth) ? maxHeight : maxWidth;
          final Rect gameBoardRect = Rect.fromLTWH(
            (constraints.maxWidth - boardDimension) / 2,
            0, // Top alignment.
            boardDimension,
            boardDimension,
          );

          return Stack(
            key: const Key('game_page_stack'),
            children: <Widget>[
              // Background image or solid color.
              _buildBackground(),
              // Game board widget.
              _buildGameBoard(context, widget.controller),
              // Drawer icon in the top-left corner.
              Align(
                key: const Key('game_page_drawer_icon_align'),
                alignment: AlignmentDirectional.topStart,
                child: SafeArea(
                  child: CustomDrawerIcon.of(context)!.drawerIcon,
                ),
              ),
              // Analysis button in the top-right corner
              if (GameController().gameInstance.gameMode ==
                      GameMode.humanVsHuman &&
                  DB().generalSettings.usePerfectDatabase &&
                  isRuleSupportingPerfectDatabase())
                Align(
                  key: const Key('game_page_analysis_button_align'),
                  alignment: AlignmentDirectional.topEnd,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Material(
                        color: Colors.transparent,
                        child: IconButton(
                          key: const Key('game_page_analysis_button'),
                          icon: Icon(
                            AnalysisMode.isEnabled
                                ? FluentIcons.beaker_dismiss_24_regular
                                : FluentIcons.beaker_24_regular,
                            color: Colors.white,
                          ),
                          tooltip: S.of(context).analysis,
                          onPressed: () => _analyzePosition(context),
                        ),
                      ),
                    ),
                  ),
                ),
              // Vignette overlay if enabled in display settings.
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

    // Build annotation overlay as a separate layer.
    // It is always part of the widget tree, but its visibility is controlled by Offstage.
    final Widget annotationOverlay = Offstage(
      offstage: !_isAnnotationMode,
      child: AnnotationOverlay(
        annotationManager: _annotationManager,
        // We pass the GlobalKey down so that _snapToBoardFeatures can find the board box
        gameBoardKey: _gameBoardKey,
        child: const SizedBox(width: double.infinity, height: double.infinity),
      ),
    );

    // Build annotation toolbar if enabled in display settings.
    Widget toolbar = Container();
    if (DB().displaySettings.isAnnotationToolbarShown) {
      toolbar = Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: AnnotationToolbar(
          annotationManager: _annotationManager,
          isAnnotationMode: _isAnnotationMode,
          onToggleAnnotationMode: _toggleAnnotationMode,
        ),
      );
    }

    // Return a Stack with base content, annotation overlay, and toolbar.
    return Stack(
      children: <Widget>[
        baseContent,
        annotationOverlay,
        toolbar,
      ],
    );
  }

  // Builds the background widget based on display settings.
  Widget _buildBackground() {
    final DisplaySettings displaySettings = DB().displaySettings;
    // Get background image provider if available.
    final ImageProvider? backgroundImage =
        getBackgroundImageProvider(displaySettings);

    if (backgroundImage == null) {
      // No image selected, return a container with a solid color.
      return Container(
        key: const Key('game_page_background_container'),
        color: DB().colorSettings.darkBackgroundColor,
      );
    } else {
      // Return image with error handling.
      return Image(
        key: const Key('game_page_background_image'),
        image: backgroundImage,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder:
            (BuildContext context, Object error, StackTrace? stackTrace) {
          // Fallback to a solid color if image fails to load.
          return Container(
            key: const Key('game_page_background_error_container'),
            color: DB().colorSettings.darkBackgroundColor,
          );
        },
      );
    }
  }

  // Builds the game board widget including orientation handling and layout constraints.
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
                            boardImage: getBoardImageProvider(displaySettings),
                            // Pass the GlobalKey here to the GameBoard:
                            child: GameBoard(
                              key: _gameBoardKey,
                              boardImage:
                                  getBoardImageProvider(displaySettings),
                            ),
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

  // Calculates the toolbar height based on display settings.
  double _calculateToolbarHeight(BuildContext context) {
    double toolbarHeight =
        GamePageToolbar.height + ButtonTheme.of(context).height;
    if (DB().displaySettings.isHistoryNavigationToolbarShown) {
      toolbarHeight *= 2;
    } else if (DB().displaySettings.isAnnotationToolbarShown) {
      toolbarHeight *= 4;
    } else if (DB().displaySettings.isAnalysisToolbarShown) {
      toolbarHeight *= 5;
    }
    return toolbarHeight;
  }

  // Add analysis method to the GamePage class
  Future<void> _analyzePosition(BuildContext context) async {
    // If analysis is already enabled, disable it and exit
    if (AnalysisMode.isEnabled) {
      AnalysisMode.disable();
      // No need to call setState here as the listener will handle it
      return;
    }

    // Check if rules support perfect database
    if (!isRuleSupportingPerfectDatabase()) {
      return;
    }

    // Check if perfect database is enabled
    if (!DB().generalSettings.usePerfectDatabase) {
      return;
    }

    // Run analysis and display results
    final PositionAnalysisResult result =
        await GameController().engine.analyzePosition();

    if (!result.isValid) {
      return;
    }

    // Enable analysis mode with the results
    AnalysisMode.enable(result.possibleMoves);

    // setState is still called here to ensure board is repainted
    // when user explicitly clicks the analysis button
    if (mounted) {
      setState(() {});
    }
  }
}
