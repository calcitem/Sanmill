// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// transform_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/game_page/services/transform/transform.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    "com.calcitem.sanmill/engine",
  );

  setUp(() {
    DB.instance = MockDB();
    initBitboards();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
  });

  // ---------------------------------------------------------------------------
  // transformString
  // ---------------------------------------------------------------------------
  group('transformString', () {
    // A known 24-character board string for testing
    // Positions: 0-7 inner, 8-15 middle, 16-23 outer
    const String sample = 'ABCDEFGHIJKLMNOPQRSTUVWX';

    test('identity should return the same string', () {
      expect(
        transformString(sample, TransformationType.identity),
        sample,
      );
    });

    test('identity applied twice should be unchanged', () {
      final String first = transformString(
        sample,
        TransformationType.identity,
      );
      final String second = transformString(
        first,
        TransformationType.identity,
      );
      expect(second, sample);
    });

    test('rotate90 applied four times should return original', () {
      String result = sample;
      for (int i = 0; i < 4; i++) {
        result = transformString(result, TransformationType.rotate90);
      }
      expect(result, sample);
    });

    test('horizontalFlip applied twice should return original', () {
      String result = sample;
      result = transformString(result, TransformationType.mirrorHorizontal);
      result = transformString(result, TransformationType.mirrorHorizontal);
      expect(result, sample);
    });

    test('verticalFlip applied twice should return original', () {
      String result = sample;
      result = transformString(result, TransformationType.mirrorVertical);
      result = transformString(result, TransformationType.mirrorVertical);
      expect(result, sample);
    });

    test('innerOuterFlip applied twice should return original', () {
      String result = sample;
      result = transformString(result, TransformationType.swap);
      result = transformString(result, TransformationType.swap);
      expect(result, sample);
    });

    test('should reject strings not exactly 24 characters', () {
      expect(
        () => transformString('short', TransformationType.identity),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => transformString(
          'this is way too long for a board string!!',
          TransformationType.identity,
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => transformString('', TransformationType.identity),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rotate90 should shift inner ring positions by 2', () {
      // Inner ring: positions 0-7
      // After rotate90, position i goes to position (i+2)%8
      // So 'A' (pos 0) goes to pos 2, 'B' (pos 1) goes to pos 3, etc.
      final String result = transformString(
        sample,
        TransformationType.rotate90,
      );
      // The mapping is: result[newPosition[i]] = sample[i]
      // For rotate90: newPosition = [2,3,4,5,6,7,0,1, 10,11,12,13,14,15,8,9, ...]
      // So result[2]=A, result[3]=B, result[0]=G, result[1]=H
      expect(result[0], 'G');
      expect(result[1], 'H');
      expect(result[2], 'A');
      expect(result[3], 'B');
    });

    test('innerOuterFlip should swap inner and outer rings', () {
      final String result = transformString(
        sample,
        TransformationType.swap,
      );
      // Inner (0-7) and outer (16-23) should swap
      // Middle (8-15) stays in middle
      // After flip: result[16..23] = A..H, result[8..15] = I..P, result[0..7] = Q..X
      expect(result.substring(0, 8), 'QRSTUVWX');
      expect(result.substring(8, 16), 'IJKLMNOP');
      expect(result.substring(16, 24), 'ABCDEFGH');
    });
  });

  // ---------------------------------------------------------------------------
  // transformFEN
  // ---------------------------------------------------------------------------
  group('transformFEN', () {
    test('identity should preserve FEN string', () {
      const String fen = 'O@O*****/********/********'
          ' w p p 3 6 3 6 0 0 0 0 0 0 0 0 1';
      final String result = transformFEN(fen, TransformationType.identity);

      // The board part should be preserved (first 26 chars)
      expect(result.substring(26), fen.substring(26));
    });

    test('should preserve the non-board part after transformation', () {
      const String fen = 'O@O*****/********/********'
          ' w m s 3 6 3 6 0 1 0 0 0 0 0 0 1';
      final String result = transformFEN(
        fen,
        TransformationType.rotate90,
      );

      // Non-board part (from position 26 onward) should be unchanged
      expect(result.substring(26), fen.substring(26));
    });

    test('transformFEN rotate90 x4 should return original', () {
      const String fen = 'O@O*****/********/********'
          ' w p p 3 6 3 6 0 0 0 0 0 0 0 0 1';
      String result = fen;
      for (int i = 0; i < 4; i++) {
        result = transformFEN(result, TransformationType.rotate90);
      }
      expect(result, fen);
    });

    test('transformFEN horizontalFlip x2 should return original', () {
      const String fen = 'O@O*****/********/********'
          ' w p p 3 6 3 6 0 0 0 0 0 0 0 0 1';
      String result = fen;
      result = transformFEN(result, TransformationType.mirrorHorizontal);
      result = transformFEN(result, TransformationType.mirrorHorizontal);
      expect(result, fen);
    });
  });

  // ---------------------------------------------------------------------------
  // transformMoveNotation
  // ---------------------------------------------------------------------------
  group('transformMoveNotation', () {
    test('identity should preserve move notations', () {
      expect(
        transformMoveNotation('d5', TransformationType.identity),
        'd5',
      );
      expect(
        transformMoveNotation('d5-e4', TransformationType.identity),
        'd5-e4',
      );
      expect(
        transformMoveNotation('xd5', TransformationType.identity),
        'xd5',
      );
    });

    test('rotate90 should transform place move correctly', () {
      // d5 is index 0, rotate90 maps 0 -> 2, index 2 is e4
      expect(
        transformMoveNotation('d5', TransformationType.rotate90),
        'e4',
      );
    });

    test('rotate90 should transform slide move correctly', () {
      // d5(0)->2(e4), e5(1)->3(e3)
      expect(
        transformMoveNotation('d5-e5', TransformationType.rotate90),
        'e4-e3',
      );
    });

    test('rotate90 should transform remove move correctly', () {
      // d5(0)->2(e4)
      expect(
        transformMoveNotation('xd5', TransformationType.rotate90),
        'xe4',
      );
    });

    test('swap should swap inner and outer ring squares', () {
      // d5 is inner ring index 0, swap maps 0 -> 16, index 16 is d7
      expect(
        transformMoveNotation('d5', TransformationType.swap),
        'd7',
      );
      // d7 is outer ring index 16, swap maps 16 -> 0, index 0 is d5
      expect(
        transformMoveNotation('d7', TransformationType.swap),
        'd5',
      );
      // d6 is middle ring index 8, swap maps 8 -> 8 (unchanged)
      expect(
        transformMoveNotation('d6', TransformationType.swap),
        'd6',
      );
    });

    test('special moves should be preserved', () {
      expect(
        transformMoveNotation('draw', TransformationType.rotate90),
        'draw',
      );
      expect(
        transformMoveNotation('(none)', TransformationType.rotate90),
        '(none)',
      );
      expect(
        transformMoveNotation('none', TransformationType.rotate90),
        'none',
      );
    });

    test('rotate90 applied 4 times should return original', () {
      const String move = 'a1-a4';
      String result = move;
      for (int i = 0; i < 4; i++) {
        result = transformMoveNotation(result, TransformationType.rotate90);
      }
      expect(result, move);
    });

    test('mirrorHorizontal applied twice should return original', () {
      const String move = 'xg7';
      String result = move;
      result = transformMoveNotation(
        result,
        TransformationType.mirrorHorizontal,
      );
      result = transformMoveNotation(
        result,
        TransformationType.mirrorHorizontal,
      );
      expect(result, move);
    });
  });

  // ---------------------------------------------------------------------------
  // composeTransformMaps and inverseTransformMap
  // ---------------------------------------------------------------------------
  group('composition and inverse', () {
    test('compose rotate90 twice should equal rotate180', () {
      final List<int> r90 = getTransformMap(TransformationType.rotate90);
      final List<int> r180 = getTransformMap(TransformationType.rotate180);
      expect(composeTransformMaps(r90, r90), r180);
    });

    test('compose rotate90 three times should equal rotate270', () {
      final List<int> r90 = getTransformMap(TransformationType.rotate90);
      final List<int> r180 = getTransformMap(TransformationType.rotate180);
      final List<int> r270 = getTransformMap(TransformationType.rotate270);
      expect(composeTransformMaps(r180, r90), r270);
    });

    test('compose rotate90 four times should equal identity', () {
      final List<int> r90 = getTransformMap(TransformationType.rotate90);
      final List<int> id = getTransformMap(TransformationType.identity);
      final List<int> r180 = composeTransformMaps(r90, r90);
      final List<int> r270 = composeTransformMaps(r180, r90);
      expect(composeTransformMaps(r270, r90), id);
    });

    test('inverse of each transform composes to identity', () {
      final List<int> id = getTransformMap(TransformationType.identity);
      for (final TransformationType t in TransformationType.values) {
        final List<int> map = getTransformMap(t);
        final List<int> inv = inverseTransformMap(map);
        expect(
          composeTransformMaps(map, inv),
          id,
          reason: 'compose($t, inverse($t)) should equal identity',
        );
      }
    });

    test('compose swap with rotate90 should equal swapRotate90', () {
      final List<int> swap = getTransformMap(TransformationType.swap);
      final List<int> r90 = getTransformMap(TransformationType.rotate90);
      final List<int> sr90 = getTransformMap(TransformationType.swapRotate90);
      // swapRotate90 = swap(rotate90(x)), so compose rotate90 first, then swap
      expect(composeTransformMaps(r90, swap), sr90);
    });
  });

  // ---------------------------------------------------------------------------
  // randomTransformationType
  // ---------------------------------------------------------------------------
  group('randomTransformationType', () {
    test('should return a valid TransformationType', () {
      for (int i = 0; i < 50; i++) {
        final TransformationType t = randomTransformationType();
        expect(TransformationType.values.contains(t), isTrue);
      }
    });

    test('excluding identity should never return identity', () {
      for (int i = 0; i < 100; i++) {
        final TransformationType t = randomTransformationType();
        expect(t, isNot(TransformationType.identity));
      }
    });

    test('including identity should sometimes return identity', () {
      // With 16 types, probability of never getting identity in 200
      // tries is (15/16)^200 ≈ 2.6e-6, so this should be reliable.
      bool gotIdentity = false;
      for (int i = 0; i < 200; i++) {
        if (randomTransformationType(excludeIdentity: false) ==
            TransformationType.identity) {
          gotIdentity = true;
          break;
        }
      }
      expect(gotIdentity, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // transformationMap
  // ---------------------------------------------------------------------------
  group('transformationMap', () {
    test('should have entries for all TransformationType values', () {
      for (final TransformationType t in TransformationType.values) {
        expect(
          transformationMap.containsKey(t),
          isTrue,
          reason: 'Missing mapping for $t',
        );
      }
    });

    test('all mappings should have exactly 24 entries', () {
      transformationMap.forEach(
        (TransformationType type, List<int> mapping) {
          expect(
            mapping.length,
            24,
            reason: 'Mapping for $type should have 24 entries',
          );
        },
      );
    });

    test('identity mapping should be 0..23', () {
      expect(
        transformationMap[TransformationType.identity],
        List<int>.generate(24, (int i) => i),
      );
    });

    test('all mappings should be permutations of 0..23', () {
      transformationMap.forEach(
        (TransformationType type, List<int> mapping) {
          final List<int> sorted = List<int>.from(mapping)..sort();
          expect(
            sorted,
            List<int>.generate(24, (int i) => i),
            reason: 'Mapping for $type should be a permutation',
          );
        },
      );
    });
  });
}
