// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';

void main() {
  group('PuzzlePackMetadata', () {
    group('constructor and basic properties', () {
      test('creates with required fields only', () {
        const PuzzlePackMetadata metadata = PuzzlePackMetadata(
          id: 'pack_001',
          name: 'Test Pack',
          description: 'A test puzzle pack',
        );

        expect(metadata.id, equals('pack_001'));
        expect(metadata.name, equals('Test Pack'));
        expect(metadata.description, equals('A test puzzle pack'));
        expect(metadata.author, isNull);
        expect(metadata.version, isNull);
        expect(metadata.createdDate, isNull);
        expect(metadata.updatedDate, isNull);
        expect(metadata.tags, isEmpty);
        expect(metadata.isOfficial, isFalse);
        expect(metadata.requiredAppVersion, isNull);
        expect(metadata.ruleVariantId, equals('standard_9mm'));
        expect(metadata.coverImage, isNull);
        expect(metadata.website, isNull);
      });

      test('creates with all fields specified', () {
        final DateTime created = DateTime(2025);
        final DateTime updated = DateTime(2026, 1, 15);

        final PuzzlePackMetadata metadata = PuzzlePackMetadata(
          id: 'pack_002',
          name: 'Advanced Tactics',
          description: 'Advanced puzzle collection',
          author: 'John Doe',
          version: '1.2.3',
          createdDate: created,
          updatedDate: updated,
          tags: const <String>['advanced', 'tactics'],
          isOfficial: true,
          requiredAppVersion: '7.1.0',
          ruleVariantId: 'twelve_mens_morris',
          coverImage: 'path/to/cover.png',
          website: 'https://example.com',
        );

        expect(metadata.id, equals('pack_002'));
        expect(metadata.name, equals('Advanced Tactics'));
        expect(metadata.description, equals('Advanced puzzle collection'));
        expect(metadata.author, equals('John Doe'));
        expect(metadata.version, equals('1.2.3'));
        expect(metadata.createdDate, equals(created));
        expect(metadata.updatedDate, equals(updated));
        expect(metadata.tags, containsAll(<String>['advanced', 'tactics']));
        expect(metadata.isOfficial, isTrue);
        expect(metadata.requiredAppVersion, equals('7.1.0'));
        expect(metadata.ruleVariantId, equals('twelve_mens_morris'));
        expect(metadata.coverImage, equals('path/to/cover.png'));
        expect(metadata.website, equals('https://example.com'));
      });
    });

    group('copyWith', () {
      test('creates copy with updated fields', () {
        const PuzzlePackMetadata original = PuzzlePackMetadata(
          id: 'pack_003',
          name: 'Original Name',
          description: 'Original description',
        );

        final PuzzlePackMetadata updated = original.copyWith(
          name: 'Updated Name',
          version: '2.0.0',
          isOfficial: true,
        );

        expect(updated.id, equals('pack_003'));
        expect(updated.name, equals('Updated Name'));
        expect(updated.description, equals('Original description'));
        expect(updated.version, equals('2.0.0'));
        expect(updated.isOfficial, isTrue);
      });

      test('preserves original values when not specified', () {
        final DateTime created = DateTime(2025, 6);

        final PuzzlePackMetadata original = PuzzlePackMetadata(
          id: 'pack_004',
          name: 'Stable Pack',
          description: 'Stable description',
          author: 'Jane Smith',
          createdDate: created,
          tags: const <String>['stable', 'tested'],
        );

        final PuzzlePackMetadata updated = original.copyWith(version: '1.0.1');

        expect(updated.id, equals('pack_004'));
        expect(updated.name, equals('Stable Pack'));
        expect(updated.description, equals('Stable description'));
        expect(updated.author, equals('Jane Smith'));
        expect(updated.createdDate, equals(created));
        expect(updated.tags, containsAll(<String>['stable', 'tested']));
        expect(updated.version, equals('1.0.1'));
      });

      test('can update dates independently', () {
        final DateTime originalCreated = DateTime(2025);
        final DateTime originalUpdated = DateTime(2025, 6);
        final DateTime newUpdated = DateTime(2026, 1, 15);

        final PuzzlePackMetadata original = PuzzlePackMetadata(
          id: 'pack_005',
          name: 'Date Test Pack',
          description: 'Testing date updates',
          createdDate: originalCreated,
          updatedDate: originalUpdated,
        );

        final PuzzlePackMetadata updated = original.copyWith(
          updatedDate: newUpdated,
        );

        expect(updated.createdDate, equals(originalCreated));
        expect(updated.updatedDate, equals(newUpdated));
      });
    });

    group('JSON serialization', () {
      test('toJson serializes all fields correctly', () {
        final DateTime created = DateTime.utc(2025, 1, 1, 12);
        final DateTime updated = DateTime.utc(2026, 1, 15, 10, 30);

        final PuzzlePackMetadata metadata = PuzzlePackMetadata(
          id: 'pack_006',
          name: 'Complete Pack',
          description: 'Pack with all fields',
          author: 'Alice Wonder',
          version: '3.0.0',
          createdDate: created,
          updatedDate: updated,
          tags: const <String>['complete', 'full'],
          isOfficial: true,
          requiredAppVersion: '7.2.0',
          ruleVariantId: 'russian_mill',
          coverImage: 'assets/cover.png',
          website: 'https://puzzles.example.com',
        );

        final Map<String, dynamic> json = metadata.toJson();

        expect(json['id'], equals('pack_006'));
        expect(json['name'], equals('Complete Pack'));
        expect(json['description'], equals('Pack with all fields'));
        expect(json['author'], equals('Alice Wonder'));
        expect(json['version'], equals('3.0.0'));
        expect(json['createdDate'], equals(created.toIso8601String()));
        expect(json['updatedDate'], equals(updated.toIso8601String()));
        expect(json['tags'], containsAll(<String>['complete', 'full']));
        expect(json['isOfficial'], isTrue);
        expect(json['requiredAppVersion'], equals('7.2.0'));
        expect(json['ruleVariantId'], equals('russian_mill'));
        expect(json['coverImage'], equals('assets/cover.png'));
        expect(json['website'], equals('https://puzzles.example.com'));
      });

      test('toJson omits null optional fields', () {
        const PuzzlePackMetadata metadata = PuzzlePackMetadata(
          id: 'pack_007',
          name: 'Minimal Pack',
          description: 'Pack with minimal fields',
        );

        final Map<String, dynamic> json = metadata.toJson();

        expect(json.containsKey('id'), isTrue);
        expect(json.containsKey('name'), isTrue);
        expect(json.containsKey('description'), isTrue);
        expect(json.containsKey('isOfficial'), isTrue);
        expect(json.containsKey('ruleVariantId'), isTrue);

        expect(json.containsKey('author'), isFalse);
        expect(json.containsKey('version'), isFalse);
        expect(json.containsKey('createdDate'), isFalse);
        expect(json.containsKey('updatedDate'), isFalse);
        expect(json.containsKey('coverImage'), isFalse);
        expect(json.containsKey('website'), isFalse);
      });

      test('toJson includes empty tags array conditionally', () {
        const PuzzlePackMetadata metadataEmpty = PuzzlePackMetadata(
          id: 'pack_008a',
          name: 'No Tags',
          description: 'Pack without tags',
        );

        final Map<String, dynamic> jsonEmpty = metadataEmpty.toJson();
        expect(jsonEmpty.containsKey('tags'), isFalse);

        const PuzzlePackMetadata metadataWithTags = PuzzlePackMetadata(
          id: 'pack_008b',
          name: 'With Tags',
          description: 'Pack with tags',
          tags: <String>['tag1'],
        );

        final Map<String, dynamic> jsonWithTags = metadataWithTags.toJson();
        expect(jsonWithTags.containsKey('tags'), isTrue);
      });

      test('fromJson deserializes all fields correctly', () {
        final Map<String, dynamic> json = <String, dynamic>{
          'id': 'pack_009',
          'name': 'Imported Pack',
          'description': 'Pack from JSON',
          'author': 'Bob Builder',
          'version': '4.5.6',
          'createdDate': '2025-03-15T08:30:00.000Z',
          'updatedDate': '2026-01-10T14:45:00.000Z',
          'tags': <String>['imported', 'json'],
          'isOfficial': true,
          'requiredAppVersion': '7.3.0',
          'ruleVariantId': 'lasker_morris',
          'coverImage': 'http://example.com/cover.jpg',
          'website': 'https://pack.example.org',
        };

        final PuzzlePackMetadata metadata = PuzzlePackMetadata.fromJson(json);

        expect(metadata.id, equals('pack_009'));
        expect(metadata.name, equals('Imported Pack'));
        expect(metadata.description, equals('Pack from JSON'));
        expect(metadata.author, equals('Bob Builder'));
        expect(metadata.version, equals('4.5.6'));
        expect(metadata.createdDate, isNotNull);
        expect(metadata.updatedDate, isNotNull);
        expect(metadata.tags, containsAll(<String>['imported', 'json']));
        expect(metadata.isOfficial, isTrue);
        expect(metadata.requiredAppVersion, equals('7.3.0'));
        expect(metadata.ruleVariantId, equals('lasker_morris'));
        expect(metadata.coverImage, equals('http://example.com/cover.jpg'));
        expect(metadata.website, equals('https://pack.example.org'));
      });

      test('fromJson handles missing optional fields', () {
        final Map<String, dynamic> json = <String, dynamic>{
          'id': 'pack_010',
          'name': 'Minimal JSON Pack',
          'description': 'Pack with minimal JSON',
        };

        final PuzzlePackMetadata metadata = PuzzlePackMetadata.fromJson(json);

        expect(metadata.id, equals('pack_010'));
        expect(metadata.name, equals('Minimal JSON Pack'));
        expect(metadata.description, equals('Pack with minimal JSON'));
        expect(metadata.author, isNull);
        expect(metadata.version, isNull);
        expect(metadata.createdDate, isNull);
        expect(metadata.updatedDate, isNull);
        expect(metadata.tags, isEmpty);
        expect(metadata.isOfficial, isFalse);
        expect(metadata.requiredAppVersion, isNull);
        expect(metadata.ruleVariantId, equals('standard_9mm'));
        expect(metadata.coverImage, isNull);
        expect(metadata.website, isNull);
      });

      test('fromJson defaults isOfficial to false', () {
        final Map<String, dynamic> json = <String, dynamic>{
          'id': 'pack_011',
          'name': 'Unofficial Pack',
          'description': 'Community pack',
        };

        final PuzzlePackMetadata metadata = PuzzlePackMetadata.fromJson(json);

        expect(metadata.isOfficial, isFalse);
      });

      test('fromJson defaults ruleVariantId to standard_9mm', () {
        final Map<String, dynamic> json = <String, dynamic>{
          'id': 'pack_012',
          'name': 'Standard Pack',
          'description': 'Uses default rules',
        };

        final PuzzlePackMetadata metadata = PuzzlePackMetadata.fromJson(json);

        expect(metadata.ruleVariantId, equals('standard_9mm'));
      });

      test('round-trip serialization preserves all data', () {
        final DateTime created = DateTime.utc(2025, 7, 4, 10);
        final DateTime updated = DateTime.utc(2026);

        final PuzzlePackMetadata original = PuzzlePackMetadata(
          id: 'pack_013',
          name: 'Round Trip Pack',
          description: 'Testing round-trip serialization',
          author: 'Charlie Brown',
          version: '5.0.0',
          createdDate: created,
          updatedDate: updated,
          tags: const <String>['roundtrip', 'test', 'serialization'],
          requiredAppVersion: '7.0.5',
          ruleVariantId: 'custom_variant',
          coverImage: 'data/covers/roundtrip.png',
          website: 'https://roundtrip.test',
        );

        final Map<String, dynamic> json = original.toJson();
        final PuzzlePackMetadata deserialized = PuzzlePackMetadata.fromJson(
          json,
        );

        expect(deserialized.id, equals(original.id));
        expect(deserialized.name, equals(original.name));
        expect(deserialized.description, equals(original.description));
        expect(deserialized.author, equals(original.author));
        expect(deserialized.version, equals(original.version));
        expect(deserialized.createdDate, equals(original.createdDate));
        expect(deserialized.updatedDate, equals(original.updatedDate));
        expect(deserialized.tags, equals(original.tags));
        expect(deserialized.isOfficial, equals(original.isOfficial));
        expect(
          deserialized.requiredAppVersion,
          equals(original.requiredAppVersion),
        );
        expect(deserialized.ruleVariantId, equals(original.ruleVariantId));
        expect(deserialized.coverImage, equals(original.coverImage));
        expect(deserialized.website, equals(original.website));
      });
    });

    group('toString', () {
      test('returns formatted string with version', () {
        const PuzzlePackMetadata metadata = PuzzlePackMetadata(
          id: 'pack_014',
          name: 'Display Pack',
          description: 'Testing toString',
          version: '1.0.0',
        );

        final String str = metadata.toString();

        expect(str, contains('Display Pack'));
        expect(str, contains('1.0.0'));
      });

      test('handles null version', () {
        const PuzzlePackMetadata metadata = PuzzlePackMetadata(
          id: 'pack_015',
          name: 'No Version Pack',
          description: 'No version specified',
        );

        final String str = metadata.toString();

        expect(str, contains('No Version Pack'));
        expect(str, contains('null'));
      });
    });

    group('edge cases', () {
      test('handles very long names and descriptions', () {
        final String longName = 'A' * 500;
        final String longDescription = 'B' * 2000;

        final PuzzlePackMetadata metadata = PuzzlePackMetadata(
          id: 'pack_016',
          name: longName,
          description: longDescription,
        );

        expect(metadata.name, equals(longName));
        expect(metadata.description, equals(longDescription));

        final Map<String, dynamic> json = metadata.toJson();
        final PuzzlePackMetadata deserialized = PuzzlePackMetadata.fromJson(
          json,
        );

        expect(deserialized.name, equals(longName));
        expect(deserialized.description, equals(longDescription));
      });

      test('handles special characters in strings', () {
        const PuzzlePackMetadata metadata = PuzzlePackMetadata(
          id: 'pack_017',
          name: 'Pack with 特殊字符 and émojis 🎯',
          description: 'Description with "quotes" and \'apostrophes\'',
          author: 'Author <email@example.com>',
        );

        final Map<String, dynamic> json = metadata.toJson();
        final PuzzlePackMetadata deserialized = PuzzlePackMetadata.fromJson(
          json,
        );

        expect(deserialized.name, equals(metadata.name));
        expect(deserialized.description, equals(metadata.description));
        expect(deserialized.author, equals(metadata.author));
      });

      test('handles empty strings', () {
        const PuzzlePackMetadata metadata = PuzzlePackMetadata(
          id: '',
          name: '',
          description: '',
          author: '',
          version: '',
        );

        expect(metadata.id, isEmpty);
        expect(metadata.name, isEmpty);
        expect(metadata.description, isEmpty);
        expect(metadata.author, isEmpty);
        expect(metadata.version, isEmpty);
      });

      test('handles large number of tags', () {
        final List<String> manyTags = List<String>.generate(
          100,
          (int i) => 'tag$i',
        );

        final PuzzlePackMetadata metadata = PuzzlePackMetadata(
          id: 'pack_018',
          name: 'Many Tags Pack',
          description: 'Pack with many tags',
          tags: manyTags,
        );

        expect(metadata.tags.length, equals(100));

        final Map<String, dynamic> json = metadata.toJson();
        final PuzzlePackMetadata deserialized = PuzzlePackMetadata.fromJson(
          json,
        );

        expect(deserialized.tags.length, equals(100));
        expect(deserialized.tags, equals(manyTags));
      });

      test('handles URL edge cases', () {
        const PuzzlePackMetadata metadata = PuzzlePackMetadata(
          id: 'pack_019',
          name: 'URL Test Pack',
          description: 'Testing various URL formats',
          website:
              'http://localhost:8080/path/to/resource?param=value&foo=bar#anchor',
          coverImage: 'file:///absolute/path/to/image.png',
        );

        final Map<String, dynamic> json = metadata.toJson();
        final PuzzlePackMetadata deserialized = PuzzlePackMetadata.fromJson(
          json,
        );

        expect(deserialized.website, equals(metadata.website));
        expect(deserialized.coverImage, equals(metadata.coverImage));
      });
    });
  });
}
