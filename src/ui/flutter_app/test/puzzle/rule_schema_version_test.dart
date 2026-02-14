// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// rule_schema_version_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/puzzle/models/rule_schema_version.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';

void main() {
  // ---------------------------------------------------------------------------
  // RuleSchemaVersion enum
  // ---------------------------------------------------------------------------
  group('RuleSchemaVersion', () {
    test('should have at least one version', () {
      expect(RuleSchemaVersion.values, isNotEmpty);
      expect(RuleSchemaVersion.values, contains(RuleSchemaVersion.v1));
    });
  });

  // ---------------------------------------------------------------------------
  // RuleSchema
  // ---------------------------------------------------------------------------
  group('RuleSchema', () {
    test('forVersion(v1) should return schema with parameters', () {
      final RuleSchema schema = RuleSchema.forVersion(RuleSchemaVersion.v1);

      expect(schema.version, RuleSchemaVersion.v1);
      expect(schema.parameters, isNotEmpty);
    });

    test('latest should return v1 schema', () {
      final RuleSchema latest = RuleSchema.latest;

      expect(latest.version, RuleSchemaVersion.v1);
    });

    test('v1 schema should include core parameters', () {
      final RuleSchema schema = RuleSchema.forVersion(RuleSchemaVersion.v1);

      expect(schema.parameters, contains('piecesCount'));
      expect(schema.parameters, contains('hasDiagonalLines'));
      expect(schema.parameters, contains('mayFly'));
      expect(schema.parameters, contains('nMoveRule'));
      expect(schema.parameters, contains('enableCustodianCapture'));
      expect(schema.parameters, contains('enableInterventionCapture'));
      expect(schema.parameters, contains('enableLeapCapture'));
    });

    test('v1 schema should include all capture mechanic parameters', () {
      final RuleSchema schema = RuleSchema.forVersion(RuleSchemaVersion.v1);

      // Custodian capture parameters
      expect(schema.parameters, contains('custodianCaptureOnSquareEdges'));
      expect(schema.parameters, contains('custodianCaptureOnCrossLines'));
      expect(schema.parameters, contains('custodianCaptureInPlacingPhase'));
      expect(schema.parameters, contains('custodianCaptureInMovingPhase'));

      // Intervention capture parameters
      expect(schema.parameters, contains('interventionCaptureOnSquareEdges'));
      expect(schema.parameters, contains('interventionCaptureInPlacingPhase'));

      // Leap capture parameters
      expect(schema.parameters, contains('leapCaptureOnSquareEdges'));
      expect(schema.parameters, contains('leapCaptureInPlacingPhase'));
    });
  });

  // ---------------------------------------------------------------------------
  // VersionedRuleHashCalculator
  // ---------------------------------------------------------------------------
  group('VersionedRuleHashCalculator', () {
    const VersionedRuleHashCalculator calculator =
        VersionedRuleHashCalculator();

    test('should produce non-empty hash', () {
      final String hash = calculator.calculateLatestHash(const RuleSettings());

      expect(hash, isNotEmpty);
    });

    test('same settings should produce same hash', () {
      final String hash1 = calculator.calculateLatestHash(const RuleSettings());
      final String hash2 = calculator.calculateLatestHash(const RuleSettings());

      expect(hash1, hash2);
    });

    test('different settings should produce different hashes', () {
      final String hash1 = calculator.calculateLatestHash(
        const RuleSettings(piecesCount: 9),
      );
      final String hash2 = calculator.calculateLatestHash(
        const RuleSettings(piecesCount: 12),
      );

      expect(hash1, isNot(hash2));
    });

    test('diagonal lines difference should produce different hashes', () {
      final String hash1 = calculator.calculateLatestHash(
        const RuleSettings(hasDiagonalLines: false),
      );
      final String hash2 = calculator.calculateLatestHash(
        const RuleSettings(hasDiagonalLines: true),
      );

      expect(hash1, isNot(hash2));
    });

    test('hash should be a valid MD5 hex string (32 chars)', () {
      final String hash = calculator.calculateLatestHash(const RuleSettings());

      // MD5 produces 32 hex characters
      expect(hash.length, 32);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(hash), isTrue);
    });

    test('all named rule variants produce unique hashes', () {
      final Set<String> hashes = <String>{};
      final List<RuleSettings> variants = <RuleSettings>[
        const RuleSettings(), // Nine Men's Morris
        const TwelveMensMorrisRuleSettings(),
        const MorabarabaRuleSettings(),
        const DoozRuleSettings(),
        const LaskerMorrisSettings(),
        const OneTimeMillRuleSettings(),
        const ChamGonuRuleSettings(),
        const ZhiQiRuleSettings(),
        const ChengSanQiRuleSettings(),
        const DaSanQiRuleSettings(),
        const MulMulanRuleSettings(),
        const NerenchiRuleSettings(),
        const ELFiljaRuleSettings(),
      ];

      for (final RuleSettings v in variants) {
        final String hash = calculator.calculateLatestHash(v);
        expect(
          hashes.add(hash),
          isTrue,
          reason:
              'Duplicate hash found for variant with '
              '${v.piecesCount} pieces',
        );
      }
    });

    test('explicit version should produce same hash as latest', () {
      final String hashLatest = calculator.calculateLatestHash(
        const RuleSettings(),
      );
      final String hashV1 = calculator.calculateHash(
        const RuleSettings(),
        version: RuleSchemaVersion.v1,
      );

      expect(hashLatest, hashV1);
    });
  });

  // ---------------------------------------------------------------------------
  // RuleMigrationManager
  // ---------------------------------------------------------------------------
  group('RuleMigrationManager', () {
    const RuleMigrationManager manager = RuleMigrationManager();

    test('should not need migration for fresh hashes', () {
      const VersionedRuleHashCalculator calculator =
          VersionedRuleHashCalculator();
      final String hash = calculator.calculateLatestHash(const RuleSettings());

      expect(manager.needsMigration(hash), isFalse);
    });

    test('migrate should return null for unknown hashes', () {
      expect(manager.migrate('unknown_hash'), isNull);
    });

    test('getEquivalentHashes should include the hash itself', () {
      final List<String> equivalents = manager.getEquivalentHashes('some_hash');

      expect(equivalents, contains('some_hash'));
    });
  });

  // ---------------------------------------------------------------------------
  // RuleHashMigration extension
  // ---------------------------------------------------------------------------
  group('RuleHashMigration extension', () {
    test('needsMigration should return false for fresh hashes', () {
      expect('fresh_hash'.needsMigration, isFalse);
    });

    test('migratedHash should return self when no migration needed', () {
      expect('fresh_hash'.migratedHash, 'fresh_hash');
    });

    test('equivalentHashes should include self', () {
      expect('fresh_hash'.equivalentHashes, contains('fresh_hash'));
    });
  });
}
