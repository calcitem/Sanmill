// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_pack_metadata_json_test.dart
//
// Additional tests for PuzzlePackMetadata JSON serialization and copyWith.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    "com.calcitem.sanmill/engine",
  );

  setUp(() {
    DB.instance = MockDB();
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
  // PuzzlePackMetadata constructor
  // ---------------------------------------------------------------------------
  group('PuzzlePackMetadata construction', () {
    test('should store required fields', () {
      const PuzzlePackMetadata meta = PuzzlePackMetadata(
        id: 'pack-1',
        name: 'Beginner Pack',
        description: 'Easy puzzles for beginners',
      );

      expect(meta.id, 'pack-1');
      expect(meta.name, 'Beginner Pack');
      expect(meta.description, 'Easy puzzles for beginners');
    });

    test('should have correct defaults for optional fields', () {
      const PuzzlePackMetadata meta = PuzzlePackMetadata(
        id: 'pack-1',
        name: 'Test',
        description: 'Test pack',
      );

      expect(meta.author, isNull);
      expect(meta.version, isNull);
      expect(meta.createdDate, isNull);
      expect(meta.updatedDate, isNull);
      expect(meta.tags, isEmpty);
      expect(meta.isOfficial, isFalse);
      expect(meta.requiredAppVersion, isNull);
      expect(meta.ruleVariantId, 'standard_9mm');
      expect(meta.coverImage, isNull);
      expect(meta.website, isNull);
    });

    test('should accept all optional fields', () {
      final DateTime now = DateTime(2026, 2, 14);
      final PuzzlePackMetadata meta = PuzzlePackMetadata(
        id: 'pack-2',
        name: 'Advanced Pack',
        description: 'Hard puzzles',
        author: 'Sanmill Team',
        version: '1.2.0',
        createdDate: now,
        updatedDate: now,
        tags: const <String>['tactics', 'advanced'],
        isOfficial: true,
        requiredAppVersion: '7.1.0',
        ruleVariantId: 'twelve_mens_morris',
        coverImage: 'cover.png',
        website: 'https://example.com',
      );

      expect(meta.author, 'Sanmill Team');
      expect(meta.version, '1.2.0');
      expect(meta.isOfficial, isTrue);
      expect(meta.tags, <String>['tactics', 'advanced']);
      expect(meta.ruleVariantId, 'twelve_mens_morris');
    });
  });

  // ---------------------------------------------------------------------------
  // toJson / fromJson
  // ---------------------------------------------------------------------------
  group('PuzzlePackMetadata JSON', () {
    test('toJson should include required fields', () {
      const PuzzlePackMetadata meta = PuzzlePackMetadata(
        id: 'pack-1',
        name: 'Test Pack',
        description: 'A test puzzle pack',
      );

      final Map<String, dynamic> json = meta.toJson();

      expect(json['id'], 'pack-1');
      expect(json['name'], 'Test Pack');
      expect(json['description'], 'A test puzzle pack');
      expect(json['isOfficial'], isFalse);
      expect(json['ruleVariantId'], 'standard_9mm');
    });

    test('toJson should omit null optional fields', () {
      const PuzzlePackMetadata meta = PuzzlePackMetadata(
        id: 'pack-1',
        name: 'Test',
        description: 'Desc',
      );

      final Map<String, dynamic> json = meta.toJson();

      expect(json.containsKey('author'), isFalse);
      expect(json.containsKey('version'), isFalse);
      expect(json.containsKey('createdDate'), isFalse);
      expect(json.containsKey('coverImage'), isFalse);
    });

    test('toJson should include non-null optional fields', () {
      final PuzzlePackMetadata meta = PuzzlePackMetadata(
        id: 'pack-1',
        name: 'Test',
        description: 'Desc',
        author: 'Author',
        version: '1.0',
        createdDate: DateTime(2026),
        tags: const <String>['tag1'],
      );

      final Map<String, dynamic> json = meta.toJson();

      expect(json['author'], 'Author');
      expect(json['version'], '1.0');
      expect(json.containsKey('createdDate'), isTrue);
      expect(json['tags'], <String>['tag1']);
    });

    test('fromJson should parse required fields', () {
      final PuzzlePackMetadata meta = PuzzlePackMetadata.fromJson(
        <String, dynamic>{
          'id': 'pack-99',
          'name': 'From JSON',
          'description': 'Parsed from JSON',
        },
      );

      expect(meta.id, 'pack-99');
      expect(meta.name, 'From JSON');
      expect(meta.description, 'Parsed from JSON');
    });

    test('fromJson should use defaults for missing optional fields', () {
      final PuzzlePackMetadata meta = PuzzlePackMetadata.fromJson(
        <String, dynamic>{
          'id': 'pack-1',
          'name': 'Test',
          'description': 'Desc',
        },
      );

      expect(meta.isOfficial, isFalse);
      expect(meta.ruleVariantId, 'standard_9mm');
      expect(meta.tags, isEmpty);
    });

    test('fromJson should parse all fields', () {
      final PuzzlePackMetadata meta = PuzzlePackMetadata.fromJson(
        <String, dynamic>{
          'id': 'pack-full',
          'name': 'Full Pack',
          'description': 'All fields',
          'author': 'Author',
          'version': '2.0',
          'createdDate': '2026-01-01T00:00:00.000',
          'updatedDate': '2026-02-01T00:00:00.000',
          'tags': <String>['a', 'b'],
          'isOfficial': true,
          'requiredAppVersion': '7.2.0',
          'ruleVariantId': 'morabaraba',
          'coverImage': 'img.png',
          'website': 'https://example.com',
        },
      );

      expect(meta.author, 'Author');
      expect(meta.version, '2.0');
      expect(meta.createdDate, isNotNull);
      expect(meta.updatedDate, isNotNull);
      expect(meta.tags, <String>['a', 'b']);
      expect(meta.isOfficial, isTrue);
      expect(meta.requiredAppVersion, '7.2.0');
      expect(meta.ruleVariantId, 'morabaraba');
    });

    test('toJson/fromJson round-trip', () {
      final DateTime now = DateTime(2026, 2, 14);
      final PuzzlePackMetadata original = PuzzlePackMetadata(
        id: 'round-trip',
        name: 'Round Trip',
        description: 'Test round-trip',
        author: 'Tester',
        version: '1.0.0',
        createdDate: now,
        tags: const <String>['test'],
        isOfficial: true,
      );

      final Map<String, dynamic> json = original.toJson();
      final PuzzlePackMetadata restored = PuzzlePackMetadata.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.description, original.description);
      expect(restored.author, original.author);
      expect(restored.version, original.version);
      expect(restored.isOfficial, original.isOfficial);
      expect(restored.tags, original.tags);
    });
  });

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------
  group('PuzzlePackMetadata.copyWith', () {
    test('should copy with no changes when no arguments', () {
      const PuzzlePackMetadata original = PuzzlePackMetadata(
        id: 'pack-1',
        name: 'Original',
        description: 'Original desc',
        isOfficial: true,
      );
      final PuzzlePackMetadata copy = original.copyWith();

      expect(copy.id, original.id);
      expect(copy.name, original.name);
      expect(copy.isOfficial, original.isOfficial);
    });

    test('should override specified fields', () {
      const PuzzlePackMetadata original = PuzzlePackMetadata(
        id: 'pack-1',
        name: 'Original',
        description: 'Original desc',
      );
      final PuzzlePackMetadata updated = original.copyWith(
        name: 'Updated',
        author: 'New Author',
      );

      expect(updated.name, 'Updated');
      expect(updated.author, 'New Author');
      expect(updated.id, 'pack-1'); // Unchanged
      expect(updated.description, 'Original desc'); // Unchanged
    });
  });

  // ---------------------------------------------------------------------------
  // toString
  // ---------------------------------------------------------------------------
  group('PuzzlePackMetadata.toString', () {
    test('should contain name and version', () {
      const PuzzlePackMetadata meta = PuzzlePackMetadata(
        id: 'pack-1',
        name: 'Test Pack',
        description: 'Desc',
        version: '1.0',
      );

      expect(meta.toString(), contains('Test Pack'));
      expect(meta.toString(), contains('1.0'));
    });
  });
}
