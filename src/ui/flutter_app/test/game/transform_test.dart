// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// transform_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/game_page/services/mill.dart';
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
        result = transformString(result, TransformationType.rotate90Degrees);
      }
      expect(result, sample);
    });

    test('horizontalFlip applied twice should return original', () {
      String result = sample;
      result = transformString(result, TransformationType.horizontalFlip);
      result = transformString(result, TransformationType.horizontalFlip);
      expect(result, sample);
    });

    test('verticalFlip applied twice should return original', () {
      String result = sample;
      result = transformString(result, TransformationType.verticalFlip);
      result = transformString(result, TransformationType.verticalFlip);
      expect(result, sample);
    });

    test('innerOuterFlip applied twice should return original', () {
      String result = sample;
      result = transformString(result, TransformationType.innerOuterFlip);
      result = transformString(result, TransformationType.innerOuterFlip);
      expect(result, sample);
    });

    test('should reject strings not exactly 24 characters', () {
      expect(
        () => transformString('short', TransformationType.identity),
        throwsArgumentError,
      );
      expect(
        () => transformString(
          'this is way too long for a board string!!',
          TransformationType.identity,
        ),
        throwsArgumentError,
      );
      expect(
        () => transformString('', TransformationType.identity),
        throwsArgumentError,
      );
    });

    test('rotate90 should shift inner ring positions by 2', () {
      // Inner ring: positions 0-7
      // After rotate90, position i goes to position (i+2)%8
      // So 'A' (pos 0) goes to pos 2, 'B' (pos 1) goes to pos 3, etc.
      final String result = transformString(
        sample,
        TransformationType.rotate90Degrees,
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
        TransformationType.innerOuterFlip,
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
        TransformationType.rotate90Degrees,
      );

      // Non-board part (from position 26 onward) should be unchanged
      expect(result.substring(26), fen.substring(26));
    });

    test('transformFEN rotate90 x4 should return original', () {
      const String fen = 'O@O*****/********/********'
          ' w p p 3 6 3 6 0 0 0 0 0 0 0 0 1';
      String result = fen;
      for (int i = 0; i < 4; i++) {
        result = transformFEN(result, TransformationType.rotate90Degrees);
      }
      expect(result, fen);
    });

    test('transformFEN horizontalFlip x2 should return original', () {
      const String fen = 'O@O*****/********/********'
          ' w p p 3 6 3 6 0 0 0 0 0 0 0 0 1';
      String result = fen;
      result = transformFEN(result, TransformationType.horizontalFlip);
      result = transformFEN(result, TransformationType.horizontalFlip);
      expect(result, fen);
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
