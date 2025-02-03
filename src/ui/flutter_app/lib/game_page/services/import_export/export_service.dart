// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// export_service.dart

part of '../mill.dart';

class ExportService {
  const ExportService._();

  /// Exports the game to the device's clipboard.
  static Future<void> exportGame(BuildContext context,
      {bool shouldPop = true}) async {
    await Clipboard.setData(
      ClipboardData(text: GameController().gameRecorder.moveHistoryText),
    );

    if (!context.mounted) {
      return;
    }

    rootScaffoldMessengerKey.currentState!
        .showSnackBarClear(S.of(context).moveHistoryCopied);

    if (shouldPop) {
      Navigator.pop(context);
    }
  }
}
