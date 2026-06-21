// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/games/mill/opening_book/opening_book_models.dart';

void main() {
  group('OpeningEntry.fromJson', () {
    test('parses NMM_LLM snake_case schema with nested branches', () {
      final OpeningEntry entry = OpeningEntry.fromJson(<String, dynamic>{
        'opening_id': 'mill-rush-parallel',
        'name': 'Mill Rush — Parallel',
        'aliases': <String>['Parallel Lines'],
        'family': 'Mill Rush',
        'side': 'W',
        'seed_source': 'book',
        'source_reference': 'Chapter 15.2',
        'confidence': 1.0,
        'tags': <String>['aggressive', 'placement'],
        'strategic_notes': 'Build the b2-d2-f2 mill.',
        'common_blunders': <String>['b4', 'a4'],
        'recommended_responses': <String, dynamic>{
          'B': <String>['b6', 'd6', 'f6'],
        },
        'outcome_stats': <String, dynamic>{'W': 1, 'B': 0, 'D': 0},
        'line_moves': <String>['d2', 'd6', 'f4', 'b4'],
        'favored_side': 'W',
        'branch_moves': <Map<String, dynamic>>[
          <String, dynamic>{
            'branch_id': 'b2-alt',
            'deviation_ply': 7,
            'deviation_move': 'd1',
            'name': 'd1 Variant',
            'line_continuation': <String>['d1', 'b6'],
            'strategic_notes': 'Contest the south cross-line.',
            'seed_source': 'book',
            'outcome_stats': <String, dynamic>{'W': 0, 'B': 0, 'D': 0},
          },
        ],
      });

      expect(entry.id, 'mill-rush-parallel');
      expect(entry.aliases, <String>['Parallel Lines']);
      expect(entry.source, 'book');
      expect(entry.sourceReference, 'Chapter 15.2');
      expect(entry.commonBlunders, <String>['b4', 'a4']);
      expect(entry.recommendedResponses['B'], <String>['b6', 'd6', 'f6']);
      expect(entry.outcomeStats['W'], 1);
      expect(entry.lineMoves, <String>['d2', 'd6', 'f4', 'b4']);
      expect(entry.favoredSide, 'W');
      expect(entry.branchMoves, hasLength(1));
      expect(entry.branchMoves.first.deviationPly, 7);
      expect(entry.branchMoves.first.lineContinuation, <String>['d1', 'b6']);
    });

    test('falls back to neutral defaults for missing fields', () {
      final OpeningEntry entry = OpeningEntry.fromJson(<String, dynamic>{});
      expect(entry.id, '');
      expect(entry.side, 'both');
      expect(entry.source, 'book');
      expect(entry.confidence, 1.0);
      expect(entry.lineMoves, isEmpty);
      expect(entry.branchMoves, isEmpty);
      expect(entry.recommendedResponses, isEmpty);
      expect(entry.favoredSide, 'equal');
    });
  });

  group('OpeningBookData.fromJson', () {
    test('parses oracle map and openings list and round-trips toJson', () {
      final OpeningBookData data = OpeningBookData.fromJson(<String, dynamic>{
        'schemaVersion': 1,
        'variant': 'nmm',
        'symmetry': 'ring16',
        'oracle': <String, dynamic>{
          'fen-a': <String>['d2', 'b4'],
          'fen-b': <String>['f4'],
        },
        'openings': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'o1',
            'name': 'One',
            'lineMoves': <String>['d2', 'd6'],
          },
        ],
      });

      expect(data.variant, 'nmm');
      expect(data.oracle['fen-a'], <String>['d2', 'b4']);
      expect(data.openings.single.id, 'o1');

      final OpeningBookData round = OpeningBookData.fromJson(data.toJson());
      expect(round.oracle['fen-a'], <String>['d2', 'b4']);
      expect(round.openings.single.lineMoves, <String>['d2', 'd6']);
    });
  });
}
