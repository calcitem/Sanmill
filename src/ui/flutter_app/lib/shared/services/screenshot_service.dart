// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// screenshot_service.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:native_screenshot_widget/native_screenshot_widget.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../game_page/services/mill.dart';
import '../widgets/snackbars/scaffold_messenger.dart';
import 'environment_config.dart';
import 'logger.dart';

class ScreenshotService {
  ScreenshotService._();

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

    filename = determineFilename(filename, storageLocation);
    logger.i("Screenshot captured, proceeding to save...");
    await saveImage(image, filename);
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
              await ImageGallerySaver.saveImage(image, name: filename);
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
}
