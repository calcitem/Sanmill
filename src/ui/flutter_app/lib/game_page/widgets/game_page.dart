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
import 'package:image_picker/image_picker.dart';

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
import '../pages/board_recognition_debug_page.dart';
import '../services/analysis_mode.dart';
import '../services/animation/animation_manager.dart';
import '../services/annotation/annotation_manager.dart';
import '../services/board_image_recognition.dart';
import '../services/import_export/pgn.dart';
import '../services/painters/animations/piece_effect_animation.dart';
import '../services/painters/painters.dart';
import '../services/player_timer.dart';
import '../widgets/board_recognition_debug_view.dart';
import 'challenge_confetti.dart';
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
                  GameMode.humanVsHuman)
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
                                ? FluentIcons.eye_off_24_regular
                                : FluentIcons.eye_24_regular,
                            color: Colors.white,
                          ),
                          tooltip: S.of(context).analysis,
                          onPressed: () => _analyzePosition(context),
                        ),
                      ),
                    ),
                  ),
                ),
              // Board image recognition button in the top-right corner (only in Setup Position mode)
              if (GameController().gameInstance.gameMode ==
                  GameMode.setupPosition)
                Align(
                  key: const Key('game_page_image_recognition_button_align'),
                  alignment: AlignmentDirectional.topEnd,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Material(
                        color: Colors.transparent,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            // Parameters adjustment button (only shown in dev mode)
                            if (EnvironmentConfig.devMode)
                              IconButton(
                                key: const Key(
                                    'game_page_recognition_params_button'),
                                icon: const Icon(
                                  FluentIcons.settings_24_regular,
                                  color: Colors.white,
                                ),
                                tooltip: S.of(context).recognitionParameters,
                                onPressed: () =>
                                    _showRecognitionParamsDialog(context),
                              ),
                            // Camera button for board recognition
                            IconButton(
                              key: const Key(
                                  'game_page_image_recognition_button'),
                              icon: const Icon(
                                FluentIcons.camera_24_regular,
                                color: Colors.white,
                              ),
                              tooltip: S.of(context).recognizeBoardFromImage,
                              // Board image recognition
                              onPressed: () =>
                                  _recognizeBoardFromImage(context),
                            ),
                          ],
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
                  // Optionally add a CircularProgressIndicator here
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

  // Method to handle board image recognition
  void _recognizeBoardFromImage(BuildContext context) {
    try {
      // Pick image from gallery and analyze it directly
      _pickAndRecognizeImage(context);
    } catch (e) {
      // Show error message if recognition fails
      rootScaffoldMessengerKey.currentState?.showSnackBarClear(
          S.of(context).unableToStartImageRecognition(e.toString()));
      logger.e("Error initiating board recognition: $e");
    }
  }

  /// Display a dialog to adjust board recognition parameters
  /// These parameters will be stored and used for future recognitions
  void _showRecognitionParamsDialog(BuildContext context) {
    // Load current parameters from BoardImageRecognitionService
    double contrastEnhancementFactor =
        BoardImageRecognitionService.contrastEnhancementFactor;
    double pieceThreshold = BoardImageRecognitionService.pieceThreshold;
    double boardColorDistanceThreshold =
        BoardImageRecognitionService.boardColorDistanceThreshold;
    double pieceColorMatchThreshold =
        BoardImageRecognitionService.pieceColorMatchThreshold;
    int whiteBrightnessThreshold =
        BoardImageRecognitionService.whiteBrightnessThreshold;
    int blackBrightnessThreshold =
        BoardImageRecognitionService.blackBrightnessThreshold;
    double blackSaturationThreshold =
        BoardImageRecognitionService.blackSaturationThreshold;
    int blackColorVarianceThreshold =
        BoardImageRecognitionService.blackColorVarianceThreshold;

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            // Function to build a parameter slider
            Widget buildParameterSlider({
              required String label,
              required double value,
              required double min,
              required double max,
              required int divisions,
              required Function(double) onChanged,
            }) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Flexible(
                          flex: 3,
                          child: Text(
                            label,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            value.toStringAsFixed(2),
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Slider(
                    value: value,
                    min: min,
                    max: max,
                    divisions: divisions,
                    onChanged: (double newValue) {
                      setState(() {
                        onChanged(newValue);
                      });
                    },
                  ),
                  const Divider(height: 8),
                ],
              );
            }

            return AlertDialog(
              title: Text(S.of(context).recognitionParameters),
              content: SingleChildScrollView(
                child: Container(
                  width: 350,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        S.of(context).adjustParamsDesc,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 16),

                      // Contrast Enhancement Factor
                      buildParameterSlider(
                        label: "Contrast Enhancement",
                        value: contrastEnhancementFactor,
                        min: 1.0,
                        max: 3.0,
                        divisions: 20,
                        onChanged: (double value) {
                          contrastEnhancementFactor = value;
                        },
                      ),

                      // Piece Detection Threshold
                      buildParameterSlider(
                        label: "Piece Detection Threshold",
                        value: pieceThreshold,
                        min: 0.1,
                        max: 0.5,
                        divisions: 20,
                        onChanged: (double value) {
                          pieceThreshold = value;
                        },
                      ),

                      // Board Color Distance Threshold
                      buildParameterSlider(
                        label: "Board Color Distance",
                        value: boardColorDistanceThreshold,
                        min: 10.0,
                        max: 50.0,
                        divisions: 40,
                        onChanged: (double value) {
                          boardColorDistanceThreshold = value;
                        },
                      ),

                      // Piece Color Match Threshold
                      buildParameterSlider(
                        label: "Piece Color Match Threshold",
                        value: pieceColorMatchThreshold,
                        min: 10.0,
                        max: 50.0,
                        divisions: 40,
                        onChanged: (double value) {
                          pieceColorMatchThreshold = value;
                        },
                      ),

                      // White Brightness Threshold
                      buildParameterSlider(
                        label: "White Brightness Threshold",
                        value: whiteBrightnessThreshold.toDouble(),
                        min: 120.0,
                        max: 220.0,
                        divisions: 100,
                        onChanged: (double value) {
                          whiteBrightnessThreshold = value.round();
                        },
                      ),

                      // Black Brightness Threshold
                      buildParameterSlider(
                        label: "Black Brightness Threshold",
                        value: blackBrightnessThreshold.toDouble(),
                        min: 80.0,
                        max: 180.0,
                        divisions: 100,
                        onChanged: (double value) {
                          blackBrightnessThreshold = value.round();
                        },
                      ),

                      // Black Saturation Threshold
                      buildParameterSlider(
                        label: "Black Saturation Threshold",
                        value: blackSaturationThreshold,
                        min: 0.05,
                        max: 0.5,
                        divisions: 15,
                        onChanged: (double value) {
                          blackSaturationThreshold = value;
                        },
                      ),

                      // Black Color Variance Threshold
                      buildParameterSlider(
                        label: "Black Color Variance",
                        value: blackColorVarianceThreshold.toDouble(),
                        min: 10.0,
                        max: 80.0,
                        divisions: 35,
                        onChanged: (double value) {
                          blackColorVarianceThreshold = value.round();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    // Reset parameters to defaults
                    setState(() {
                      contrastEnhancementFactor = 1.8;
                      pieceThreshold = 0.25;
                      boardColorDistanceThreshold = 28.0;
                      pieceColorMatchThreshold = 30.0;
                      whiteBrightnessThreshold = 170;
                      blackBrightnessThreshold = 135;
                      blackSaturationThreshold = 0.25;
                      blackColorVarianceThreshold = 40;
                    });
                  },
                  child: Text(S.of(context).resetToDefaults),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text(S.of(context).cancel),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Save parameters to service
                    BoardImageRecognitionService.updateParameters(
                      contrastEnhancementFactor: contrastEnhancementFactor,
                      pieceThreshold: pieceThreshold,
                      boardColorDistanceThreshold: boardColorDistanceThreshold,
                      pieceColorMatchThreshold: pieceColorMatchThreshold,
                      whiteBrightnessThreshold: whiteBrightnessThreshold,
                      blackBrightnessThreshold: blackBrightnessThreshold,
                      blackSaturationThreshold: blackSaturationThreshold,
                      blackColorVarianceThreshold: blackColorVarianceThreshold,
                    );

                    // Close the dialog
                    Navigator.of(context).pop();

                    // Display a confirmation message
                    rootScaffoldMessengerKey.currentState?.showSnackBar(
                      SnackBar(
                        content:
                            Text(S.of(context).recognitionParametersUpdated),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Text(S.of(context).saveParameters),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Pick an image from gallery and analyze it
  Future<void> _pickAndRecognizeImage(BuildContext context) async {
    final ImagePicker picker = ImagePicker();

    // Pick image from gallery (async gap)
    final XFile? pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
    );

    // Early return if user cancels or widget was disposed
    if (pickedFile == null) {
      return;
    }
    // Check if the context is still mounted after the async gap
    if (!context.mounted) {
      return;
    }
    // Capture context dependent members BEFORE the await/async gap.
    // We will re-check mounted *after* the async gap.
    final NavigatorState currentNavigator = Navigator.of(context);
    final ScaffoldMessengerState currentMessenger =
        ScaffoldMessenger.of(context);
    final BuildContext currentContext = context; // Keep for initial dialog
    final S strings = S.of(context);

    // At this point context is still valid for initial dialog
    final AlertDialog dialogContent = AlertDialog(
      title: Text(strings.waiting),
      content: Row(
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Expanded(
            child: Text(strings.analyzingGameBoardImage),
          ),
        ],
      ),
    );

    bool isDialogShowing = true;
    // Show the dialog using the captured context
    showDialog(
      context: currentContext, // Use captured context for the initial dialog
      barrierDismissible: false,
      builder: (_) => dialogContent,
    );

    try {
      // Read bytes and recognize (async)
      final Uint8List imageData = await pickedFile.readAsBytes();
      final Map<int, PieceColor> recognizedPieces =
          await BoardImageRecognitionService.recognizeBoardFromImage(imageData);

      // Check if the context is still mounted after the async gap
      if (!context.mounted) {
        // Try to dismiss dialog if showing, handle potential errors
        if (isDialogShowing) {
          try {
            currentNavigator.pop();
          } catch (_) {}
          isDialogShowing = false;
        }
        return;
      }

      // Dismiss the processing dialog using captured navigator
      if (isDialogShowing) {
        currentNavigator.pop();
        isDialogShowing = false;
      }

      // Check if dev mode is enabled - only show debug UI in dev mode
      if (EnvironmentConfig.devMode) {
        // Use the captured context instead of the original one after the async gap
        final Size screenSize = MediaQuery.of(currentContext).size;

        showDialog<bool>(
          context: currentContext, // Use captured context after the async gap
          barrierDismissible: false,
          builder: (BuildContext dialogContext) {
            // Use dialogContext for navigator inside the dialog
            final NavigatorState dialogNavigator = Navigator.of(dialogContext);
            return Dialog(
              // Use insetPadding to make dialog larger
              insetPadding: EdgeInsets.symmetric(
                horizontal: screenSize.width * 0.05,
                vertical: screenSize.height * 0.1,
              ),
              child: BoardRecognitionDebugPage.createRecognitionResultDialog(
                imageBytes: imageData,
                result: recognizedPieces,
                boardPoints: BoardImageRecognitionService.lastDetectedPoints,
                processedWidth:
                    BoardImageRecognitionService.processedImageWidth,
                processedHeight:
                    BoardImageRecognitionService.processedImageHeight,
                debugInfo: BoardImageRecognitionService.lastDebugInfo,
                context: dialogContext,
                onResult: (bool shouldApply) {
                  // Close dialog using dialog's navigator
                  dialogNavigator.pop(shouldApply);

                  // Check if the context is still mounted after the async gap
                  if (!context.mounted) {
                    return;
                  }

                  // Apply the recognized state if user confirmed
                  if (shouldApply) {
                    // Pass the captured messenger (captured before await)
                    _applyRecognizedBoardState(
                        recognizedPieces, currentMessenger, context);
                  }
                },
              ),
            );
          },
        );
      } else {
        // In normal mode, directly apply recognition results without showing debug view
        if (recognizedPieces.isNotEmpty) {
          // Apply the recognized state directly
          _applyRecognizedBoardState(
              recognizedPieces, currentMessenger, context);
        } else {
          // Show error if no pieces recognized
          currentMessenger.showSnackBar(
            SnackBar(
                content: Text(
                    strings.noPiecesWereRecognizedInTheImagePleaseTryAgain)),
          );
        }
      }
    } catch (e) {
      // Ensure the dialog is closed on error using captured navigator
      if (isDialogShowing) {
        try {
          currentNavigator.pop(); // Use navigator captured before await
        } catch (_) {}
        isDialogShowing = false;
      }

      // Check if the context is still mounted after the async gap before showing snackbar
      if (!context.mounted) {
        return;
      }

      // Use captured messenger for snackbar (captured before await)
      currentMessenger.showSnackBar(SnackBar(
          content: Text(strings.imageRecognitionFailed(e.toString()))));
      logger.e("Error during board recognition: $e");
    }
  }

  /// Apply the recognized board state to the game (uses captured context for S)
  void _applyRecognizedBoardState(Map<int, PieceColor> recognizedPieces,
      ScaffoldMessengerState? messenger, BuildContext context) {
    final S strings = S.of(context);

    try {
      // Generate FEN string from recognized pieces
      final String? fen =
          BoardRecognitionDebugView.generateTempFenString(recognizedPieces);

      if (fen == null) {
        messenger
            ?.showSnackBarClear(strings.failedToGenerateFenFromRecognizedBoard);
        return;
      }

      // Reset board first
      GameController().position.reset();

      // Set FEN string to the position
      if (GameController().position.setFen(fen)) {
        // Successfully set FEN
        // Log successful operation
        logger.i("Successfully applied FEN from image recognition: $fen");

        // Update position notifier to refresh UI
        GameController().setupPositionNotifier.updateIcons();
        GameController().boardSemanticsNotifier.updateSemantics();

        // Show success message with details
        final int whiteCount =
            GameController().position.countPieceOnBoard(PieceColor.white);
        final int blackCount =
            GameController().position.countPieceOnBoard(PieceColor.black);

        // Construct localized message parts
        final String message = strings.appliedPositionDetails(
          whiteCount,
          blackCount,
        );
        final String next =
            GameController().position.sideToMove == PieceColor.white
                ? strings.whiteSMove
                : strings.blackSMove;
        final String fenCopiedMsg = strings.fenCopiedToClipboard;

        // Update the game recorder with the setup position
        GameController().gameRecorder =
            GameRecorder(lastPositionWithRemove: fen, setupPosition: fen);

        // Copy FEN to clipboard for user convenience
        Clipboard.setData(ClipboardData(text: fen));

        // Show success message (using captured S strings)
        messenger?.showSnackBarClear('$message, $next $fenCopiedMsg');
      } else {
        // Failed to set FEN
        messenger
            ?.showSnackBarClear(strings.failedToApplyRecognizedBoardPosition);
        logger.e("Failed to set FEN: $fen");
      }
    } catch (e) {
      logger.e("Error applying recognized board state: $e");
      messenger?.showSnackBarClear(strings.recognitionFailed(e.toString()));
    }
  }
}
