// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../generated/intl/l10n.dart';
import 'puzzle_export_service.dart';

extension PuzzleImportResultLocalization on ImportResult {
  String localizedError(S strings) {
    return switch (errorKey) {
      'puzzleImportInvalidFilePath' => strings.puzzleImportInvalidFilePath,
      'puzzleImportFileNotExist' => strings.puzzleImportFileNotExist,
      'puzzleImportInvalidFormat' => strings.puzzleImportInvalidFormat,
      'puzzleImportIncompatibleVersion' =>
        strings.puzzleImportIncompatibleVersion(
          errorParams!['version']! as String,
          errorParams!['expected']! as String,
        ),
      'puzzleImportErrorPickingFile' ||
      'puzzleImportErrorReading' ||
      null => strings.puzzleImportFailed,
      final String unsupported => _unsupportedErrorKey(strings, unsupported),
    };
  }

  String _unsupportedErrorKey(S strings, String key) {
    assert(false, 'Unsupported puzzle import localization key: $key');
    return strings.puzzleImportFailed;
  }
}
