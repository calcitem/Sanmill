// This file is part of Sanmill.
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)
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

// ignore_for_file: use_build_context_synchronously

part of '../mill.dart';

//@visibleForTesting
class LoadService {
  LoadService._();

  static const String _logTag = "[Loader]";

  /// Retrieves the file path.
  static Future<String?> getFilePath(BuildContext context) async {
    Directory? dir = (!kIsWeb && Platform.isAndroid)
        ? await getExternalStorageDirectory()
        : await getApplicationDocumentsDirectory();
    final String path = '${dir?.path ?? ""}/records';

    // Ensure the folder exists
    dir = Directory(path);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    String? resultLabel = await _showTextInputDialog(context);

    if (resultLabel == null) {
      return null;
    }

    GameController().loadedGameFilenamePrefix = resultLabel;

    if (resultLabel.endsWith(".pgn") == false) {
      resultLabel = "$resultLabel.pgn";
    }

    final String filePath =
        resultLabel.startsWith(path) ? resultLabel : "$path/$resultLabel";

    return filePath;
  }

  /// Picks file.
  static Future<String?> pickFile(BuildContext context) async {
    late Directory? dir;

    dir = (!kIsWeb && Platform.isAndroid)
        ? await getExternalStorageDirectory()
        : await getApplicationDocumentsDirectory();
    final String path = '${dir?.path ?? ""}/records';

    // Ensure the folder exists
    dir = Directory(path);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    // Copy PGN files recursively from ApplicationDocumentsDirectory to
    // ExternalStorageDirectory without overwriting existing files.
    // This is done for compatibility with version 3.x.
    if (!kIsWeb && Platform.isAndroid) {
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String appDocPath = appDocDir.path;
      final List<FileSystemEntity> entities =
          appDocDir.listSync(recursive: true);

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
    }

    final String? result = await FilesystemPicker.openDialog(
      context: context,
      rootDirectory: dir,
      rootName: S.of(context).gameFiles,
      fsType: FilesystemType.file,
      showGoUp: !kIsWeb && !Platform.isLinux,
      allowedExtensions: <String>[".pgn"],
      fileTileSelectMode:
          FileTileSelectMode.checkButton, // TODO: whole tile is better.
      theme: const FilesystemPickerTheme(
        backgroundColor: Colors.greenAccent,
      ),
    );

    if (result == null) {
      return null;
    }

    return result;
  }

