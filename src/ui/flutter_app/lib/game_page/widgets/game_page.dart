// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_page.dart

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;
import 'package:marquee/marquee.dart';

import '../../appearance_settings/models/display_settings.dart';
import '../../appearance_settings/widgets/appearance_settings_page.dart';
import '../../experience_recording/services/recording_service.dart';
import '../../experience_recording/widgets/recording_indicator.dart';
import '../../experience_recording/widgets/replay_controls.dart';
import '../../game_page/services/mill.dart';
import '../../game_platform/game_session.dart';
import '../../game_shell/game_session_scope.dart';
import '../../games/mill/native_mill_snapshot_board_view.dart';
import '../../general_settings/models/general_settings.dart';
import '../../generated/intl/l10n.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../rule_settings/widgets/rule_settings_page.dart';
import '../../shared/config/constants.dart';
import '../../shared/database/database.dart';
import '../../shared/services/catcher_service.dart';
import '../../shared/services/environment_config.dart';
import '../../shared/services/logger.dart';
import '../../shared/services/system_ui_service.dart';
import '../../shared/services/url.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/themes/ui_colors.dart';
import '../../shared/utils/helpers/string_helpers/string_buffer_helper.dart';
import '../../shared/utils/helpers/text_helpers/safe_text_editing_controller.dart';
import '../../shared/widgets/custom_spacer.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../../src/rust/api/simple.dart' as tgf;
import '../../statistics/model/stats_settings.dart';
// Voice assistant functionality disabled
// import '../../voice_assistant/widgets/voice_button.dart';
import '../services/animation/animation_manager.dart';
import '../services/animation/headless_animation_manager.dart';
import '../services/annotation/annotation_manager.dart';
import '../services/board_recognition_import.dart';
import '../services/import_export/pgn.dart';
import '../services/painters/animations/piece_effect_animation.dart';
import '../services/painters/painters.dart';
import '../services/player_timer.dart';
import 'ai_chat_dialog.dart';
import 'challenge_confetti.dart';
import 'dialogs/engine_failure_dialog.dart';
import 'dialogs/performance_warning_dialog.dart';
import 'moves_list_page.dart';
import 'play_area.dart';
import 'toolbars/game_toolbar.dart';
import 'vignette_overlay.dart';

part 'board_semantics.dart';
part 'dialogs/algorithm_suggestion_dialog.dart';
part 'dialogs/game_result_alert_dialog.dart';
part 'dialogs/info_dialog.dart';
part 'dialogs/move_list_dialog.dart';
part 'dialogs/strategy_suggestion_dialog.dart';
part 'game_board.dart';
part 'game_header.dart';
part 'game_page_action_sheet.dart';
part 'modals/move_options_modal.dart';

/// Main GamePage widget that initializes the game controller and passes it
/// to a stateful inner widget managing annotation mode.
class GamePage extends StatelessWidget {
  const GamePage(this.gameMode, {super.key});

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
    // Reset the cumulative win/draw/loss tally when entering the game page,
    // mirroring the legacy `Position.resetScore()` call that lived in the
    // old GamePage constructor. The score then accumulates across in-page
    // restarts and is read by the info dialog and PGN import.
    resetMillScore();
    // Initialize annotation manager from game controller.
    _annotationManager = widget.controller.annotationManager;

    // Auto-start experience recording if enabled and not already recording.
    _maybeStartRecording();

