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

import 'package:flutter/foundation.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:native_screenshot_widget/native_screenshot_widget.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

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
    if (kIsWeb || Platform.isAndroid == false) {
      logger.i("Taking screenshots is not supported on this platform");
      return;
    }

    logger.i("Attempting to capture screenshot...");

    final Uint8List? image = await screenshotController.takeScreenshot();
    if (image == null) {
      logger.e("Failed to capture screenshot: Image is null.");
      return;
    }

    // Generate a unique filename based on current date and time if no filename is provided
    if (filename == null || storageLocation == 'gallery') {
      final DateTime now = DateTime.now();
      filename =
          'sanmill-screenshot_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour}${now.minute}${now.second}.jpg';
    }

    logger.i("Screenshot captured, proceeding to save...");
    await saveImage(image, filename);
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
