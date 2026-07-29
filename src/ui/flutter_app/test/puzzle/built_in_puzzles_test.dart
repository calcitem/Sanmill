// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// built_in_puzzles_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/puzzle/services/built_in_puzzles.dart';

/// Reads a puzzle asset directly from the project tree.
///
/// Flutter unit tests run with the working directory at the package root,
/// so the bundle asset key doubles as a file path -- the same trick used by
/// `opening_book_test_assets.dart` for the opening book.
Future<String> _loadBuiltInPuzzlesAssetFromDisk(String assetKey) {
  return File(assetKey).readAsString();
}

void main() {
  setUp(() {
    builtInPuzzlesAssetLoader = _loadBuiltInPuzzlesAssetFromDisk;
  });

  tearDown(() {
    builtInPuzzlesAssetLoader = _loadBuiltInPuzzlesAssetFromDisk;
  });

  group('getBuiltInPuzzles', () {
    test('loads the bundled Malom Perfect DB puzzle pack from disk', () async {
      final List<PuzzleInfo> puzzles = await getBuiltInPuzzles();

      expect(puzzles, isNotEmpty);
      expect(puzzles, hasLength(177));
      expect(
        puzzles.any(
          (PuzzleInfo puzzle) =>
              puzzle.title == 'White · Win in 5: immobilize the opponent',
        ),
        isTrue,
      );
      expect(
        puzzles.any(
          (PuzzleInfo puzzle) => puzzle.title.contains('leave them no move'),
        ),
        isFalse,
      );
      for (final PuzzleInfo puzzle in puzzles) {
        expect(puzzle.id, isNotEmpty);
        expect(puzzle.solutions, isNotEmpty);
        expect(puzzle.isCustom, isFalse);
        for (final PuzzleSolution solution in puzzle.solutions) {
          expect(solution.moves, isNotEmpty);
        }
      }
    });

    test('every puzzle id in the bundled pack is unique', () async {
      final List<PuzzleInfo> puzzles = await getBuiltInPuzzles();
      final Set<String> ids = puzzles.map((PuzzleInfo p) => p.id).toSet();
      expect(ids.length, puzzles.length);
    });

    test('beginner puzzles introduce three different concepts', () async {
      final List<PuzzleInfo> puzzles = await getBuiltInPuzzles();
      final List<PuzzleInfo> beginnerPuzzles = puzzles
          .where((PuzzleInfo puzzle) => puzzle.difficulty.name == 'beginner')
          .toList();
      final Set<String> topics = beginnerPuzzles
          .expand(
            (PuzzleInfo puzzle) =>
                puzzle.tags.where((String tag) => tag.startsWith('topic:')),
          )
          .toSet();

      expect(beginnerPuzzles, hasLength(3));
      expect(topics, <String>{
        'topic:capture-choice',
        'topic:mill-block',
        'topic:immobilization',
      });
    });

    test('player-facing descriptions stay concise and non-technical', () async {
      final List<PuzzleInfo> puzzles = await getBuiltInPuzzles();
      final RegExp winObjective = RegExp(
        r'^(White|Black) to move\. Find the forced win in \d+ moves?\.$',
      );
      final RegExp drawObjective = RegExp(
        r'^(White|Black) to move\. Find the only move that preserves the draw; every other legal move loses\.$',
      );
      const List<String> technicalTerms = <String>[
        'Perfect DB',
        'Rust/TGF',
        'Z3',
        'principal variation',
        'replay witness',
        'anonymised',
      ];

      for (final PuzzleInfo puzzle in puzzles) {
        expect(
          puzzle.description,
          matches(
            puzzle.category == PuzzleCategory.defend
                ? drawObjective
                : winObjective,
          ),
          reason: puzzle.id,
        );
        for (final String term in technicalTerms) {
          expect(puzzle.description, isNot(contains(term)), reason: puzzle.id);
        }
      }
    });

    test('public objectives agree with every optimal solution', () async {
      final List<PuzzleInfo> puzzles = await getBuiltInPuzzles();
      final RegExp winTitle = RegExp(r'^(White|Black) · Win in (\d+)(?::.*)?$');
      final RegExp drawTitle = RegExp(
        r'^(White|Black) · Hold the draw(?::.*)?$',
      );
      int winCount = 0;
      int drawCount = 0;

      for (final PuzzleInfo puzzle in puzzles) {
        final String sideName =
            puzzle.initialPosition.split(RegExp(r'\s+'))[1] == 'w'
            ? 'White'
            : 'Black';
        final solverSide = puzzle.solutions.first.moves.first.side;
        expect(solverSide.name, sideName.toLowerCase(), reason: puzzle.id);
        final Set<int> optimalCounts = puzzle.solutions
            .where((PuzzleSolution solution) => solution.isOptimal)
            .map(
              (PuzzleSolution solution) =>
                  solution.getPlayerMoveCount(solverSide),
            )
            .toSet();
        expect(optimalCounts, hasLength(1), reason: puzzle.id);
        final int moveCount = optimalCounts.single;
        expect(moveCount, greaterThan(0), reason: puzzle.id);

        switch (puzzle.category) {
          case PuzzleCategory.winGame:
          case PuzzleCategory.opening:
            winCount += 1;
            final RegExpMatch? match = winTitle.firstMatch(puzzle.title);
            expect(match, isNotNull, reason: puzzle.id);
            expect(match!.group(1), sideName, reason: puzzle.id);
            expect(int.parse(match.group(2)!), moveCount, reason: puzzle.id);
            expect(
              puzzle.tags.where((String tag) => tag.startsWith('win-in-')),
              <String>['win-in-$moveCount'],
              reason: puzzle.id,
            );
            expect(puzzle.tags, contains('objective:win'), reason: puzzle.id);
            expect(puzzle.id, contains('_${moveCount}_'), reason: puzzle.id);
          case PuzzleCategory.defend:
            drawCount += 1;
            final RegExpMatch? match = drawTitle.firstMatch(puzzle.title);
            expect(match, isNotNull, reason: puzzle.id);
            expect(match!.group(1), sideName, reason: puzzle.id);
            expect(moveCount, 1, reason: puzzle.id);
            expect(
              puzzle.tags,
              containsAll(<String>[
                'objective:hold-draw',
                'hold-draw-in-1',
                'unique-draw-save',
              ]),
              reason: puzzle.id,
            );
          case PuzzleCategory.formMill:
          case PuzzleCategory.capturePieces:
          case PuzzleCategory.findBestMove:
          case PuzzleCategory.endgame:
          case PuzzleCategory.mixed:
            fail(
              '${puzzle.id} has unsupported built-in objective '
              '${puzzle.category.name}',
            );
        }
      }

      expect(winCount, 167);
      expect(drawCount, 10);
    });

    test('the embedded expert-review batches remain identifiable', () async {
      final Map<String, dynamic> package =
          jsonDecode(
                await _loadBuiltInPuzzlesAssetFromDisk(builtInPuzzlesAsset),
              )
              as Map<String, dynamic>;
      final Map<String, dynamic> metadata =
          package['metadata']! as Map<String, dynamic>;
      expect(metadata['version'], '1.7.0-review.1');
      expect(metadata['isOfficial'], isFalse);

      final List<Map<String, dynamic>> reviewBatches =
          (package['reviewBatches']! as List<dynamic>)
              .cast<Map<String, dynamic>>();
      expect(reviewBatches, hasLength(4));
      expect(
        <String, int>{
          for (final Map<String, dynamic> batch in reviewBatches)
            batch['id']! as String: batch['puzzleCount']! as int,
        },
        <String, int>{
          'engine-blunder-review-selected-30': 30,
          'strategy-theme-review-selected-10': 10,
          'similarity-repair-selected-16': 16,
          'draw-defence-review-selected-10': 10,
        },
      );
      for (final Map<String, dynamic> batch in reviewBatches) {
        expect(batch['status'], 'expert-pending');
        expect(
          (batch['selectionProvenance']! as Map<String, dynamic>)['status'],
          'OPTIMAL',
        );
      }

      final List<Map<String, dynamic>> reviewPuzzles =
          (package['puzzles']! as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .where(
                (Map<String, dynamic> puzzle) =>
                    (puzzle['tags']! as List<dynamic>).contains(
                      'review-status:expert-pending',
                    ),
              )
              .toList();
      expect(reviewPuzzles, hasLength(66));
      final Map<String, int> puzzleBatchCounts = <String, int>{};
      for (final Map<String, dynamic> puzzle in reviewPuzzles) {
        final List<dynamic> tags = puzzle['tags']! as List<dynamic>;
        expect(
          tags.any(
            (dynamic tag) =>
                tag == 'discovery:engine-blunder-corpus' ||
                tag == 'discovery:smt-z3' ||
                tag == 'discovery:broad-perfect-db-sampling' ||
                tag == 'discovery:outcome-contrast',
          ),
          isTrue,
          reason: puzzle['id']! as String,
        );
        final List<String> batchTags = tags
            .cast<String>()
            .where((String tag) => tag.startsWith('review-batch:'))
            .toList();
        expect(batchTags, hasLength(1), reason: puzzle['id']! as String);
        final String batch = batchTags.single.substring('review-batch:'.length);
        expect(
          reviewBatches.any(
            (Map<String, dynamic> record) => record['id'] == batch,
          ),
          isTrue,
          reason: puzzle['id']! as String,
        );
        puzzleBatchCounts.update(
          batch,
          (int count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      expect(puzzleBatchCounts, <String, int>{
        'engine-blunder-review-selected-30': 30,
        'strategy-theme-review-selected-10': 10,
        'similarity-repair-selected-16': 16,
        'draw-defence-review-selected-10': 10,
      });
    });

    test(
      'the bundled pack is classified as a progressive curriculum',
      () async {
        final List<PuzzleInfo> puzzles = await getBuiltInPuzzles();
        const List<String> topicOrder = <String>[
          'capture-choice',
          'quiet-move',
          'mill-block',
          'allow-mill',
          'greedy-mill-trap',
          'wrong-mill-trap',
          'double-mill',
          'dual-threat',
          'right-angle-threat',
          'mill-recovery',
          'mill-abandonment',
          'junction-release',
          'ring-transfer',
          'sacrifice',
          'mobility-squeeze',
          'draw-save',
          'immobilization',
          'flying-defence',
          'zugzwang',
          'calculation',
        ];
        const Map<String, int> difficultyRank = <String, int>{
          'beginner': 1,
          'easy': 2,
          'medium': 3,
          'hard': 4,
          'expert': 5,
        };

        final List<List<PuzzleInfo>> curriculumSections = <List<PuzzleInfo>>[
          puzzles
              .where(
                (PuzzleInfo puzzle) =>
                    !puzzle.tags.contains('review-status:expert-pending'),
              )
              .toList(),
          puzzles
              .where(
                (PuzzleInfo puzzle) =>
                    puzzle.tags.contains('review-status:expert-pending'),
              )
              .toList(),
        ];
        for (final List<PuzzleInfo> section in curriculumSections) {
          int previousTopic = -1;
          int previousDifficulty = -1;
          for (final PuzzleInfo puzzle in section) {
            final List<String> topics = puzzle.tags
                .where((String tag) => tag.startsWith('topic:'))
                .toList();
            final List<String> curricula = puzzle.tags
                .where((String tag) => tag.startsWith('curriculum:'))
                .toList();
            final List<String> progression = puzzle.tags
                .where((String tag) => tag.startsWith('progression:'))
                .toList();
            final List<String> distanceBands = puzzle.tags
                .where((String tag) => tag.startsWith('distance-band:'))
                .toList();
            expect(topics, hasLength(1), reason: puzzle.id);
            expect(curricula, hasLength(1), reason: puzzle.id);
            expect(progression, hasLength(1), reason: puzzle.id);
            expect(distanceBands, hasLength(1), reason: puzzle.id);

            final int topic = topicOrder.indexOf(
              topics.single.substring('topic:'.length),
            );
            final int difficulty = difficultyRank[puzzle.difficulty.name]!;
            expect(topic, greaterThanOrEqualTo(0), reason: puzzle.id);
            expect(
              progression.single,
              'progression:$difficulty-${puzzle.difficulty.name}',
              reason: puzzle.id,
            );
            expect(
              topic,
              greaterThanOrEqualTo(previousTopic),
              reason: puzzle.id,
            );
            if (topic == previousTopic) {
              expect(
                difficulty,
                greaterThanOrEqualTo(previousDifficulty),
                reason: puzzle.id,
              );
            } else {
              previousDifficulty = -1;
            }
            previousTopic = topic;
            previousDifficulty = difficulty;
          }
        }
      },
    );

    test('replay-backed puzzles retain anonymised provenance', () async {
      final Map<String, dynamic> package =
          jsonDecode(
                await _loadBuiltInPuzzlesAssetFromDisk(builtInPuzzlesAsset),
              )
              as Map<String, dynamic>;
      final List<dynamic> puzzles = package['puzzles']! as List<dynamic>;
      final List<Map<String, dynamic>> replayPuzzles = puzzles
          .cast<Map<String, dynamic>>()
          .where(
            (Map<String, dynamic> puzzle) => (puzzle['tags']! as List<dynamic>)
                .contains('source:replay-backed'),
          )
          .toList();
      expect(replayPuzzles, hasLength(13));

      final RegExp sha256 = RegExp(r'^[0-9a-f]{64}$');
      for (final Map<String, dynamic> puzzle in replayPuzzles) {
        final List<dynamic> tags = puzzle['tags']! as List<dynamic>;
        expect(
          tags,
          contains('human-missed-win'),
          reason: puzzle['id'] as String,
        );
        expect(
          tags,
          contains('solution-display:principal-variation'),
          reason: puzzle['id'] as String,
        );
        expect(tags, isNot(contains('source:composed')));

        final Map<String, dynamic> provenance =
            puzzle['provenance']! as Map<String, dynamic>;
        expect(provenance['kind'], 'human-game-replay');
        expect(provenance['transformModel'], 'sanmill-ring16-v1');
        expect(
          sha256.hasMatch(provenance['databaseSha256']! as String),
          isTrue,
        );
        expect(
          sha256.hasMatch(provenance['sourceGameSha256']! as String),
          isTrue,
        );
        expect(
          provenance['presentationTransform']! as int,
          inInclusiveRange(0, 15),
        );
        final List<dynamic> history =
            provenance['replayHistory']! as List<dynamic>;
        expect(
          provenance['sourceLogicalPly'],
          history.length + 1,
          reason: puzzle['id'] as String,
        );
        expect(provenance['recordedTurn'], isNotEmpty);
      }
    });

    test('a missing asset degrades to an empty list, not a throw', () async {
      builtInPuzzlesAssetLoader = (String key) async =>
          throw const FileSystemException('missing');

      final List<PuzzleInfo> puzzles = await getBuiltInPuzzles();

      expect(puzzles, isEmpty);
    });

    test('malformed JSON degrades to an empty list, not a throw', () async {
      builtInPuzzlesAssetLoader = (String key) async => 'not json';

      final List<PuzzleInfo> puzzles = await getBuiltInPuzzles();

      expect(puzzles, isEmpty);
    });

    test(
      'a JSON object without a puzzles array yields an empty list',
      () async {
        builtInPuzzlesAssetLoader = (String key) async =>
            '{"formatVersion": "1.0"}';

        final List<PuzzleInfo> puzzles = await getBuiltInPuzzles();

        expect(puzzles, isEmpty);
      },
    );
  });
}
