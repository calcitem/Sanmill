// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// save_load_service.dart

part of '../mill.dart';

//@visibleForTesting
class LoadService {
  LoadService._();

  static const String _logTag = "[Loader]";

  /// Retrieves the file path with optional content bytes for Android/iOS.
  static Future<String?> getFilePath(
    BuildContext context, {
    Uint8List? bytes,
  }) async {
    final DateTime now = DateTime.now();
    final String formattedDate =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
    final String defaultFileName = '$formattedDate.pgn';

    // On desktop platforms, use last saved directory as initial directory.
    // On mobile, don't set initialDirectory (SAF limitation).
    final bool isMobilePlatform =
        !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final String lastDirectory = isMobilePlatform
        ? ''
        : DB().generalSettings.lastPgnSaveDirectory;

    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: S.of(context).saveGame,
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: <String>['pgn'],
      bytes: bytes,
      initialDirectory: lastDirectory.isNotEmpty ? lastDirectory : null,
    );

    if (outputFile == null) {
      return null;
    }

    if (!outputFile.toLowerCase().endsWith('.pgn')) {
      outputFile = '$outputFile.pgn';
    }

    GameController().loadedGameFilenamePrefix = extractPgnFilenamePrefix(
      outputFile,
    );

    return outputFile;
  }

  /// Picks file.
  static Future<String?> pickFile(BuildContext context) async {
    // Copy PGN files recursively from ApplicationDocumentsDirectory to
    // ExternalStorageDirectory without overwriting existing files.
    // This is done for compatibility with version 3.x.
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final Directory appDocDir = await getApplicationDocumentsDirectory();
        final String appDocPath = appDocDir.path;
        final Directory? extDir = await getExternalStorageDirectory();
        final String path = '${extDir?.path ?? ""}/records';

        final Directory dir = Directory(path);
        if (!dir.existsSync()) {
          await dir.create(recursive: true);
        }

        final List<FileSystemEntity> entities = appDocDir.listSync(
          recursive: true,
        );

        for (final FileSystemEntity entity in entities) {
          if (entity is File && entity.path.endsWith('.pgn')) {
            final String newPath = entity.path.replaceAll(appDocPath, path);
            final File newFile = File(newPath);

            if (!newFile.existsSync()) {
              await newFile.create(recursive: true);
              await entity.copy(newPath);
            }

            await entity.delete();
          }
        }
      } catch (e) {
        logger.e('$_logTag Error migrating files: $e');
      }
    }

    if (!context.mounted) {
      return null;
    }

    // On desktop platforms, use last saved directory as initial directory.
    // On mobile, don't set initialDirectory (SAF limitation).
    final bool isMobilePlatform =
        !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final String lastDirectory = isMobilePlatform
        ? ''
        : DB().generalSettings.lastPgnSaveDirectory;

    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['pgn'],
      initialDirectory: lastDirectory.isNotEmpty ? lastDirectory : null,
    );

    if (result != null && result.files.single.path != null) {
      return result.files.single.path;
    }

    return null;
  }

  /// Saves the game to the file.
  static Future<String?> saveGame(
    BuildContext context, {
    bool shouldPop = true,
  }) async {
    if (EnvironmentConfig.test == true) {
      return null;
    }

    final String strGameSavedTo = S.of(context).gameSavedTo;

    if (!(GameController().gameRecorder.activeNode?.parent != null ||
        GameController().isPositionSetup == true)) {
      if (shouldPop) {
        Navigator.pop(context);
      }
      return null;
    }

    // Generate content first before calling getFilePath
    final String content = ImportService.addTagPairs(
      GameController().gameRecorder.moveHistoryText,
    );

    // On mobile platforms, provide bytes to FilePicker for automatic saving
    // On desktop platforms, we'll save manually after getting the path
    final bool isMobilePlatform =
        !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final Uint8List? contentBytes = isMobilePlatform
        ? Uint8List.fromList(utf8.encode(content))
        : null;

    final String? filename = await getFilePath(context, bytes: contentBytes);

    if (filename == null) {
      safePop();
      return null;
    }

    // Save the directory path for next time
    _saveLastPgnDirectory(filename);

    // On Android/iOS with bytes provided, file is already saved by FilePicker
    // On desktop platforms, we need to write the file manually
    if (!isMobilePlatform) {
      if (filename.startsWith('content://')) {
        // Handle content:// URIs via platform channel (should not happen on desktop)
        final bool success = await writeContentUri(
          Uri.parse(filename),
          content,
        );

        if (!success) {
          if (!context.mounted) {
            return null;
          }
          // TODO: Add saveFailed localization string
          rootScaffoldMessengerKey.currentState!.showSnackBarClear(
            S.of(context).loadFailed,
          );
          if (shouldPop) {
            safePop();
          }
          return null;
        }
      } else {
        // Use regular file I/O for desktop filesystem paths
        final File file = File(filename);
        await file.writeAsString(content);
      }
    }

    rootScaffoldMessengerKey.currentState!.showSnackBarClear(
      "$strGameSavedTo $filename",
    );

    if (shouldPop) {
      safePop();
    }

    if (GameController().loadedGameFilenamePrefix != null) {
      GameController().headerTipNotifier.showTip(
        GameController().loadedGameFilenamePrefix!,
      );
    }

    return filename;
  }

  /// Main function to load game from a file.
  static Future<void> loadGame(
    BuildContext context,
    String? filePath, {
    required bool isRunning,
    bool shouldPop = true,
  }) async {
    filePath ??= await pickFileIfNeeded(context);

    if (filePath == null) {
      logger.e('$_logTag File path is null');
      return;
    }

    try {
      // Check for 'content' and 'file' prefix in the filePath
      if (filePath.startsWith('content') || filePath.startsWith('file://')) {
        final String? fileContent = await readFileContentFromUri(
          Uri.parse(filePath),
        );
        if (fileContent == null) {
          final Directory? dir = await getExternalStorageDirectory();
          rootScaffoldMessengerKey.currentState!.showSnackBarClear(
            "You should put files in the right place: $dir",
          );
          return;
        }
        GameController().initialSharingMoveList = fileContent;
        if (isRunning == true) {
          // Delay 1s and refresh Game Board
          Future<void>.delayed(const Duration(seconds: 1), () {
            GameController().headerIconsNotifier.showIcons();
            GameController().boardSemanticsNotifier.updateSemantics();
          });
        }
      } else {
        // Assume original file reading logic if not 'content'
        final String fileContent = await readFileContent(filePath);
        logger.t('$_logTag File Content: $fileContent');
        if (!context.mounted) {
          return;
        }
        final bool importSuccess = await importGameData(context, fileContent);
        if (importSuccess) {
          if (!context.mounted) {
            return;
          }
          await handleHistoryNavigation(context);
        }
        if (!context.mounted) {
          return;
        }
        if (shouldPop) {
          Navigator.pop(context); // Only pop if used in a dialog context.
        }
      }
    } catch (exception) {
      if (!context.mounted) {
        return;
      }
      GameController().headerTipNotifier.showTip(S.of(context).loadFailed);
      if (!context.mounted) {
        return;
      }
      if (shouldPop) {
        Navigator.pop(context); // Only pop if used in a dialog context.
      }
      return;
    }
    GameController().loadedGameFilenamePrefix = extractPgnFilenamePrefix(
      filePath,
    );

    // Save the directory path for next time
    _saveLastPgnDirectory(filePath);

    // Delay to show the tip after the navigation tip is shown
    if (GameController().loadedGameFilenamePrefix != null) {
      final String loadedGameFilenamePrefix =
          GameController().loadedGameFilenamePrefix!;
      Future<void>.delayed(Duration.zero, () {
        GameController().headerTipNotifier.showTip(loadedGameFilenamePrefix);
      });
    }
  }

  /// Saves the directory path of the given file path.
  static void _saveLastPgnDirectory(String filePath) {
    try {
      // Skip on Android/iOS: SAF paths can't be enumerated via Directory.listSync()
      // due to Scoped Storage restrictions in Android 11+.
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        return;
      }

      // Skip saving for content:// URIs (platform-managed, no filesystem path).
      if (filePath.startsWith('content://')) {
        return;
      }

      // Normalize to a filesystem path (supports Windows '\' paths and file:// URIs).
      String localPath = filePath;
      if (localPath.startsWith('file://')) {
        localPath = Uri.parse(localPath).toFilePath();
      } else {
        // Only decode when it actually looks like an encoded path.
        if (localPath.contains('%')) {
          try {
            localPath = Uri.decodeFull(localPath);
          } catch (_) {
            // Keep original if decoding fails.
          }
        }
      }

      final String directoryPath = File(localPath).parent.path;

      if (directoryPath.isEmpty) {
        return;
      }

      // Save to settings
      DB().generalSettings = DB().generalSettings.copyWith(
        lastPgnSaveDirectory: directoryPath,
      );
    } catch (e) {
      logger.e('$_logTag Error saving last PGN directory: $e');
    }
  }

  static String? extractPgnFilenamePrefix(String path) {
    // Check if the string ends with '.pgn'
    if (path.toLowerCase().endsWith('.pgn')) {
      try {
        // Decode the entire URI before extraction.
        String decodedPath = path;
        if (decodedPath.startsWith('file://')) {
          decodedPath = Uri.parse(decodedPath).toFilePath();
        } else if (!decodedPath.startsWith("/")) {
          decodedPath = Uri.decodeComponent(decodedPath);
        }

        final String filename = decodedPath.split(RegExp(r'[\\/]+')).last;
        if (!filename.toLowerCase().endsWith('.pgn')) {
          return null;
        }
        return filename.substring(0, filename.length - 4);
      } catch (e) {
        // In case of any error, return null
        return null;
      }
    } else {
      // Return null if the path does not start with 'content:' or does not end with '.pgn'
      // Sometimes legal URI is not contain file name, so return null.
      return null;
    }
  }

  /// Handles user interaction to pick a file.
  static Future<String?> pickFileIfNeeded(BuildContext context) async {
    if (EnvironmentConfig.test == true) {
      return null;
    }

    rootScaffoldMessengerKey.currentState!.clearSnackBars();
    return pickFile(context);
  }

  /// Reads content from a file at the provided path.
  static Future<String> readFileContent(String filePath) async {
    final File file = File(filePath);
    return file.readAsString();
  }

  /// Import game data from file content.
  static Future<bool> importGameData(
    BuildContext context,
    String fileContent,
  ) async {
    try {
      ImportService.import(fileContent);
      logger.t('$_logTag File Content: $fileContent');
      final String tagPairs = getTagPairs(fileContent);

      if (tagPairs.isNotEmpty) {
        rootScaffoldMessengerKey.currentState!.showSnackBar(
          CustomSnackBar(tagPairs),
        );
      }

      return true;
    } catch (exception) {
      // Extract the specific error message instead of showing entire file content
      final String errorMessage = exception.toString();
      final String tip = S.of(context).cannotImport(errorMessage);
      rootScaffoldMessengerKey.currentState?.showSnackBarClear(tip);
      GameController().headerTipNotifier.showTip(tip);

      return false;
    }
  }

  /// Handle game history navigation.
  static Future<void> handleHistoryNavigation(BuildContext context) async {
    await HistoryNavigator.takeBackAll(context, pop: false);

    if (!context.mounted) {
      return;
    }

    if (await HistoryNavigator.stepForwardAll(context, pop: false) ==
        const HistoryOK()) {
      if (!context.mounted) {
        return;
      }

      rootScaffoldMessengerKey.currentState?.showSnackBarClear(
        S.of(context).done,
      );
      GameController().headerTipNotifier.showTip(
        S.of(context).done,
      ); // "Game loaded."
    } else {
      if (!context.mounted) {
        return;
      }

      // Format error message to be more specific if importFailedStr is available
      String errorMessage;
      if (HistoryNavigator.importFailedStr.isNotEmpty) {
        // Show specific segment that failed to import
        errorMessage = HistoryNavigator.importFailedStr;
      } else {
        // Fallback to general error if no specific info is available
        errorMessage = "❌";
      }

      final String tip = S.of(context).cannotImport(errorMessage);
      rootScaffoldMessengerKey.currentState?.showSnackBarClear(tip);
      GameController().headerTipNotifier.showTip(tip);

      HistoryNavigator.importFailedStr = "";
    }
  }

  /// Reads content from a file at the provided content URI.
  static Future<String?> readFileContentFromUri(Uri uri) async {
    String? str;
    try {
      str = await readContentUri(uri);
    } catch (e) {
      logger.e('Error reading file at $uri: $e');
      rethrow;
    }
    return str;
  }
}
