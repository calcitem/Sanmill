// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/save_load/saved_game_catalog.dart';

void main() {
  test('saved game summaries classify unfinished PGNs as ongoing', () {
    final DateTime modified = DateTime.utc(2026);
    final SavedGameSummary ongoing = SavedGameSummary(
      path: '/tmp/ongoing.pgn',
      filename: 'ongoing.pgn',
      modified: modified,
      preview: const SavedGamePreview(
        boardLayout: null,
        moveCount: 2,
        result: '*',
      ),
    );
    final SavedGameSummary finished = SavedGameSummary(
      path: '/tmp/finished.pgn',
      filename: 'finished.pgn',
      modified: modified,
      preview: const SavedGamePreview(
        boardLayout: null,
        moveCount: 18,
        result: '1-0',
      ),
    );
    final SavedGameSummary unknown = SavedGameSummary(
      path: '/tmp/unknown.pgn',
      filename: 'unknown.pgn',
      modified: modified,
    );

    expect(ongoing.isOngoing, isTrue);
    expect(finished.isOngoing, isFalse);
    expect(unknown.isOngoing, isFalse);
  });
}
