// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// board_recognition_import.dart
//
// Orchestrates the "recognise a board from an image" flow for the Setup
// Position editor.
//
// Responsibilities are deliberately split so each piece stays reusable:
//   * [BoardImageRecognitionService] - pure image -> piece-map pipeline.
//   * [BoardRecognitionDebugView]     - visualization + FEN generation.
//   * [BoardRecognitionDebugPage]     - dev-mode preview dialog.
//   * [MillSetupPositionController]    - applies a FEN to the native session.
//
// This coordinator wires them together and is the single entry point the
// UI calls, so adding new sources (camera, screenshot, file) later only
// needs another `pick*` helper that funnels into [applyRecognizedPieces].

// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../games/mill/mill_setup_position_controller.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/services/environment_config.dart';
import '../../shared/services/logger.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../pages/board_recognition_debug_page.dart';
import '../widgets/board_recognition_debug_view.dart';
import 'board_image_recognition.dart';
import 'mill.dart';

/// Entry points for importing a board position from an image into the
/// active Setup Position editor.
abstract final class BoardRecognitionImport {
  static const String _logTag = '[BoardRecognitionImport]';

  /// True when a Setup Position editor is active and can receive a FEN.
  static bool get isAvailable =>
      GameController().setupPositionController != null;

  /// Picks an image from the gallery, runs recognition and loads the
  /// detected position into the Setup Position editor.
  ///
  /// In development builds the result is shown in a preview dialog first
  /// (see [BoardRecognitionDebugPage]); otherwise it is applied directly.
  static Future<void> recognizeFromGallery(BuildContext context) async {
    if (!isAvailable) {
      return;
    }

    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
    );
    if (pickedFile == null || !context.mounted) {
      return;
    }

    // Capture context-dependent handles before the recognition await gap.
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final S strings = S.of(context);
    final Size screenSize = MediaQuery.of(context).size;

