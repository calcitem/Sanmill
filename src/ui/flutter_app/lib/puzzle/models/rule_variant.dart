// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// rule_variant.dart
//
// Rule variant identification and management for puzzles

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../rule_settings/models/rule_settings.dart';

/// Rule variant identifier for puzzles
///
/// Each variant represents a unique rule configuration that affects gameplay.
/// Puzzles are grouped by variants to ensure compatibility and fair comparison.
@HiveType(typeId: 35)
class RuleVariant {
  const RuleVariant({
    required this.id,
    required this.name,
    required this.description,
    required this.ruleHash,
  });

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

  /// Calculate a hash from rule settings
  ///
  /// This hash includes all gameplay-affecting parameters.
  /// Changes to cosmetic settings (like timeouts) don't affect the hash.
  static String _calculateRuleHash(RuleSettings settings) {
    // Create a map of critical rule parameters
    // These are the parameters that fundamentally affect puzzle solving
    final Map<String, dynamic> criticalParams = <String, dynamic>{
      'piecesCount': settings.piecesCount,
      'flyPieceCount': settings.flyPieceCount,
      'piecesAtLeastCount': settings.piecesAtLeastCount,
      'hasDiagonalLines': settings.hasDiagonalLines,
      'mayMoveInPlacingPhase': settings.mayMoveInPlacingPhase,
      'isDefenderMoveFirst': settings.isDefenderMoveFirst,
      'mayRemoveMultiple': settings.mayRemoveMultiple,
      'mayRemoveFromMillsAlways': settings.mayRemoveFromMillsAlways,
      'boardFullAction': settings.boardFullAction?.index,
      'stalemateAction': settings.stalemateAction?.index,
      'mayFly': settings.mayFly,
      'nMoveRule': settings.nMoveRule,
      'endgameNMoveRule': settings.endgameNMoveRule,
      'threefoldRepetitionRule': settings.threefoldRepetitionRule,
      'millFormationActionInPlacingPhase':
          settings.millFormationActionInPlacingPhase?.index,
      'restrictRepeatedMillsFormation': settings.restrictRepeatedMillsFormation,
      'oneTimeUseMill': settings.oneTimeUseMill,
      'enableCustodianCapture': settings.enableCustodianCapture,
      'custodianCaptureOnSquareEdges': settings.custodianCaptureOnSquareEdges,
      'custodianCaptureOnCrossLines': settings.custodianCaptureOnCrossLines,
      'custodianCaptureOnDiagonalLines':
          settings.custodianCaptureOnDiagonalLines,
      'custodianCaptureInPlacingPhase': settings.custodianCaptureInPlacingPhase,
      'custodianCaptureInMovingPhase': settings.custodianCaptureInMovingPhase,
      'custodianCaptureOnlyWhenOwnPiecesLeq3':
          settings.custodianCaptureOnlyWhenOwnPiecesLeq3,
      'enableInterventionCapture': settings.enableInterventionCapture,
      'interventionCaptureOnSquareEdges':
          settings.interventionCaptureOnSquareEdges,
      'interventionCaptureOnCrossLines':
          settings.interventionCaptureOnCrossLines,
      'interventionCaptureOnDiagonalLines':
          settings.interventionCaptureOnDiagonalLines,
      'interventionCaptureInPlacingPhase':
          settings.interventionCaptureInPlacingPhase,
      'interventionCaptureInMovingPhase':
          settings.interventionCaptureInMovingPhase,
      'interventionCaptureOnlyWhenOwnPiecesLeq3':
          settings.interventionCaptureOnlyWhenOwnPiecesLeq3,
      'enableLeapCapture': settings.enableLeapCapture,
      'leapCaptureOnSquareEdges': settings.leapCaptureOnSquareEdges,
      'leapCaptureOnCrossLines': settings.leapCaptureOnCrossLines,
      'leapCaptureOnDiagonalLines': settings.leapCaptureOnDiagonalLines,
      'leapCaptureInPlacingPhase': settings.leapCaptureInPlacingPhase,
      'leapCaptureInMovingPhase': settings.leapCaptureInMovingPhase,
      'leapCaptureOnlyWhenOwnPiecesLeq3':
          settings.leapCaptureOnlyWhenOwnPiecesLeq3,
      'stopPlacingWhenTwoEmptySquares': settings.stopPlacingWhenTwoEmptySquares,
    };

    // Convert to JSON and calculate MD5 hash
    final String jsonString = jsonEncode(criticalParams);
    final List<int> bytes = utf8.encode(jsonString);
    final Digest digest = md5.convert(bytes);

    return digest.toString();
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
      return 'Nine Men\'s Morris';
    } else if (settings.isLikelyTwelveMensMorris()) {
      return 'Twelve Men\'s Morris';
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
  /// Standard Nine Men's Morris
  static RuleVariant get nineMensMorris => RuleVariant.fromRuleSettings(
        const RuleSettings(),
      );

  /// Twelve Men's Morris
  static RuleVariant get twelveMensMorris => RuleVariant.fromRuleSettings(
        const TwelveMensMorrisRuleSettings(),
      );

  /// Russian Mill (One-time Mill)
  static RuleVariant get russianMill => RuleVariant.fromRuleSettings(
        const OneTimeMillRuleSettings(),
      );

  /// Morabaraba
  static RuleVariant get morabaraba => RuleVariant.fromRuleSettings(
        const MorabarabaRuleSettings(),
      );

  /// Cham Gonu
  static RuleVariant get chamGonu => RuleVariant.fromRuleSettings(
        const ChamGonuRuleSettings(),
      );

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
