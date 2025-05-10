// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// screenshot_service.dart

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:native_screenshot_widget/native_screenshot_widget.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../game_page/services/mill.dart';
import '../database/database.dart';
import '../widgets/snackbars/scaffold_messenger.dart';
import 'environment_config.dart';
import 'logger.dart';

class ScreenshotService {
  ScreenshotService._();

  /// Singleton instance
  static final ScreenshotService instance = ScreenshotService._();

  /// Optional initialization logic (currently a no-op but kept for future use)
  Future<void> init() async {
    // Placeholder for any platform-specific initialization in the future.
    return;
  }

  static const String _logTag = "[ScreenshotService]";

  static final NativeScreenshotController screenshotController =
      NativeScreenshotController();

  static Future<void> takeScreenshot(String storageLocation,
      [String? filename]) async {
    if (!isSupportedPlatform()) {
      logger.i("Taking screenshots is not supported on this platform");
      return;
    }

    logger.i("Attempting to capture screenshot...");
    final Uint8List? image = await screenshotController.takeScreenshot();
    if (image == null) {
      logger.e("Failed to capture screenshot: Image is null.");
      return;
    }

    // Get the final image based on user settings
    final Uint8List finalImage;
    if (DB().displaySettings.isScreenshotGameInfoShown) {
      // Add game info to the image if enabled in settings
      finalImage = await _addGameInfoToImage(image);
    } else {
      // Use original image without game info
      finalImage = image;
    }

    filename = determineFilename(filename, storageLocation);
    logger.i("Screenshot captured, proceeding to save...");
    await saveImage(finalImage, filename);
  }

  static bool isSupportedPlatform() => !kIsWeb && Platform.isAndroid;

  static String determineFilename(String? filename, String storageLocation) {
    if (filename != null && storageLocation != 'gallery') {
      return filename;
    }

    final DateTime now = DateTime.now();
    final String? prefix = GameController().loadedGameFilenamePrefix;
    // Use the prefix if it's not null; otherwise, default to 'sanmill'
    if (prefix != null) {
      return 'sanmill-screenshot_${prefix}_${formatDateTime(now)}.jpg';
    } else {
      return 'sanmill-screenshot_${formatDateTime(now)}.jpg';
    }
  }

  static String formatDateTime(DateTime dateTime) {
    return '${dateTime.year}${dateTime.month.toString().padLeft(2, '0')}${dateTime.day.toString().padLeft(2, '0')}_'
        '${dateTime.hour}${dateTime.minute}${dateTime.second}';
  }

  static Future<void> saveImage(Uint8List image, String filename) async {
    if (EnvironmentConfig.test == true) {
      return;
    }

    try {
      if (filename.startsWith('sanmill-screenshot')) {
        // For mobile platforms, save directly to the gallery
        if (kIsWeb) {
          logger.e("Saving images to the gallery is not supported on the web");
          rootScaffoldMessengerKey.currentState!.showSnackBar(CustomSnackBar(
              "Saving images to the gallery is not supported on the web"));
          return;
        } else if (Platform.isAndroid || Platform.isIOS) {
          final FutureOr<dynamic> result =
              await ImageGallerySaverPlus.saveImage(image, name: filename);
          handleSaveImageResult(result, filename);
        } else {
          // For desktop platforms, save to the 'screenshots' directory
          final String? path = await getFilePath('screenshots/$filename');
          if (path != null) {
            final File file = File(path);
            await file.writeAsBytes(image);
            logger.i("$_logTag Image saved to $path");
            rootScaffoldMessengerKey.currentState!.showSnackBar(
              CustomSnackBar(path),
            );
          }
        }
      } else {
        // For auto-screenshot specific files, save them directly using the path in filename
        final File file = File(filename);
        await file.writeAsBytes(image);
        logger.i("$_logTag Image saved to $filename");
      }
    } catch (e) {
      logger.e("Failed to save image: $e");
      rootScaffoldMessengerKey.currentState!
          .showSnackBar(CustomSnackBar("Failed to save image: $e"));
    }
  }

  static void handleSaveImageResult(dynamic result, String filename) {
    if (result is Map) {
      final Map<String, dynamic> resultMap = Map<String, dynamic>.from(result);
      if (resultMap['isSuccess'] == true) {
        logger.i("Image saved to Gallery with path ${resultMap['filePath']}");
        rootScaffoldMessengerKey.currentState!.showSnackBar(
          CustomSnackBar(filename),
        );
      } else {
        logger.e("$_logTag Failed to save image to Gallery");
        // TODO: Use S.of(context).failedToSaveImageToGallery
        rootScaffoldMessengerKey.currentState!
            .showSnackBar(CustomSnackBar("Failed to save image to Gallery"));
      }
    } else {
      logger.e("Unexpected result type");
      rootScaffoldMessengerKey.currentState!
          .showSnackBar(CustomSnackBar("Unexpected result type"));
    }
  }