  /// Saves the game to the file.
  static Future<String?> saveGame(BuildContext context) async {
    if (EnvironmentConfig.test == true) {
      return null;
    }

    final String strGameSavedTo = S.of(context).gameSavedTo;

    if (!(GameController().gameRecorder.hasPrevious == true ||
        GameController().isPositionSetup == true)) {
      Navigator.pop(context);
      return null;
    }

    final String? filename = await getFilePath(context);

    if (filename == null) {
      safePop();
      return null;
    }

    final File file = File(filename);
    file.writeAsString(ImportService.addTagPairs(
        GameController().gameRecorder.moveHistoryText));

    rootScaffoldMessengerKey.currentState!
        .showSnackBarClear("$strGameSavedTo $filename");

    safePop();

    // Wait for the dialog to disappear before taking a screenshot
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      ScreenshotService.takeScreenshot("records", "$filename.jpg");

      if (GameController().loadedGameFilenamePrefix != null) {
        GameController()
            .headerTipNotifier
            .showTip(GameController().loadedGameFilenamePrefix!);
      }
    });

    return filename;
  }

  /// Main function to load game from a file.
  static Future<void> loadGame(BuildContext context, String? filePath,
      {required bool isRunning}) async {
    filePath ??= await pickFileIfNeeded(context);

    if (filePath == null) {
      logger.e('$_logTag File path is null');
      return;
    }

    try {
      // Check for 'content' and 'file' prefix in the filePath
      if (filePath.startsWith('content') || filePath.startsWith('file://')) {
        final String? fileContent =
            await readFileContentFromUri(Uri.parse(filePath));
        if (fileContent == null) {
          final Directory? dir = await getExternalStorageDirectory();
          rootScaffoldMessengerKey.currentState!.showSnackBarClear(
              "You should put files in the right place: $dir");
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
        final bool importSuccess = await importGameData(context, fileContent);
        if (importSuccess) {
          await handleHistoryNavigation(context);
        }
        Navigator.pop(context);
      }
    } catch (exception) {
      GameController().headerTipNotifier.showTip(S.of(context).loadFailed);
      Navigator.pop(context);
      return;
    }
    GameController().loadedGameFilenamePrefix =
        extractPgnFilenamePrefix(filePath);

    // Delay to show the tip after the navigation tip is shown
    if (GameController().loadedGameFilenamePrefix != null) {
      final String loadedGameFilenamePrefix =
          GameController().loadedGameFilenamePrefix!;
      Future<void>.delayed(Duration.zero, () {
        GameController().headerTipNotifier.showTip(loadedGameFilenamePrefix);
      });
    }
  }

  static String? extractPgnFilenamePrefix(String path) {
    // Check if the string ends with '.pgn'
    if (path.endsWith('.pgn')) {
      try {
        // Decode the entire URI before extraction
        final String decodedPath;
        if (path.startsWith("/")) {
          decodedPath = path;
        } else {
          decodedPath = Uri.decodeComponent(path);
        }

        // Find the last index of '/'
        final int lastIndex = decodedPath.lastIndexOf('/');
        if (lastIndex == -1) {
          return null;
        }
        // Extract the substring from the character after '/' to the start of '.pgn'
        return decodedPath.substring(lastIndex + 1, decodedPath.length - 4);
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
      BuildContext context, String fileContent) async {
    try {
      ImportService.import(fileContent);
      logger.t('$_logTag File Content: $fileContent');
      final String tagPairs = ImportService.getTagPairs(fileContent);

      if (tagPairs.isNotEmpty) {
        rootScaffoldMessengerKey.currentState!
            .showSnackBar(CustomSnackBar(tagPairs));
      }

      return true;
    } catch (exception) {
      final String tip = S.of(context).cannotImport(fileContent);
      GameController().headerTipNotifier.showTip(tip);
      Navigator.pop(context);
      return false;
    }
  }

  /// Handle game history navigation.
  static Future<void> handleHistoryNavigation(BuildContext context) async {
    await HistoryNavigator.takeBackAll(context, pop: false);

    if (await HistoryNavigator.stepForwardAll(context, pop: false) ==
        const HistoryOK()) {
      GameController()
          .headerTipNotifier
          .showTip(S.of(context).done); // "Game loaded."
    } else {
      final String tip =
          S.of(context).cannotImport(HistoryNavigator.importFailedStr);
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

  static Future<String?> _showTextInputDialog(BuildContext context) async {
    final TextEditingController textFieldController = TextEditingController();
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            S.of(context).filename,
            style: TextStyle(
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
          ),
          content: TextField(
            controller: textFieldController,
            decoration: const InputDecoration(
              suffixText: ".pgn",
            ),
          ),
          actions: <Widget>[
            ElevatedButton(
                child: Text(
                  S.of(context).browse,
                  style: TextStyle(
                      fontSize:
                          AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
                ),
                onPressed: () async {
                  final String? result = await pickFile(context);
                  if (result == null) {
                    return;
                  }
                  textFieldController.text = result;
                  Navigator.pop(context, textFieldController.text);
                }),
            ElevatedButton(
              child: Text(
                S.of(context).cancel,
                style: TextStyle(
                    fontSize:
                        AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              child: Text(
                S.of(context).ok,
                style: TextStyle(
                    fontSize:
                        AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
              ),
              onPressed: () => Navigator.pop(context, textFieldController.text),
            ),
          ],
        );
      },
      barrierDismissible: false,
    );
  }
}
