// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../games/mill/mill_setup_position_controller.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/services/logger.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../pages/board_corner_editor_page.dart';
import '../pages/board_recognition_progress_page.dart';
import '../pages/board_recognition_review_dialog.dart';
import '../widgets/board_recognition_debug_view.dart';
import 'board_image_recognition.dart';
import 'mill.dart';

/// Imports a photographed position into the active Setup Position editor.
abstract final class BoardRecognitionImport {
  static const String _logTag = '[BoardRecognitionImport]';

  static bool get isAvailable => GameController().isSetupPosition;

  /// Selects a camera or album source when the current platform supports it.
  static Future<void> recognize(BuildContext context) async {
    final MillSetupPositionController? originController =
        GameController().setupPositionController;
    if (!isAvailable || originController == null) {
      return;
    }

    final bool hasCameraPicker =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final ImageSource? source;
    if (hasCameraPicker) {
      source = await showModalBottomSheet<ImageSource>(
        context: context,
        useRootNavigator: true,
        builder: (BuildContext sheetContext) => SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: Text(S.of(sheetContext).photoShoot),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(S.of(sheetContext).selectFromAlbum),
                onTap: () =>
                    Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
    } else {
      source = ImageSource.gallery;
    }
    if (source == null ||
        !context.mounted ||
        !_isOriginEditorActive(originController)) {
      return;
    }
    await _recognizeFromSource(context, source, originController);
  }

  /// Asks the user to align the four outer-square corners, recognizes the
  /// fixed 24 locations, and presents an editable preview.
  static Future<void> _recognizeFromSource(
    BuildContext context,
    ImageSource source,
    MillSetupPositionController originController,
  ) async {
    final XFile? pickedFile;
    try {
      pickedFile = await ImagePicker().pickImage(source: source);
    } catch (error, stackTrace) {
      logger.e('$_logTag Failed to open image source: $error\n$stackTrace');
      if (context.mounted && _isOriginEditorActive(originController)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBarClear(S.of(context).boardRecognitionFailedTryAgain);
      }
      return;
    }
    if (pickedFile == null ||
        !context.mounted ||
        !_isOriginEditorActive(originController)) {
      return;
    }
    final XFile selectedFile = pickedFile;

    final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final S strings = S.of(context);

    final BoardRecognitionProgressResult<PreparedBoardImage?>? preparation =
        await showBoardRecognitionProgress<PreparedBoardImage?>(
          context: context,
          message: strings.analyzingGameBoardImage,
          task: () async {
            final Uint8List imageData = await selectedFile.readAsBytes();
            return BoardImageRecognitionService.prepareImageForPreview(
              imageData,
            );
          },
        );
    if (preparation == null ||
        !context.mounted ||
        !_isOriginEditorActive(originController)) {
      return;
    }
    if (!preparation.isSuccess) {
      logger.e(
        '$_logTag Failed to prepare image: ${preparation.error}\n'
        '${preparation.stackTrace}',
      );
      messenger.showSnackBarClear(strings.boardRecognitionFailedTryAgain);
      return;
    }
    final PreparedBoardImage? prepared = preparation.value;
    if (prepared == null) {
      messenger.showSnackBarClear(strings.boardRecognitionFailedTryAgain);
      return;
    }

    final Future<BoardImageCorners?> cornerSuggestion =
        BoardImageRecognitionService.detectCorners(prepared);
    final BoardImageCorners? corners = await navigator.push<BoardImageCorners>(
      MaterialPageRoute<BoardImageCorners>(
        builder: (BuildContext routeContext) => BoardCornerEditorPage(
          imageBytes: prepared.bytes,
          imageSize: prepared.size,
          cornerSuggestion: cornerSuggestion,
        ),
      ),
    );
    if (corners == null ||
        !context.mounted ||
        !_isOriginEditorActive(originController)) {
      return;
    }

    final BoardRecognitionProgressResult<BoardRecognitionResult>? recognition =
        await showBoardRecognitionProgress<BoardRecognitionResult>(
          context: context,
          message: strings.analyzingGameBoardImage,
          task: () => BoardImageRecognitionService.recognizeBoardFromImage(
            prepared,
            corners: corners,
          ),
        );
    if (recognition == null ||
        !context.mounted ||
        !_isOriginEditorActive(originController)) {
      return;
    }
    if (!recognition.isSuccess) {
      logger.e(
        '$_logTag Failed to recognize image: ${recognition.error}\n'
        '${recognition.stackTrace}',
      );
      messenger.showSnackBarClear(strings.boardRecognitionFailedTryAgain);
      return;
    }
    final BoardRecognitionResult result = recognition.value!;

    if (!result.isSuccess) {
      final String message =
          result.failure == BoardRecognitionFailure.noPiecesDetected
          ? strings.noPiecesWereRecognizedInTheImagePleaseTryAgain
          : strings.boardRecognitionFailedTryAgain;
      messenger.showSnackBarClear(message);
      return;
    }

    final Map<int, PieceColor>? reviewed =
        await showDialog<Map<int, PieceColor>>(
          context: context,
          barrierDismissible: false,
          useRootNavigator: true,
          builder: (BuildContext dialogContext) =>
              BoardRecognitionReviewDialog(result: result),
        );
    if (reviewed == null ||
        !context.mounted ||
        !_isOriginEditorActive(originController)) {
      return;
    }
    applyRecognizedPieces(
      reviewed,
      messenger,
      strings,
      expectedController: originController,
    );
  }

  /// Generates a FEN and loads it into the active native setup session.
  static bool applyRecognizedPieces(
    Map<int, PieceColor> pieces,
    ScaffoldMessengerState messenger,
    S strings, {
    MillSetupPositionController? expectedController,
  }) {
    final GameController gameController = GameController();
    final MillSetupPositionController? controller =
        gameController.setupPositionController;
    if (!gameController.isSetupPosition ||
        controller == null ||
        (expectedController != null &&
            !identical(controller, expectedController))) {
      return false;
    }
    final bool hasPieces = pieces.values.any(
      (PieceColor color) =>
          color == PieceColor.white || color == PieceColor.black,
    );
    if (!hasPieces) {
      messenger.showSnackBarClear(
        strings.noPiecesWereRecognizedInTheImagePleaseTryAgain,
      );
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

    gameController.setupPositionNotifier.updateIcons();
    gameController.headerIconsNotifier.showIcons();
    gameController.boardSemanticsNotifier.updateSemantics();

    final int whiteCount = controller.countOnBoard(PieceColor.white);
    final int blackCount = controller.countOnBoard(PieceColor.black);
    final String details = strings.appliedPositionDetails(
      whiteCount,
      blackCount,
    );
    final String next = controller.sideToMove == PieceColor.black
        ? strings.blackSMove
        : strings.whiteSMove;
    messenger.showSnackBarClear('$details. $next.');
    logger.i('$_logTag Applied recognized FEN to setup session: $fen');
    return true;
  }

  static bool _isOriginEditorActive(
    MillSetupPositionController originController,
  ) {
    final GameController gameController = GameController();
    return gameController.isSetupPosition &&
        identical(gameController.setupPositionController, originController);
  }
}
