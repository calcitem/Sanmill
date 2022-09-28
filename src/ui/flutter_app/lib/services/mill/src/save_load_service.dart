// ignore_for_file: use_build_context_synchronously

// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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

part of '../mill.dart';

@visibleForTesting
class LoadService {
  static const _tag = "[Loader]";

  LoadService._();

  /// Retrieves the file path.
  static Future<String?> getFilePath(BuildContext context) async {
    Directory dir = await getApplicationDocumentsDirectory();
    String path = dir.path;

    var resultLabel = await _showTextInputDialog(context);

    if (resultLabel == null) return null;

    if (resultLabel.endsWith(".pgn") == false) {
      resultLabel = "$resultLabel.pgn";
    }

    String filePath =
        resultLabel.startsWith(path) ? resultLabel : "$path/$resultLabel";

    return filePath;
  }

  /// Picks file.
  static Future<String?> pickFile(BuildContext context) async {
    Directory dir = await getApplicationDocumentsDirectory();

    String? result = await FilesystemPicker.openDialog(
      context: context,
      rootDirectory: dir,
      rootName: "Game Files", // TODO: l10n
      fsType: FilesystemType.file,
      permissionText: "Access to the storage was not granted.", // TODO: l10n
      showGoUp: true,
      allowedExtensions: ['.pgn'],
      fileTileSelectMode:
          FileTileSelectMode.checkButton, //  TODO: whole tile is better.
    );

    if (result == null) {
      return null;
    }

    return result;
  }

  /// Saves the game to the file.
  static Future<void> saveGame(BuildContext context) async {
    Navigator.pop(context);

    if (MillController().recorder.hasPrevious == false) {
      return;
    }

    final filename = await getFilePath(context);

    if (filename == null) return;

    File file = File(filename);

    file.writeAsString(MillController().recorder.moveHistoryText!);

    rootScaffoldMessengerKey.currentState!
        .showSnackBarClear("File saved."); // TODO: l10n
  }

  /// Read the game from the file.
  static Future<void> loadGame(BuildContext context) async {
    rootScaffoldMessengerKey.currentState!.clearSnackBars();

    String? result = await pickFile(context);
    if (result == null) return;

    File file = File(result);

    late String fileContent;

    try {
      fileContent = await file.readAsString();
    } catch (exception) {
      MillController()
          .headerTipNotifier
          .showTip("Load failed!", snackBar: true); // TODO: l10n
      Navigator.pop(context);
      return;
    }

    logger.v('File Content: $fileContent');

    try {
      ImportService.import(
          fileContent); // MillController().newRecorder = newHistory;
    } catch (exception) {
      final tip = S.of(context).cannotImport(fileContent);
      MillController().headerTipNotifier.showTip(tip, snackBar: true);
      Navigator.pop(context);
      return;
    }

    // TODO: Duplicate
    await HistoryNavigator.takeBackAll(context, pop: false);

    if (await HistoryNavigator.stepForwardAll(context, pop: false) ==
        const HistoryOK()) {
      MillController()
          .headerTipNotifier
          .showTip("Game loaded.", snackBar: true); // l10n
    } else {
      final tip = S.of(context).cannotImport(HistoryNavigator.importFailedStr);
      MillController().headerTipNotifier.showTip(tip, snackBar: true);
      HistoryNavigator.importFailedStr = "";
    }

    Navigator.pop(context);
  }

  static Future<String?> _showTextInputDialog(BuildContext context) async {
    var textFieldController = TextEditingController();
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('File Name'), // TODO: l10n
          content: TextField(
            controller: textFieldController,
            decoration: const InputDecoration(
              suffixText: ".pgn",
              enabled: true,
            ),
          ),
          actions: <Widget>[
            ElevatedButton(
                child: const Text("Browse..."), // TODO: l10n
                onPressed: () async {
                  var result = await pickFile(context);
                  if (result == null) return;
                  textFieldController.text = result;
                  Navigator.pop(context, textFieldController.text);
                }),
            ElevatedButton(
              child: const Text("Close"), // TODO: l10n
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              child: const Text('OK'), // TODO: l10n
              onPressed: () => Navigator.pop(context, textFieldController.text),
            ),
          ],
        );
      },
      barrierDismissible: false,
    );
  }
}
