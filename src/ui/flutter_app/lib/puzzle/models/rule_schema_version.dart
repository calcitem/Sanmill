// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// rule_schema_version.dart
//
// Versioned rule schema for backward compatibility

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../rule_settings/models/rule_settings.dart';

/// Rule schema version
///
/// Each version defines a fixed set of parameters used in hash calculation.
/// When new rule parameters are added, we increment the schema version.
/// This ensures existing puzzles remain compatible.
enum RuleSchemaVersion {
  /// Version 1: Initial release (2025-01)
  /// Includes: basic rule parameters
  v1,

  /// Version 2: Future expansion
  /// When new parameters are added, create v2 and define migration
  // v2,
}

/// Rule schema defines which parameters are included in hash calculation
class RuleSchema {
  const RuleSchema({required this.version, required this.parameters});

  /// Schema version
  final RuleSchemaVersion version;

  /// List of parameter names included in this version
  final List<String> parameters;

  /// Get schema for a specific version
  static RuleSchema forVersion(RuleSchemaVersion version) {
    switch (version) {
      case RuleSchemaVersion.v1:
        return _schemaV1;
    }
  }

  /// Get latest schema version
  static RuleSchema get latest => forVersion(RuleSchemaVersion.v1);

  /// Schema V1: Initial parameter set
  static const RuleSchema _schemaV1 = RuleSchema(
    version: RuleSchemaVersion.v1,
    parameters: <String>[
      // Core piece configuration
      'piecesCount',
      'flyPieceCount',
      'piecesAtLeastCount',

      // Board layout
      'hasDiagonalLines',

      // Placement phase rules
      'mayMoveInPlacingPhase',
      'isDefenderMoveFirst',

      // Mill and removal rules
      'mayRemoveMultiple',
      'mayRemoveFromMillsAlways',
      'millFormationActionInPlacingPhase',
      'restrictRepeatedMillsFormation',
      'oneTimeUseMill',

      // Game ending conditions
      'boardFullAction',
      'stalemateAction',

      // Flying rules
      'mayFly',

      // Draw rules
      'nMoveRule',
      'endgameNMoveRule',
      'threefoldRepetitionRule',

      // Capture mechanics - Custodian
      'enableCustodianCapture',
      'custodianCaptureOnSquareEdges',
      'custodianCaptureOnCrossLines',
      'custodianCaptureOnDiagonalLines',
      'custodianCaptureInPlacingPhase',
      'custodianCaptureInMovingPhase',
      'custodianCaptureOnlyWhenOwnPiecesLeq3',

      // Capture mechanics - Intervention
      'enableInterventionCapture',
      'interventionCaptureOnSquareEdges',
      'interventionCaptureOnCrossLines',
      'interventionCaptureOnDiagonalLines',
      'interventionCaptureInPlacingPhase',
      'interventionCaptureInMovingPhase',
      'interventionCaptureOnlyWhenOwnPiecesLeq3',

      // Capture mechanics - Leap
      'enableLeapCapture',
      'leapCaptureOnSquareEdges',
      'leapCaptureOnCrossLines',
      'leapCaptureOnDiagonalLines',
      'leapCaptureInPlacingPhase',
      'leapCaptureInMovingPhase',
      'leapCaptureOnlyWhenOwnPiecesLeq3',

      // Special rules
      'stopPlacingWhenTwoEmptySquares',
    ],
  );
}

/// Versioned rule hash calculator
///
/// Calculates rule hash based on a specific schema version.
/// This ensures hash stability when new parameters are added.
class VersionedRuleHashCalculator {
  const VersionedRuleHashCalculator();

  /// Calculate hash for a rule set using a specific schema version
  String calculateHash(
    RuleSettings settings, {
    RuleSchemaVersion version = RuleSchemaVersion.v1,
  }) {
    final RuleSchema schema = RuleSchema.forVersion(version);
    return _calculateHashWithSchema(settings, schema);
  }

