// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/games/mill/mill_perfect_database_support.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';

import '../../helpers/mocks/mock_database.dart';

void main() {
  late MockDB mockDB;

  setUp(() {
    mockDB = MockDB();
    DB.instance = mockDB;
  });

  tearDown(() {
    DB.instance = null;
  });

  bool supports(RuleSettings ruleSettings) {
    mockDB.ruleSettings = ruleSettings;
    return isRuleSupportingPerfectDatabase();
  }

  group('isRuleSupportingPerfectDatabase', () {
    test('accepts all legacy Perfect DB rule variants behind one switch', () {
      expect(supports(const RuleSettings()), isTrue);
      expect(supports(const LaskerMorrisSettings()), isTrue);
      expect(supports(const TwelveMensMorrisRuleSettings()), isTrue);
    });

    test('rejects nearby rule combinations without matching DB variants', () {
      expect(supports(const RuleSettings(piecesCount: 10)), isFalse);
      expect(
        supports(
          const RuleSettings(
            piecesCount: 12,
            hasDiagonalLines: true,
            mayMoveInPlacingPhase: true,
          ),
        ),
        isFalse,
      );
      expect(supports(const RuleSettings(piecesCount: 12)), isFalse);
    });

    test('rejects supported variants when common Perfect DB rules differ', () {
      expect(supports(const RuleSettings(mayRemoveMultiple: true)), isFalse);
      expect(
        supports(
          const RuleSettings(
            piecesCount: 10,
            mayMoveInPlacingPhase: true,
            enableLeapCapture: true,
          ),
        ),
        isFalse,
      );
      expect(supports(const MorabarabaRuleSettings()), isFalse);
    });
  });
}
