// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// rule_variant.dart
//
// Rule variant identification and management for puzzles

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:meta/meta.dart';

import '../../rule_settings/models/rule_settings.dart';
import 'rule_schema_version.dart';

part 'rule_variant.g.dart';

/// Rule variant identifier for puzzles
///
/// Each variant represents a unique rule configuration that affects gameplay.
/// Puzzles are grouped by variants to ensure compatibility and fair comparison.
@immutable
@HiveType(typeId: 35)
class RuleVariant {
  const RuleVariant({
    required this.id,
    required this.name,
    required this.description,
    required this.ruleHash,
  });

  /// Create a RuleVariant from RuleSettings
  factory RuleVariant.fromRuleSettings(RuleSettings settings) {
    final String hash = _calculateRuleHash(settings);
    final String id = _generateVariantId(settings);
    final String name = _generateVariantName(settings);
    final String description = _generateVariantDescription(settings);

    return RuleVariant(
      id: id,
      name: name,
      description: description,
      ruleHash: hash,
    );
  }

  /// Unique identifier for this variant (e.g., "standard_9mm", "twelve_mens_morris")
  @HiveField(0)
  final String id;

  /// Display name of the variant
  @HiveField(1)
  final String name;

  /// Description of this variant
  @HiveField(2)
  final String description;

  /// Hash of the rule settings for quick comparison
  /// This is calculated from the critical rule parameters
  @HiveField(3)
  final String ruleHash;

  /// Calculate a hash from rule settings using versioned schema
  ///
  /// This hash is calculated using a versioned schema to ensure stability.
  /// When new rule parameters are added, the schema version is incremented
  /// and old hashes can be automatically migrated to new ones.
  ///
  /// This prevents puzzle loss when upgrading the app with new rule features.
  static String _calculateRuleHash(RuleSettings settings) {
    const VersionedRuleHashCalculator calculator =
        VersionedRuleHashCalculator();

    // Use latest schema version for new puzzles
    // Old puzzles will be automatically migrated via RuleMigrationManager
    return calculator.calculateLatestHash(settings);
  }

  /// Generate a human-readable variant ID
  static String _generateVariantId(RuleSettings settings) {
    // Detect common variants
    if (settings.isLikelyNineMensMorris()) {
      return 'standard_9mm';
    } else if (settings.isLikelyTwelveMensMorris()) {
      return 'twelve_mens_morris';
    } else if (settings.piecesCount == 12 &&
        !settings.hasDiagonalLines &&
        settings.oneTimeUseMill) {
      return 'russian_mill';
    } else if (settings.piecesCount == 12 &&
        settings.hasDiagonalLines &&
        settings.enableCustodianCapture) {
      return 'cham_gonu';
    } else if (settings.piecesCount == 12 && !settings.hasDiagonalLines) {
      return 'morabaraba';
    }

    // For custom variants, use a descriptive name
    return 'custom_${settings.piecesCount}p_${settings.hasDiagonalLines ? 'diag' : 'nodiag'}';
  }

  /// Generate a display name for the variant
  static String _generateVariantName(RuleSettings settings) {
    if (settings.isLikelyNineMensMorris()) {
      return "Nine Men's Morris";
    } else if (settings.isLikelyTwelveMensMorris()) {
      return "Twelve Men's Morris";
    } else if (settings.piecesCount == 12 &&
        !settings.hasDiagonalLines &&
        settings.oneTimeUseMill) {
      return 'Russian Mill';
    } else if (settings.piecesCount == 12 &&
        settings.hasDiagonalLines &&
        settings.enableCustodianCapture) {
      return 'Cham Gonu';
    } else if (settings.piecesCount == 12 && !settings.hasDiagonalLines) {
      return 'Morabaraba';
    }

    return '${settings.piecesCount}-Piece Variant';
  }

  /// Generate a description for the variant
  static String _generateVariantDescription(RuleSettings settings) {
    final List<String> features = <String>[];

    features.add('${settings.piecesCount} pieces per player');

    if (settings.hasDiagonalLines) {
      features.add('diagonal lines');
    }

    if (settings.mayFly && settings.flyPieceCount < settings.piecesCount) {
      features.add('flying at ${settings.flyPieceCount} pieces');
    }

    if (settings.oneTimeUseMill) {
      features.add('one-time mill');
    }

    if (settings.enableCustodianCapture) {
      features.add('custodian capture');
    }

    if (settings.enableInterventionCapture) {
      features.add('intervention capture');
    }

    if (settings.enableLeapCapture) {
      features.add('leap capture');
    }

    return features.join(', ');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuleVariant &&
          runtimeType == other.runtimeType &&
          ruleHash == other.ruleHash;

  @override
  int get hashCode => ruleHash.hashCode;

  @override
  String toString() => 'RuleVariant($id: $name)';
}

/// Predefined rule variants
class PredefinedVariants {
  const PredefinedVariants._();
  /// Standard Nine Men's Morris
  static RuleVariant get nineMensMorris =>
      RuleVariant.fromRuleSettings(const RuleSettings());

  /// Twelve Men's Morris
  static RuleVariant get twelveMensMorris =>
      RuleVariant.fromRuleSettings(const TwelveMensMorrisRuleSettings());

  /// Russian Mill (One-time Mill)
  static RuleVariant get russianMill =>
      RuleVariant.fromRuleSettings(const OneTimeMillRuleSettings());

  /// Morabaraba
  static RuleVariant get morabaraba =>
      RuleVariant.fromRuleSettings(const MorabarabaRuleSettings());

  /// Cham Gonu
  static RuleVariant get chamGonu =>
      RuleVariant.fromRuleSettings(const ChamGonuRuleSettings());

  /// Get all predefined variants
  static List<RuleVariant> get all => <RuleVariant>[
    nineMensMorris,
    twelveMensMorris,
    russianMill,
    morabaraba,
    chamGonu,
  ];

  /// Get variant by ID
  static RuleVariant? getById(String id) {
    try {
      return all.firstWhere((RuleVariant v) => v.id == id);
    } catch (e) {
      return null;
    }
  }
}