  /// Calculate hash using latest schema version
  String calculateLatestHash(RuleSettings settings) {
    return calculateHash(settings);
  }

  /// Calculate hash with a specific schema
  String _calculateHashWithSchema(RuleSettings settings, RuleSchema schema) {
    // Extract only the parameters defined in this schema version
    final Map<String, dynamic> params = _extractParameters(settings, schema);

    // Add schema version to ensure different versions produce different hashes
    params['_schemaVersion'] = schema.version.index;

    // Convert to canonical JSON and calculate hash
    final String jsonString = _canonicalJson(params);
    final List<int> bytes = utf8.encode(jsonString);
    final Digest digest = md5.convert(bytes);

    return digest.toString();
  }

  /// Extract parameters from settings based on schema
  Map<String, dynamic> _extractParameters(
    RuleSettings settings,
    RuleSchema schema,
  ) {
    final Map<String, dynamic> params = <String, dynamic>{};

    for (final String paramName in schema.parameters) {
      final dynamic value = _getParameterValue(settings, paramName);
      if (value != null) {
        params[paramName] = value;
      }
    }

    return params;
  }

  /// Get parameter value from settings by name
  dynamic _getParameterValue(RuleSettings settings, String paramName) {
    switch (paramName) {
      // Core configuration
      case 'piecesCount':
        return settings.piecesCount;
      case 'flyPieceCount':
        return settings.flyPieceCount;
      case 'piecesAtLeastCount':
        return settings.piecesAtLeastCount;

      // Board layout
      case 'hasDiagonalLines':
        return settings.hasDiagonalLines;

      // Placement phase
      case 'mayMoveInPlacingPhase':
        return settings.mayMoveInPlacingPhase;
      case 'isDefenderMoveFirst':
        return settings.isDefenderMoveFirst;

      // Mill and removal
      case 'mayRemoveMultiple':
        return settings.mayRemoveMultiple;
      case 'mayRemoveFromMillsAlways':
        return settings.mayRemoveFromMillsAlways;
      case 'millFormationActionInPlacingPhase':
        return settings.millFormationActionInPlacingPhase?.index;
      case 'restrictRepeatedMillsFormation':
        return settings.restrictRepeatedMillsFormation;
      case 'oneTimeUseMill':
        return settings.oneTimeUseMill;

      // Game ending
      case 'boardFullAction':
        return settings.boardFullAction?.index;
      case 'stalemateAction':
        return settings.stalemateAction?.index;

      // Flying
      case 'mayFly':
        return settings.mayFly;

      // Draw rules
      case 'nMoveRule':
        return settings.nMoveRule;
      case 'endgameNMoveRule':
        return settings.endgameNMoveRule;
      case 'threefoldRepetitionRule':
        return settings.threefoldRepetitionRule;

      // Custodian capture
      case 'enableCustodianCapture':
        return settings.enableCustodianCapture;
      case 'custodianCaptureOnSquareEdges':
        return settings.custodianCaptureOnSquareEdges;
      case 'custodianCaptureOnCrossLines':
        return settings.custodianCaptureOnCrossLines;
      case 'custodianCaptureOnDiagonalLines':
        return settings.custodianCaptureOnDiagonalLines;
      case 'custodianCaptureInPlacingPhase':
        return settings.custodianCaptureInPlacingPhase;
      case 'custodianCaptureInMovingPhase':
        return settings.custodianCaptureInMovingPhase;
      case 'custodianCaptureOnlyWhenOwnPiecesLeq3':
        return settings.custodianCaptureOnlyWhenOwnPiecesLeq3;

      // Intervention capture
      case 'enableInterventionCapture':
        return settings.enableInterventionCapture;
      case 'interventionCaptureOnSquareEdges':
        return settings.interventionCaptureOnSquareEdges;
      case 'interventionCaptureOnCrossLines':
        return settings.interventionCaptureOnCrossLines;
      case 'interventionCaptureOnDiagonalLines':
        return settings.interventionCaptureOnDiagonalLines;
      case 'interventionCaptureInPlacingPhase':
        return settings.interventionCaptureInPlacingPhase;
      case 'interventionCaptureInMovingPhase':
        return settings.interventionCaptureInMovingPhase;
      case 'interventionCaptureOnlyWhenOwnPiecesLeq3':
        return settings.interventionCaptureOnlyWhenOwnPiecesLeq3;

      // Leap capture
      case 'enableLeapCapture':
        return settings.enableLeapCapture;
      case 'leapCaptureOnSquareEdges':
        return settings.leapCaptureOnSquareEdges;
      case 'leapCaptureOnCrossLines':
        return settings.leapCaptureOnCrossLines;
      case 'leapCaptureOnDiagonalLines':
        return settings.leapCaptureOnDiagonalLines;
      case 'leapCaptureInPlacingPhase':
        return settings.leapCaptureInPlacingPhase;
      case 'leapCaptureInMovingPhase':
        return settings.leapCaptureInMovingPhase;
      case 'leapCaptureOnlyWhenOwnPiecesLeq3':
        return settings.leapCaptureOnlyWhenOwnPiecesLeq3;

      // Special rules
      case 'stopPlacingWhenTwoEmptySquares':
        return settings.stopPlacingWhenTwoEmptySquares;

      default:
        return null;
    }
  }

