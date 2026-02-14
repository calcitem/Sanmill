// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

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

  // ---------------------------------------------------------------------------
  // Canonical variant ID <-> RuleSettings mappings
  // ---------------------------------------------------------------------------

  /// Display names for all known variant IDs.
  ///
  /// When a new named rule variant is added to `RuleSettings`, add an entry
  /// here, in [canonicalSettings], and in [_generateVariantId].
  static const Map<String, String> _variantNames = <String, String>{
    'standard_9mm': "Nine Men's Morris",
    'twelve_mens_morris': "Twelve Men's Morris",
    'morabaraba': 'Morabaraba',
    'dooz': 'Dooz',
    'lasker_morris': 'Lasker Morris',
    'russian_mill': 'Russian Mill',
    'cham_gonu': 'Cham Gonu',
    'zhi_qi': 'Zhi Qi',
    'cheng_san_qi': 'Cheng San Qi',
    'da_san_qi': 'Da San Qi',
    'mul_mulan': 'Mul-Mulan',
    'nerenchi': 'Nerenchi',
    'el_filja': 'El Filja',
  };

  /// Canonical [RuleSettings] for every known variant ID.
  ///
  /// Used to apply the correct rules when entering puzzle mode.
  /// When a new named variant is added, register it here so that puzzles
  /// using that variant can be played with the correct engine configuration.
  static const Map<String, RuleSettings> canonicalSettings =
      <String, RuleSettings>{
        'standard_9mm': NineMensMorrisRuleSettings(),
        'twelve_mens_morris': TwelveMensMorrisRuleSettings(),
        'morabaraba': MorabarabaRuleSettings(),
        'dooz': DoozRuleSettings(),
        'lasker_morris': LaskerMorrisSettings(),
        'russian_mill': OneTimeMillRuleSettings(),
        'cham_gonu': ChamGonuRuleSettings(),
        'zhi_qi': ZhiQiRuleSettings(),
        'cheng_san_qi': ChengSanQiRuleSettings(),
        'da_san_qi': DaSanQiRuleSettings(),
        'mul_mulan': MulMulanRuleSettings(),
        'nerenchi': NerenchiRuleSettings(),
        'el_filja': ELFiljaRuleSettings(),
      };

  // ---------------------------------------------------------------------------
  // Variant detection
  // ---------------------------------------------------------------------------

  /// Generate a human-readable variant ID from [RuleSettings].
  ///
  /// Detection is ordered from most-specific to least-specific so that
  /// variants sharing common traits (e.g. 12 pieces + diagonal lines) are
  /// disambiguated correctly.
  ///
  /// **Forward-compatibility:** Each check tests only the *distinguishing*
  /// features of a variant rather than every parameter, so newly added rule
  /// parameters with sensible defaults will not break existing detection.
  /// When a new named variant is introduced, add a targeted check here
  /// *before* the generic fallback.
  static String _generateVariantId(RuleSettings settings) {
    final MillFormationActionInPlacingPhase? mfa =
        settings.millFormationActionInPlacingPhase;

    // -- Variants with globally unique mill-formation actions --------------

    // El Filja: the only variant using removalBasedOnMillCounts.
    if (mfa == MillFormationActionInPlacingPhase.removalBasedOnMillCounts) {
      return 'el_filja';
    }

    // Dooz: the only variant using removeOpponentsPieceFromHandThenOpponentsTurn.
    if (mfa ==
        MillFormationActionInPlacingPhase
            .removeOpponentsPieceFromHandThenOpponentsTurn) {
      return 'dooz';
    }

    // -- Variants with unique boolean flags --------------------------------

    // Russian Mill (One-Time Mill): only variant with oneTimeUseMill.
    if (settings.oneTimeUseMill) {
      return 'russian_mill';
    }

    // Lasker Morris: only variant with 10 pieces + placing-phase moves.
    if (settings.piecesCount == 10 && settings.mayMoveInPlacingPhase) {
      return 'lasker_morris';
    }

    // Mul-Mulan: 9 pieces + intervention capture.
    if (settings.enableInterventionCapture && settings.piecesCount == 9) {
      return 'mul_mulan';
    }

    // -- Mark-and-delay family (several variants share this action) ---------

    if (mfa == MillFormationActionInPlacingPhase.markAndDelayRemovingPieces) {
      // Cheng San Qi: 9-piece mark-and-delay variant.
      if (settings.piecesCount == 9) {
        return 'cheng_san_qi';
      }

      // Da San Qi: 12 pieces, defender moves first, may remove multiple.
      if (settings.isDefenderMoveFirst && settings.mayRemoveMultiple) {
        return 'da_san_qi';
      }

      // Zhi Qi: 12 pieces, both sides remove when board full.
      if (settings.boardFullAction ==
          BoardFullAction.firstAndSecondPlayerRemovePiece) {
        return 'zhi_qi';
      }

      // Cham Gonu: remaining 12-piece mark-and-delay variant.
      return 'cham_gonu';
    }

    // -- Standard mill-action variants (removeOpponentsPieceFromBoard) ------

    if (settings.piecesCount == 12 && settings.hasDiagonalLines) {
      // Nerenchi: defender moves first.
      if (settings.isDefenderMoveFirst) {
        return 'nerenchi';
      }

      // Morabaraba: draw on board full or restricted repeated mills.
      if (settings.boardFullAction == BoardFullAction.agreeToDraw ||
          settings.restrictRepeatedMillsFormation) {
        return 'morabaraba';
      }
    }

    // -- Broad category matches --------------------------------------------

    if (settings.isLikelyTwelveMensMorris()) {
      return 'twelve_mens_morris';
    }

    if (settings.isLikelyNineMensMorris()) {
      return 'standard_9mm';
    }

    // Fallback for user-customised rule sets.
    return 'custom_${settings.piecesCount}p'
        '_${settings.hasDiagonalLines ? 'diag' : 'nodiag'}';
  }

  /// Generate a display name for the variant.
  ///
  /// Looks up [_variantNames] by the detected variant ID, falling back to
  /// a generic piece-count description for custom variants.
  static String _generateVariantName(RuleSettings settings) {
    final String id = _generateVariantId(settings);
    return _variantNames[id] ?? '${settings.piecesCount}-Piece Variant';
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

/// Predefined rule variants.
///
/// When a new named variant is added to [RuleSettings], add a corresponding
/// getter here so that puzzles referencing the variant can be recognised by
/// [PuzzleCollectionManager] and other consumers.
class PredefinedVariants {
  const PredefinedVariants._();

  /// Standard Nine Men's Morris
  static RuleVariant get nineMensMorris =>
      RuleVariant.fromRuleSettings(const NineMensMorrisRuleSettings());

  /// Twelve Men's Morris
  static RuleVariant get twelveMensMorris =>
      RuleVariant.fromRuleSettings(const TwelveMensMorrisRuleSettings());

  /// Morabaraba
  static RuleVariant get morabaraba =>
      RuleVariant.fromRuleSettings(const MorabarabaRuleSettings());

  /// Dooz
  static RuleVariant get dooz =>
      RuleVariant.fromRuleSettings(const DoozRuleSettings());

  /// Lasker Morris
  static RuleVariant get laskerMorris =>
      RuleVariant.fromRuleSettings(const LaskerMorrisSettings());

  /// Russian Mill (One-time Mill)
  static RuleVariant get russianMill =>
      RuleVariant.fromRuleSettings(const OneTimeMillRuleSettings());

  /// Cham Gonu
  static RuleVariant get chamGonu =>
      RuleVariant.fromRuleSettings(const ChamGonuRuleSettings());

  /// Zhi Qi
  static RuleVariant get zhiQi =>
      RuleVariant.fromRuleSettings(const ZhiQiRuleSettings());

  /// Cheng San Qi
  static RuleVariant get chengSanQi =>
      RuleVariant.fromRuleSettings(const ChengSanQiRuleSettings());

  /// Da San Qi
  static RuleVariant get daSanQi =>
      RuleVariant.fromRuleSettings(const DaSanQiRuleSettings());

  /// Mul-Mulan
  static RuleVariant get mulMulan =>
      RuleVariant.fromRuleSettings(const MulMulanRuleSettings());

  /// Nerenchi
  static RuleVariant get nerenchi =>
      RuleVariant.fromRuleSettings(const NerenchiRuleSettings());

  /// El Filja
  static RuleVariant get elFilja =>
      RuleVariant.fromRuleSettings(const ELFiljaRuleSettings());

  /// All predefined variants.
  ///
  /// Lazily constructed from [RuleVariant.canonicalSettings] so that adding
  /// a new entry in one place automatically updates this list.
  static List<RuleVariant> get all => RuleVariant.canonicalSettings.entries
      .map(
        (MapEntry<String, RuleSettings> e) =>
            RuleVariant.fromRuleSettings(e.value),
      )
      .toList();

  /// Look up a predefined variant by its string [id].
  ///
  /// Returns `null` when the ID does not match any known variant, which
  /// allows callers to gracefully handle custom/unknown variants.
  static RuleVariant? getById(String id) {
    final RuleSettings? settings = RuleVariant.canonicalSettings[id];
    if (settings == null) {
      return null;
    }
    return RuleVariant.fromRuleSettings(settings);
  }
}