  static Future<String?> getFilePath(String filename) async {
    Directory? directory;
    // TODO: Change to correct path
    if (Platform.isAndroid) {
      directory = await getExternalStorageDirectory();
    } else {
      directory = await getApplicationDocumentsDirectory();
    }

    // Ensure directory exists
    if (directory != null) {
      return path.join(directory.path, filename);
    } else {
      return null;
    }
  }

  /// Adds game info to the screenshot image.
  static Future<Uint8List> _addGameInfoToImage(Uint8List originalImage) async {
    // Decode the original screenshot and get its dimensions.
    final ui.Codec codec = await ui.instantiateImageCodec(originalImage);
    final ui.FrameInfo frameInfo = await codec.getNextFrame();
    final ui.Image baseImage = frameInfo.image;
    final int baseWidth = baseImage.width;
    final int baseHeight = baseImage.height;

    // We only need one horizontal line for the game info.
    const int extraHeight = 60; // Adjust if needed
    final int newWidth = baseWidth;
    final int newHeight = baseHeight + extraHeight;

    // Create a PictureRecorder and Canvas to draw the new image.
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    // Draw a white background for the entire new image.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, newWidth.toDouble(), newHeight.toDouble()),
      Paint()..color = Colors.white,
    );

    // Draw the original screenshot at the top.
    canvas.drawImage(baseImage, Offset.zero, Paint());

    // Prepare to draw the game info line.
    final double textStartY = baseHeight + 10.0;

    // Define the TextStyle for the game info (monospaced font can be used if needed).
    const TextStyle gameInfoStyle = TextStyle(
      color: Colors.black,
      fontSize: 20,
      // fontFamily: 'Courier', // Uncomment to force monospaced characters
    );

    // Retrieve game position.
    final Position position = GameController().position;

    // 1) Phase symbols: [⬇️] ↔️ if Placing, ⬇️ [↔️] if Moving.
    final String phaseSymbols =
        position.phase == Phase.placing ? "[⬇️] ↔️ " : " ⬇️ [↔️]";

    // 2) Turn indicator: add brackets if it is that side's turn.
    final String whiteTurnEmoji =
        (position.sideToMove == PieceColor.white) ? "[⚪]" : " ⚪ ";
    final String blackTurnEmoji =
        (position.sideToMove == PieceColor.black) ? "[⚫]" : " ⚫ ";

    // 3) Calculate removed pieces.
    final int totalPieces = DB().ruleSettings.piecesCount;
    final int whiteRemoved = totalPieces -
        (position.pieceInHandCount[PieceColor.white]! +
            position.pieceOnBoardCount[PieceColor.white]!);
    final int blackRemoved = totalPieces -
        (position.pieceInHandCount[PieceColor.black]! +
            position.pieceOnBoardCount[PieceColor.black]!);

    // 4) Piece info for White and Black using emojis:
    //    🖐️ for in-hand, 🪟 for on-board, 🗑️ for removed.
    final String whiteInfo =
        "$whiteTurnEmoji 🖐️${position.pieceInHandCount[PieceColor.white]} 🪟${position.pieceOnBoardCount[PieceColor.white]} 🗑️$whiteRemoved";
    final String blackInfo =
        "$blackTurnEmoji 🖐️${position.pieceInHandCount[PieceColor.black]} 🪟${position.pieceOnBoardCount[PieceColor.black]} 🗑️$blackRemoved";

    // 5) Recent moves: prefix with 📄.
    final List<ExtMove> moves = GameController().gameRecorder.mainlineMoves;
    String movesEmoji = "";
    if (moves.isNotEmpty) {
      if (moves.length == 1) {
        movesEmoji = "📄 ${moves.last.notation}";
      } else {
        if (moves.last.notation[0] == 'x') {
          movesEmoji =
              "📄 ${moves[moves.length - 2].notation}${moves.last.notation}";
        } else {
          movesEmoji =
              "📄 ${moves[moves.length - 2].notation} ${moves.last.notation}";
        }
      }
    }

    // Combine all game info elements into one horizontal line.
    final String singleLine =
        "$phaseSymbols      $whiteInfo    $blackInfo      $movesEmoji";

    // Draw the combined line centered horizontally.
    _drawTextCentered(
        canvas, singleLine, newWidth.toDouble(), textStartY, gameInfoStyle);

    // End recording and convert the new image to PNG bytes.
    final ui.Picture picture = recorder.endRecording();
    final ui.Image newImage = await picture.toImage(newWidth, newHeight);
    final ByteData? byteData =
        await newImage.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  /// Helper function to draw centered text on the canvas.
  static void _drawTextCentered(
    Canvas canvas,
    String text,
    double containerWidth,
    double yOffset,
    TextStyle style,
  ) {
    final TextSpan span = TextSpan(text: text, style: style);
    final TextPainter tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    // Calculate horizontal offset to center the text in the container
    final double xOffset = (containerWidth - tp.width) / 2;
    tp.paint(canvas, Offset(xOffset, yOffset));
  }
}