  /// Convert to canonical JSON (sorted keys for consistency)
  String _canonicalJson(Map<String, dynamic> map) {
    final List<String> keys = map.keys.toList()..sort();
    final Map<String, dynamic> sorted = <String, dynamic>{};
    for (final String key in keys) {
      sorted[key] = map[key];
    }
    return jsonEncode(sorted);
  }
}

/// Rule migration manager
///
/// Handles automatic migration of puzzles when rule schema changes.
class RuleMigrationManager {
  const RuleMigrationManager();

  /// Migration map: old hash -> new hash
  /// When schema changes, populate this with migrations
  static const Map<String, String> _migrations = <String, String>{
    // Example: When we add new parameters in v2
    // 'old_hash_abc123': 'new_hash_def456',
  };

  /// Check if a hash needs migration
  bool needsMigration(String hash) {
    return _migrations.containsKey(hash);
  }

  /// Migrate a hash to its new value
  String? migrate(String oldHash) {
    return _migrations[oldHash];
  }

  /// Get all equivalent hashes (old + new) for a rule variant
  List<String> getEquivalentHashes(String currentHash) {
    final List<String> hashes = <String>[currentHash];

    // Check if this hash is a result of migration
    final String? originalHash = _migrations.entries
        .where((MapEntry<String, String> e) => e.value == currentHash)
        .map((MapEntry<String, String> e) => e.key)
        .firstOrNull;

    if (originalHash != null) {
      hashes.add(originalHash);
    }

    return hashes;
  }

  /// Migrate puzzle collection to new schema
  ///
  /// Call this when updating schema version to migrate all puzzles.
  /// Returns a map of old variant ID -> new variant ID
  Map<String, String> migrateAllVariants({
    required RuleSchemaVersion fromVersion,
    required RuleSchemaVersion toVersion,
  }) {
    final Map<String, String> migrations = <String, String>{};

    // TODO: Implement migration logic when moving to v2
    // For each known variant, calculate both old and new hashes
    // and add to migration map

    return migrations;
  }
}

/// Extension for convenient migration checking
extension RuleHashMigration on String {
  /// Check if this hash needs migration
  bool get needsMigration => const RuleMigrationManager().needsMigration(this);

  /// Migrate this hash if needed
  String get migratedHash => const RuleMigrationManager().migrate(this) ?? this;

  /// Get all equivalent hashes
  List<String> get equivalentHashes =>
      const RuleMigrationManager().getEquivalentHashes(this);
}
