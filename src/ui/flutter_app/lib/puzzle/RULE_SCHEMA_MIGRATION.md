# Rule Schema Migration Guide

## Overview

This guide explains how to add new rule parameters without breaking existing puzzles. The system uses **versioned rule schemas** to ensure hash stability and **automatic migration** to preserve puzzle compatibility during upgrades.

## Problem

When new rule parameters are added to `RuleSettings`, the hash calculation changes, causing:
- ❌ Old puzzles become orphaned (can't find matching rule variant)
- ❌ User's custom puzzle collections are lost
- ❌ Downloaded puzzles no longer work

## Solution

Our system uses **three-layer protection**:

1. **Versioned Schema**: Each version defines a fixed parameter set
2. **Stable Hashing**: Same parameters always produce same hash
3. **Auto-Migration**: Old hashes automatically map to new hashes

## Architecture

### 1. Rule Schema Versions

Located in `rule_schema_version.dart`:

```dart
enum RuleSchemaVersion {
  v1,  // Initial release (2025-01)
  v2,  // Future: when new parameters added
  // ...
}
```

Each version defines exactly which parameters are included in hash calculation.

### 2. Hash Calculation

```dart
// Old way (DEPRECATED - hash changes when new params added)
String calculateHash(RuleSettings settings) {
  return md5(allParameters);  // ❌ Breaks on parameter addition
}

// New way (STABLE - hash locked to schema version)
String calculateHash(RuleSettings settings) {
  final calculator = VersionedRuleHashCalculator();
  return calculator.calculateLatestHash(settings);  // ✅ Stable
}
```

### 3. Automatic Migration

When a user upgrades the app:

```dart
// User has old puzzles with v1 hash: "abc123..."
// App now uses v2 with new parameters

// Migration manager automatically maps:
oldHash "abc123..." -> newHash "def456..."

// Puzzles are still accessible!
```

## How to Add New Rule Parameters

Follow these steps when adding new gameplay-affecting parameters:

### Step 1: Add Parameter to RuleSettings

```dart
// In rule_settings.dart
class RuleSettings {
  // ... existing parameters

  // NEW: Add your parameter
  @HiveField(42)  // Use next available field number
  final bool myNewParameter;
}
```

### Step 2: Create New Schema Version

```dart
// In rule_schema_version.dart

enum RuleSchemaVersion {
  v1,
  v2,  // ← Add new version
}

// Add v2 schema definition
class RuleSchema {
  static const RuleSchema _schemaV2 = RuleSchema(
    version: RuleSchemaVersion.v2,
    parameters: [
      // Copy all v1 parameters
      'piecesCount',
      'flyPieceCount',
      // ... all v1 params

      // Add new parameter
      'myNewParameter',  // ← NEW
    ],
  );

  static RuleSchema forVersion(RuleSchemaVersion version) {
    switch (version) {
      case RuleSchemaVersion.v1:
        return _schemaV1;
      case RuleSchemaVersion.v2:  // ← NEW
        return _schemaV2;
    }
  }

  static RuleSchema get latest => forVersion(RuleSchemaVersion.v2);  // ← Update
}
```

### Step 3: Add Parameter Getter

```dart
// In rule_schema_version.dart

dynamic _getParameterValue(RuleSettings settings, String paramName) {
  switch (paramName) {
    // ... existing cases

    case 'myNewParameter':  // ← NEW
      return settings.myNewParameter;

    default:
      return null;
  }
}
```

### Step 4: Calculate Migration Mappings

Run this migration script to generate hash mappings:

```dart
void generateMigrationMappings() {
  final calculator = VersionedRuleHashCalculator();

  // For each known variant, calculate both v1 and v2 hashes
  final knownVariants = [
    RuleSettings(),  // Standard 9MM
    TwelveMensMorrisRuleSettings(),
    OneTimeMillRuleSettings(),
    // ... etc
  ];

  final migrations = <String, String>{};

  for (final variant in knownVariants) {
    final v1Hash = calculator.calculateHash(variant, version: RuleSchemaVersion.v1);
    final v2Hash = calculator.calculateHash(variant, version: RuleSchemaVersion.v2);

    migrations[v1Hash] = v2Hash;

    print('Migrating: $v1Hash -> $v2Hash');
  }

  // Output migrations map
  print('\nAdd to RuleMigrationManager._migrations:');
  print(migrations);
}
```

### Step 5: Add Migrations to Migration Manager

```dart
// In rule_schema_version.dart

class RuleMigrationManager {
  static const Map<String, String> _migrations = {
    // v1 -> v2 migrations
    'abc123...': 'def456...',  // Standard 9MM
    'xyz789...': 'uvw012...',  // 12MM
    // ... add all generated mappings
  };
}
```

### Step 6: Test Migration

```dart
void testMigration() {
  final manager = RuleMigrationManager();

  // Test old hash
  final oldHash = 'abc123...';
  assert(manager.needsMigration(oldHash));

  // Test migration
  final newHash = manager.migrate(oldHash);
  assert(newHash == 'def456...');

  print('✓ Migration test passed');
}
```

## Decision Tree: Should Parameter Affect Hash?

When adding a new parameter, decide if it should affect the hash:

```
Is this parameter gameplay-affecting?
├─ YES: Affects puzzle solving logic
│  ├─ Examples: piece counts, board layout, capture rules
│  ├─ Action: Add to schema version
│  └─ Result: New hash, migration needed
│
└─ NO: Only affects UI/cosmetics
   ├─ Examples: timeouts, colors, animations
   ├─ Action: Don't add to schema
   └─ Result: Hash unchanged, no migration
```

### Gameplay-Affecting Parameters (Include in Schema)

- ✅ Piece counts
- ✅ Board layout (diagonal lines)
- ✅ Movement rules
- ✅ Capture mechanics
- ✅ Mill formation rules
- ✅ Win/draw conditions

### Non-Gameplay Parameters (Exclude from Schema)

- ❌ Move timeouts
- ❌ UI colors/themes
- ❌ Animation speeds
- ❌ Sound effects
- ❌ Display preferences

## Migration Timeline

### Version 1 (Current - 2025-01)

- Initial parameter set
- Includes all existing gameplay rules
- Hash: Calculated from v1 schema

### Version 2 (Future)

**Trigger**: When first new gameplay parameter is added

**Migration Steps**:
1. Create v2 schema with new parameter
2. Calculate v1→v2 hash mappings
3. Add mappings to `RuleMigrationManager`
4. Update `latest` schema to v2
5. Test with existing puzzles

**User Impact**:
- ✅ Seamless: Users see no difference
- ✅ Puzzles preserved: All old puzzles still work
- ✅ No manual action required

## Testing Migration

### Unit Tests

```dart
void testSchemaStability() {
  final settings = RuleSettings();
  final calculator = VersionedRuleHashCalculator();

  // v1 hash should never change
  final v1Hash = calculator.calculateHash(settings, version: RuleSchemaVersion.v1);
  assert(v1Hash == 'expected_v1_hash');

  // v2 hash should be deterministic
  final v2Hash = calculator.calculateHash(settings, version: RuleSchemaVersion.v2);
  assert(v2Hash == 'expected_v2_hash');
}
```

### Integration Tests

```dart
void testPuzzleMigration() {
  // Create puzzle with v1 hash
  final puzzle = PuzzleInfo(
    ruleVariantId: 'v1_hash_abc123',
    // ... other fields
  );

  // Load with collection manager
  final manager = PuzzleCollectionManager([puzzle]);

  // Puzzle should be accessible via migrated hash
  final collection = manager.getCollection('v2_hash_def456');
  assert(collection != null);
  assert(collection.puzzles.contains(puzzle));
}
```

## Best Practices

### DO ✅

1. **Always use versioned calculator**
   ```dart
   final calculator = VersionedRuleHashCalculator();
   final hash = calculator.calculateLatestHash(settings);
   ```

2. **Test migration before release**
   - Generate all hash mappings
   - Test with real puzzle database
   - Verify no puzzles are orphaned

3. **Document parameter additions**
   - Add to changelog
   - Update schema version enum
   - Explain gameplay impact

4. **Keep migration history**
   - Never delete old schema definitions
   - Maintain complete migration map
   - Support multi-version jumps (v1→v3)

### DON'T ❌

1. **Don't modify existing schema versions**
   ```dart
   // ❌ BAD: Changing v1 parameters
   static const RuleSchema _schemaV1 = RuleSchema(
     parameters: [..., 'newParam'],  // Don't add to old version!
   );

   // ✅ GOOD: Create new version
   static const RuleSchema _schemaV2 = RuleSchema(
     parameters: [..., 'newParam'],  // Add to new version
   );
   ```

2. **Don't skip migration testing**
   - Always test before release
   - Check all predefined variants
   - Verify custom puzzles work

3. **Don't remove parameters from schema**
   - Breaks backward compatibility
   - Orphans puzzles using that parameter
   - Instead: deprecate and keep in schema

## Troubleshooting

### Problem: Old puzzles not showing

**Cause**: Migration mapping missing

**Solution**:
```dart
// Check if hash needs migration
final needsMigration = oldHash.needsMigration;

// Get migrated hash
final newHash = oldHash.migratedHash;

// Add to migration map if missing
RuleMigrationManager._migrations[oldHash] = newHash;
```

### Problem: Hash changes between releases

**Cause**: Schema version not locked

**Solution**:
```dart
// Lock to specific version for testing
final hash = calculator.calculateHash(
  settings,
  version: RuleSchemaVersion.v1,  // Explicit version
);
```

### Problem: Custom variant lost after upgrade

**Cause**: Custom variants don't have migration mapping

**Solution**:
```dart
// Generate hash for custom variant in both versions
final v1Hash = calculator.calculateHash(customSettings, version: v1);
final v2Hash = calculator.calculateHash(customSettings, version: v2);

// Add manual migration
RuleMigrationManager._migrations[v1Hash] = v2Hash;
```

## Future Enhancements

Potential improvements to the migration system:

1. **Automatic mapping generation**
   - Script to auto-generate migrations
   - Run during build process
   - Validate completeness

2. **Database migration on upgrade**
   - Update `ruleVariantId` field in database
   - Convert v1 hashes to v2 automatically
   - One-time migration on app upgrade

3. **Migration analytics**
   - Track which puzzles needed migration
   - Report orphaned puzzles
   - Suggest missing mappings

4. **Multi-version support**
   - Allow puzzles to specify compatible version range
   - "Works with v1-v3"
   - Automatic cross-version matching

## Summary

**Key Principle**: Schema versioning ensures that adding new rule parameters doesn't break existing puzzles.

**Process**:
1. Add parameter to `RuleSettings`
2. Create new schema version with parameter
3. Generate hash migration mappings
4. Add mappings to `RuleMigrationManager`
5. Test migration thoroughly
6. Release with confidence

**Result**: Users never lose puzzles during upgrades! 🎉