    bool isProgressShowing = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(strings.waiting),
        content: Row(
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(strings.analyzingGameBoardImage)),
          ],
        ),
      ),
    );

    void dismissProgress() {
      if (isProgressShowing) {
        navigator.pop();
        isProgressShowing = false;
      }
    }

    try {
      final Uint8List imageData = await pickedFile.readAsBytes();
      final Map<int, PieceColor> recognizedPieces =
          await BoardImageRecognitionService.recognizeBoardFromImage(imageData);

      if (!context.mounted) {
        dismissProgress();
        return;
      }
      dismissProgress();

      if (EnvironmentConfig.devMode) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) {
            return Dialog(
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
                  Navigator.of(dialogContext).pop();
                  if (shouldApply) {
                    applyRecognizedPieces(recognizedPieces, messenger, strings);
                  }
                },
              ),
            );
          },
        );
      } else if (recognizedPieces.isNotEmpty) {
        applyRecognizedPieces(recognizedPieces, messenger, strings);
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              strings.noPiecesWereRecognizedInTheImagePleaseTryAgain,
            ),
          ),
        );
      }
    } catch (e) {
      dismissProgress();
      logger.e('$_logTag Error during board recognition: $e');
      messenger.showSnackBar(
        SnackBar(content: Text(strings.imageRecognitionFailed(e.toString()))),
      );
    }
  }

  /// Generates a FEN from [pieces] and loads it into the active Setup
  /// Position editor.  Returns true when the position was applied.
  static bool applyRecognizedPieces(
    Map<int, PieceColor> pieces,
    ScaffoldMessengerState messenger,
    S strings,
  ) {
    final MillSetupPositionController? controller =
        GameController().setupPositionController;
    if (controller == null) {
      return false;
    }

    final String? fen = BoardRecognitionDebugView.generateTempFenString(pieces);
    if (fen == null) {
      messenger.showSnackBarClear(
        strings.failedToGenerateFenFromRecognizedBoard,
      );
      return false;
    }

    if (!controller.pasteFen(fen)) {
      messenger.showSnackBarClear(strings.failedToApplyRecognizedBoardPosition);
      logger.e('$_logTag Setup session rejected recognized FEN: $fen');
      return false;
    }

    // Refresh the setup toolbar and board chrome from the new model.
    GameController().setupPositionNotifier.updateIcons();
    GameController().headerIconsNotifier.showIcons();
    GameController().boardSemanticsNotifier.updateSemantics();

    final int whiteCount = controller.countOnBoard(PieceColor.white);
    final int blackCount = controller.countOnBoard(PieceColor.black);
    final String details = strings.appliedPositionDetails(
      whiteCount,
      blackCount,
    );
    final String next = controller.sideToMove == PieceColor.black
        ? strings.blackSMove
        : strings.whiteSMove;
    messenger.showSnackBarClear('$details, $next');
    logger.i('$_logTag Applied recognized FEN to setup session: $fen');
    return true;
  }

  /// Shows the recognition tuning dialog (development builds only).
  ///
  /// The sliders bind to the mutable thresholds on
  /// [BoardImageRecognitionService]; saving persists them for subsequent
  /// recognitions during the session.
  static void showParametersDialog(BuildContext context) {
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
            Widget buildSlider({
              required String label,
              required double value,
              required double min,
              required double max,
              required int divisions,
              required ValueChanged<double> onChanged,
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
                    onChanged: (double newValue) =>
                        setState(() => onChanged(newValue)),
                  ),
                  const Divider(height: 8),
                ],
              );
            }

            return AlertDialog(
              title: Text(S.of(context).recognitionParameters),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 350,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        S.of(context).adjustParamsDesc,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      buildSlider(
                        label: 'Contrast Enhancement',
                        value: contrastEnhancementFactor,
                        min: 1.0,
                        max: 3.0,
                        divisions: 20,
                        onChanged: (double v) => contrastEnhancementFactor = v,
                      ),
                      buildSlider(
                        label: 'Piece Detection Threshold',
                        value: pieceThreshold,
                        min: 0.1,
                        max: 0.5,
                        divisions: 20,
                        onChanged: (double v) => pieceThreshold = v,
                      ),
                      buildSlider(
                        label: 'Board Color Distance',
                        value: boardColorDistanceThreshold,
                        min: 10.0,
                        max: 50.0,
                        divisions: 40,
                        onChanged: (double v) =>
                            boardColorDistanceThreshold = v,
                      ),
                      buildSlider(
                        label: 'Piece Color Match Threshold',
                        value: pieceColorMatchThreshold,
                        min: 10.0,
                        max: 50.0,
                        divisions: 40,
                        onChanged: (double v) => pieceColorMatchThreshold = v,
                      ),
                      buildSlider(
                        label: 'White Brightness Threshold',
                        value: whiteBrightnessThreshold.toDouble(),
                        min: 120.0,
                        max: 220.0,
                        divisions: 100,
                        onChanged: (double v) =>
                            whiteBrightnessThreshold = v.round(),
                      ),
                      buildSlider(
                        label: 'Black Brightness Threshold',
                        value: blackBrightnessThreshold.toDouble(),
                        min: 80.0,
                        max: 180.0,
                        divisions: 100,
                        onChanged: (double v) =>
                            blackBrightnessThreshold = v.round(),
                      ),
                      buildSlider(
                        label: 'Black Saturation Threshold',
                        value: blackSaturationThreshold,
                        min: 0.05,
                        max: 0.5,
                        divisions: 15,
                        onChanged: (double v) => blackSaturationThreshold = v,
                      ),
                      buildSlider(
                        label: 'Black Color Variance',
                        value: blackColorVarianceThreshold.toDouble(),
                        min: 10.0,
                        max: 80.0,
                        divisions: 35,
                        onChanged: (double v) =>
                            blackColorVarianceThreshold = v.round(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => setState(() {
                    contrastEnhancementFactor = 1.8;
                    pieceThreshold = 0.25;
                    boardColorDistanceThreshold = 28.0;
                    pieceColorMatchThreshold = 30.0;
                    whiteBrightnessThreshold = 170;
                    blackBrightnessThreshold = 135;
                    blackSaturationThreshold = 0.25;
                    blackColorVarianceThreshold = 40;
                  }),
                  child: Text(S.of(context).resetToDefaults),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(S.of(context).cancel),
                ),
                ElevatedButton(
                  onPressed: () {
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
                    Navigator.of(context).pop();
                    rootScaffoldMessengerKey.currentState?.showSnackBar(
                      SnackBar(
                        content: Text(
                          S.of(context).recognitionParametersUpdated,
                        ),
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
}