    // When this page is mounted directly on the setup-position route, open the
    // editor once the active native session is bound.
    if (widget.controller.gameInstance.gameMode == GameMode.setupPosition) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.controller.gameInstance.gameMode == GameMode.setupPosition &&
            widget.controller.setupPositionController == null) {
          widget.controller.enterSetupPosition();
        }
      });
    }
  }

  /// Starts experience recording automatically when the feature is enabled.
  ///
  /// Skips if recording is suppressed (e.g. during replay) or already active.
  void _maybeStartRecording() {
    if (DB().generalSettings.experienceRecordingEnabled &&
        !RecordingService().isRecording &&
        !RecordingService().isSuppressed) {
      RecordingService().startRecording(
        gameMode: widget.controller.gameInstance.gameMode.toString(),
      );
    }
  }

  @override
  void dispose() {
    // Discard an unfinished setup edit when navigating away from the page
    // without changing the mode the next route just installed.
    widget.controller.abandonSetupPositionIfActive();
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
      // Voice assistant functionality disabled
      // floatingActionButton: const VoiceAssistantButton(),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Calculate board dimensions and game board rectangle.
          final double maxWidth = constraints.maxWidth;
          final double maxHeight = constraints.maxHeight;
          final double boardDimension = (maxHeight > 0 && maxHeight < maxWidth)
              ? maxHeight
              : maxWidth;
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
              // Back button in the top-left corner when this route can pop.
              Align(
                key: const Key('game_page_top_left_button_align'),
                alignment: AlignmentDirectional.topStart,
                child: SafeArea(child: _buildTopLeftButton(context)),
              ),
              // Experience recording indicator and replay controls.
              const Align(
                key: Key('game_page_recording_indicator_align'),
                alignment: Alignment.topCenter,
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        RecordingIndicator(),
                        SizedBox(height: 4),
                        ReplayControls(),
                      ],
                    ),
                  ),
                ),
              ),
              // Top-right corner buttons (analysis, AI chat, image recognition)
              if (GameController().gameInstance.gameMode ==
                      GameMode.humanVsHuman ||
                  GameController().gameInstance.gameMode ==
                      GameMode.humanVsAi ||
                  GameController().gameInstance.gameMode == GameMode.aiVsAi ||
                  GameController().gameInstance.gameMode ==
                      GameMode.setupPosition)
                Align(
                  key: const Key('game_page_top_right_buttons_align'),
                  alignment: AlignmentDirectional.topEnd,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Material(
                        color: Colors.transparent,
                        child: ValueListenableBuilder<Box<GeneralSettings>>(
                          valueListenable: DB().listenGeneralSettings,
                          builder:
                              (
                                BuildContext context,
                                Box<GeneralSettings> box,
                                Widget? child,
                              ) {
                                final GeneralSettings settings = box.get(
                                  DB.generalSettingsKey,
                                  defaultValue: const GeneralSettings(),
                                )!;
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    // AI Chat Assistant button (shown when game board is active)
                                    if (_shouldShowAiChatButton(settings))
                                      IconButton(
                                        key: const Key(
                                          'game_page_ai_chat_button',
                                        ),
                                        icon: const Icon(
                                          FluentIcons.chat_24_regular,
                                          color: Colors.white,
                                        ),
                                        tooltip: S
                                            .of(context)
                                            .aiChatButtonTooltip,
                                        onPressed: () =>
                                            _showAiChatDialog(context),
                                      ),
                                    // Board image recognition (Setup Position
                                    // mode only): load a board position from a
                                    // gallery image into the setup editor.
                                    if (GameController()
                                            .gameInstance
                                            .gameMode ==
                                        GameMode.setupPosition) ...<Widget>[
                                      // Recognition tuning sliders, dev builds
                                      // only.
                                      if (EnvironmentConfig.devMode)
                                        IconButton(
                                          key: const Key(
                                            'game_page_recognition_params_button',
                                          ),
                                          icon: const Icon(
                                            FluentIcons.settings_24_regular,
                                            color: Colors.white,
                                          ),
                                          tooltip: S
                                              .of(context)
                                              .recognitionParameters,
                                          onPressed: () =>
                                              BoardRecognitionImport.showParametersDialog(
                                                context,
                                              ),
                                        ),
                                      IconButton(
                                        key: const Key(
                                          'game_page_image_recognition_button',
                                        ),
                                        icon: const Icon(
                                          FluentIcons.camera_24_regular,
                                          color: Colors.white,
                                        ),
                                        tooltip: S
                                            .of(context)
                                            .recognizeBoardFromImage,
                                        onPressed: () =>
                                            BoardRecognitionImport.recognizeFromGallery(
                                              context,
                                            ),
                                      ),
                                    ],
                                  ],
                                );
                              },
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
    return Stack(children: <Widget>[baseContent, annotationOverlay, toolbar]);
  }

  // Builds the background widget based on display settings.
  Widget _buildBackground() {
    final DisplaySettings displaySettings = DB().displaySettings;
    // Get background image provider if available.
    final ImageProvider? backgroundImage = getBackgroundImageProvider(
      displaySettings,
    );

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
                  // Optionally add a CircularProgressIndicator here
                );
              }

              return Padding(
                key: const Key('game_page_padding'),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.boardMargin,
                ),
                child: LayoutBuilder(
                  key: const Key('game_page_inner_layout_builder'),
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double toolbarHeight = _calculateToolbarHeight(
                      context,
                    );
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
                        builder:
                            (
                              BuildContext context,
                              Box<DisplaySettings> box,
                              Widget? child,
                            ) {
                              final DisplaySettings displaySettings = box.get(
                                DB.displaySettingsKey,
                                defaultValue: const DisplaySettings(),
                              )!;
                              return PlayArea(
                                boardImage: getBoardImageProvider(
                                  displaySettings,
                                ),
                                // Pass the GlobalKey here to the GameBoard:
                                child: GameBoard(
                                  key: _gameBoardKey,
                                  boardImage: getBoardImageProvider(
                                    displaySettings,
                                  ),
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

  /// Builds the top-left back button when this route can pop.
  Widget _buildTopLeftButton(BuildContext context) {
    if (Navigator.canPop(context)) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Material(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          child: IconButton(
            key: const Key('game_page_back_button'),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            tooltip: S.of(context).back,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // Calculates the toolbar height based on display settings.
  double _calculateToolbarHeight(BuildContext context) {
    double toolbarHeight =
        GamePageToolbar.height + ButtonTheme.of(context).height;
    if (DB().displaySettings.isHistoryNavigationToolbarShown) {
      toolbarHeight *= 2;
    } else if (DB().displaySettings.isAnnotationToolbarShown) {
      toolbarHeight *= 4;
    }
    return toolbarHeight;
  }

  /// Determine if the AI chat button should be visible.
  ///
  /// The button is shown when AI chat is enabled in settings and the current
  /// game mode supports it.  We intentionally do NOT gate on
  /// [GameController.isDisposed] here because the controller's disposed flag
  /// is an engine-lifecycle concern that can be `true` during the first build
  /// frame while the previous GameBoard is being disposed and the next one is
  /// initializing. Checking it here would hide the button during route
  /// transitions.
  bool _shouldShowAiChatButton(GeneralSettings settings) {
    // Check if AI chat feature is enabled in settings
    if (!settings.aiChatEnabled) {
      return false;
    }

    final GameMode mode = GameController().gameInstance.gameMode;
    return mode == GameMode.humanVsAi ||
        mode == GameMode.humanVsHuman ||
        mode == GameMode.aiVsAi;
  }

  /// Show the AI chat assistant dialog
  void _showAiChatDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => const AiChatDialog(),
    );
  }
}
