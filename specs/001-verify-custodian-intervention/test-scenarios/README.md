# Test Scenarios for Custodian and Intervention Rules

This directory contains FEN-based test scenarios organized by functional requirement groups.

## File Organization

- `custodian_standalone.yaml` - FR-001 to FR-004: Custodian rule without mill
- `intervention_standalone.yaml` - FR-005 to FR-009: Intervention rule without mill
- `mill_custodian_combo.yaml` - FR-010 to FR-013: Mill + Custodian interactions
- `mill_intervention_combo.yaml` - FR-014 to FR-017: Mill + Intervention interactions
- `triple_combo.yaml` - FR-032, FR-033: All three rules triggered simultaneously
- `may_remove_multiple_mode.yaml` - FR-018 to FR-020, FR-036 to FR-038: mayRemoveMultiple=false scenarios
- `fen_notation.yaml` - FR-021 to FR-027, FR-034, FR-035, FR-039: FEN import/export with markers
- `move_legality.yaml` - FR-028 to FR-031: Illegal move rejection

## YAML Format

Each scenario file uses this structure:

```yaml
scenarios:
  - id: FR-001-basic-custodian
    description: "Custodian triggered at line endpoint with opponent in middle"
    fen: "position_data c:a1 p:1 w 10"
    expected:
      hasCustodian: true
      custodianTarget: "a1"
      legalTargets: ["a1"]
      illegalTargets: ["b1", "c1", "d1"]
    tags: [custodian, standalone]
```

## Test Execution

These scenarios are consumed by Dart test files:

```dart
// Example usage
final scenarios = loadYaml('custodian_standalone.yaml');
for (var scenario in scenarios['scenarios']) {
  test(scenario['id'], () {
    final game = Game.fromFEN(scenario['fen']);
    expect(game.hasCustodian, equals(scenario['expected']['hasCustodian']));
    // ... additional assertions
  });
}
```

## Coverage Mapping

Each YAML file directly maps to a Dart test file:

| YAML File | Dart Test File | FR Coverage |
|-----------|----------------|-------------|
| custodian_standalone.yaml | custodian_rule_test.dart | FR-001 to FR-004 |
| intervention_standalone.yaml | intervention_rule_test.dart | FR-005 to FR-009 |
| mill_custodian_combo.yaml | mill_custodian_combo_test.dart | FR-010 to FR-013 |
| mill_intervention_combo.yaml | mill_intervention_combo_test.dart | FR-014 to FR-017 |
| triple_combo.yaml | triple_combo_test.dart | FR-032, FR-033 |
| may_remove_multiple_mode.yaml | may_remove_multiple_test.dart | FR-018 to FR-020, FR-036 to FR-038 |
| fen_notation.yaml | fen_notation_test.dart | FR-021 to FR-027, FR-034, FR-035, FR-039 |
| move_legality.yaml | move_legality_test.dart | FR-028 to FR-031 |

Total: 8 scenario files → 8 test files → 39 functional requirements
