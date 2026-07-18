// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/puzzle/services/puzzle_export_service.dart';
import 'package:sanmill/puzzle/services/puzzle_import_localization.dart';

void main() {
  test('localizes puzzle import failures without exposing raw exceptions', () {
    final S strings = lookupS(const Locale('en'));

    expect(
      ImportResult(
        success: false,
        errorKey: 'puzzleImportErrorReading',
        errorMessage: 'Error reading file: secret path',
      ).localizedError(strings),
      'Could not import puzzles. Choose a valid puzzle file and try again.',
    );
    expect(
      ImportResult(
        success: false,
        errorKey: 'puzzleImportIncompatibleVersion',
        errorParams: <String, dynamic>{'version': '2.0', 'expected': '1.0'},
      ).localizedError(strings),
      'This puzzle file uses format version 2.0; this app supports 1.0.',
    );
  });
}
