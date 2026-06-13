// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// rule_variant_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/puzzle/models/rule_variant.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';

void main() {
  // ---------------------------------------------------------------------------
  // RuleVariant.fromRuleSettings
  // ---------------------------------------------------------------------------
  group('RuleVariant.fromRuleSettings', () {
    test("should identify standard Nine Men's Morris", () {
      final RuleVariant variant = RuleVariant.fromRuleSettings(
        const RuleSettings(),
      );

      expect(variant.id, 'standard_9mm');
      expect(variant.name, "Nine Men's Morris");
      expect(variant.ruleHash, isNotEmpty);
    });

    test("should identify Twelve Men's Morris", () {
      final RuleVariant variant = RuleVariant.fromRuleSettings(
        const TwelveMensMorrisRuleSettings(),
      );

      expect(variant.id, 'twelve_mens_morris');
      expect(variant.name, "Twelve Men's Morris");
    });

    test('should generate description with features', () {
      final RuleVariant variant = RuleVariant.fromRuleSettings(
        const RuleSettings(),
      );

      expect(variant.description, contains('9 pieces'));
    });

    test('should include diagonal lines in description when enabled', () {
      final RuleVariant variant = RuleVariant.fromRuleSettings(
        const TwelveMensMorrisRuleSettings(),
      );

      expect(variant.description, contains('diagonal'));
    });

    test('should include custodian capture in description', () {
      final RuleVariant variant = RuleVariant.fromRuleSettings(
        const RuleSettings(enableCustodianCapture: true),
      );

      expect(variant.description, contains('custodian'));
    });

    test('should include intervention capture in description', () {
      final RuleVariant variant = RuleVariant.fromRuleSettings(
        const MulMulanRuleSettings(),
      );

      expect(variant.description, contains('intervention'));
    });

    test('should generate custom variant ID for non-standard rules', () {
      final RuleVariant variant = RuleVariant.fromRuleSettings(
        const RuleSettings(piecesCount: 7, hasDiagonalLines: true),
      );

      expect(variant.id, contains('custom_'));
      expect(variant.id, contains('7p'));
      expect(variant.id, contains('diag'));
    });

    // -----------------------------------------------------------------------
    // Exhaustive detection for every named RuleSettings subclass.
    // Each test verifies that _generateVariantId returns the expected ID and
    // that the display name is populated from the lookup table.
    // -----------------------------------------------------------------------

    test('should identify Morabaraba', () {
      final RuleVariant v = RuleVariant.fromRuleSettings(
        const MorabarabaRuleSettings(),
      );
      expect(v.id, 'morabaraba');
      expect(v.name, 'Morabaraba');
    });

    test('should identify Dooz', () {
      final RuleVariant v = RuleVariant.fromRuleSettings(
        const DoozRuleSettings(),
      );
      expect(v.id, 'dooz');
      expect(v.name, 'Dooz');
    });

    test('should identify Lasker Morris', () {
      final RuleVariant v = RuleVariant.fromRuleSettings(
        const LaskerMorrisSettings(),
      );
      expect(v.id, 'lasker_morris');
      expect(v.name, 'Lasker Morris');
    });

    test('should identify Russian Mill (One-Time Mill)', () {
      final RuleVariant v = RuleVariant.fromRuleSettings(
        const OneTimeMillRuleSettings(),
      );
      expect(v.id, 'russian_mill');
      expect(v.name, 'Russian Mill');
    });

    test('should identify Cham Gonu', () {
      final RuleVariant v = RuleVariant.fromRuleSettings(
        const ChamGonuRuleSettings(),
      );
      expect(v.id, 'cham_gonu');
      expect(v.name, 'Cham Gonu');
    });

    test('should identify Zhi Qi', () {
      final RuleVariant v = RuleVariant.fromRuleSettings(
        const ZhiQiRuleSettings(),
      );
      expect(v.id, 'zhi_qi');
      expect(v.name, 'Zhi Qi');
    });

    test('should identify Cheng San Qi', () {
      final RuleVariant v = RuleVariant.fromRuleSettings(
        const ChengSanQiRuleSettings(),
      );
      expect(v.id, 'cheng_san_qi');
      expect(v.name, 'Cheng San Qi');
    });

    test('should identify Da San Qi', () {
      final RuleVariant v = RuleVariant.fromRuleSettings(
        const DaSanQiRuleSettings(),
      );
      expect(v.id, 'da_san_qi');
      expect(v.name, 'Da San Qi');
    });

    test('should identify Mul-Mulan', () {
      final RuleVariant v = RuleVariant.fromRuleSettings(
        const MulMulanRuleSettings(),
      );
      expect(v.id, 'mul_mulan');
      expect(v.name, 'Mul-Mulan');
    });

    test('should identify Nerenchi', () {
      final RuleVariant v = RuleVariant.fromRuleSettings(
        const NerenchiRuleSettings(),
      );
      expect(v.id, 'nerenchi');
      expect(v.name, 'Nerenchi');
    });

    test('should identify El Filja', () {
      final RuleVariant v = RuleVariant.fromRuleSettings(
        const ELFiljaRuleSettings(),
      );
      expect(v.id, 'el_filja');
      expect(v.name, 'El Filja');
    });
  });

  // ---------------------------------------------------------------------------
  // Canonical settings round-trip
  // ---------------------------------------------------------------------------
  group('RuleVariant.canonicalSettings', () {
    test('every canonical entry should round-trip through detection', () {
      // Ensures that for every (id, settings) pair registered in the
      // canonical map, _generateVariantId(settings) returns the same id.
      for (final MapEntry<String, RuleSettings> entry
          in RuleVariant.canonicalSettings.entries) {
        final RuleVariant v = RuleVariant.fromRuleSettings(entry.value);
        expect(
          v.id,
          entry.key,
          reason:
              'Detection of canonical settings for "${entry.key}" '
              'produced "${v.id}" instead',
        );
      }
    });

    test('every canonical entry should have a display name', () {
      for (final String id in RuleVariant.canonicalSettings.keys) {
        final RuleVariant? v = PredefinedVariants.getById(id);
        expect(v, isNotNull, reason: 'No PredefinedVariant for "$id"');
        expect(
          v!.name,
          isNot(contains('Piece Variant')),
          reason: '"$id" should have a named display name, not fallback',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // RuleVariant equality
  // ---------------------------------------------------------------------------
  group('RuleVariant equality', () {
    test('same rules should produce equal variants', () {
      final RuleVariant v1 = RuleVariant.fromRuleSettings(const RuleSettings());
      final RuleVariant v2 = RuleVariant.fromRuleSettings(const RuleSettings());

      expect(v1, equals(v2));
      expect(v1.hashCode, v2.hashCode);
    });

    test('different rules should produce different variants', () {
      final RuleVariant v1 = RuleVariant.fromRuleSettings(const RuleSettings());
      final RuleVariant v2 = RuleVariant.fromRuleSettings(
        const TwelveMensMorrisRuleSettings(),
      );

      expect(v1, isNot(equals(v2)));
    });
  });

  // ---------------------------------------------------------------------------
  // PredefinedVariants
  // ---------------------------------------------------------------------------
  group('PredefinedVariants', () {
    test('should have all predefined variants', () {
      // One entry per named variant in RuleVariant.canonicalSettings.
      expect(
        PredefinedVariants.all.length,
        RuleVariant.canonicalSettings.length,
      );
    });

    test('nineMensMorris should have correct ID', () {
      expect(PredefinedVariants.nineMensMorris.id, 'standard_9mm');
    });

    test('twelveMensMorris should have correct ID', () {
      expect(PredefinedVariants.twelveMensMorris.id, 'twelve_mens_morris');
    });

    test('getById should return correct variant', () {
      final RuleVariant? variant = PredefinedVariants.getById('standard_9mm');
      expect(variant, isNotNull);
      expect(variant!.name, contains('Nine'));
    });

    test('getById should return null for unknown ID', () {
      final RuleVariant? variant = PredefinedVariants.getById('nonexistent');
      expect(variant, isNull);
    });

    test('all predefined variants should have unique IDs', () {
      final Set<String> ids = PredefinedVariants.all
          .map((RuleVariant v) => v.id)
          .toSet();
      expect(ids.length, PredefinedVariants.all.length);
    });

    test('all predefined variants should have non-empty descriptions', () {
      for (final RuleVariant v in PredefinedVariants.all) {
        expect(v.description, isNotEmpty, reason: 'Description for ${v.id}');
      }
    });

    test('all predefined variants should have non-empty hashes', () {
      for (final RuleVariant v in PredefinedVariants.all) {
        expect(v.ruleHash, isNotEmpty, reason: 'Hash for ${v.id}');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // toString
  // ---------------------------------------------------------------------------
  group('RuleVariant.toString', () {
    test('should include id and name', () {
      final RuleVariant variant = RuleVariant.fromRuleSettings(
        const RuleSettings(),
      );

      expect(variant.toString(), contains('standard_9mm'));
      expect(variant.toString(), contains("Nine Men's Morris"));
    });
  });
}
