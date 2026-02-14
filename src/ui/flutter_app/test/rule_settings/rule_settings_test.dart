// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// rule_settings_test.dart

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Default RuleSettings
  // ---------------------------------------------------------------------------
  group('RuleSettings defaults', () {
    test('should have Nine Men\'s Morris standard defaults', () {
      const RuleSettings r = RuleSettings();

      expect(r.piecesCount, 9);
      expect(r.flyPieceCount, 3);
      expect(r.piecesAtLeastCount, 3);
      expect(r.hasDiagonalLines, isFalse);
      expect(r.mayMoveInPlacingPhase, isFalse);
      expect(r.isDefenderMoveFirst, isFalse);
      expect(r.mayRemoveMultiple, isFalse);
      expect(r.mayRemoveFromMillsAlways, isFalse);
      expect(r.boardFullAction, BoardFullAction.firstPlayerLose);
      expect(r.stalemateAction, StalemateAction.endWithStalemateLoss);
      expect(r.mayFly, isTrue);
      expect(r.nMoveRule, 100);
      expect(r.endgameNMoveRule, 100);
      expect(r.threefoldRepetitionRule, isTrue);
      expect(
        r.millFormationActionInPlacingPhase,
        MillFormationActionInPlacingPhase.removeOpponentsPieceFromBoard,
      );
      expect(r.restrictRepeatedMillsFormation, isFalse);
      expect(r.oneTimeUseMill, isFalse);
      expect(r.enableCustodianCapture, isFalse);
      expect(r.enableInterventionCapture, isFalse);
      expect(r.enableLeapCapture, isFalse);
      expect(r.stopPlacingWhenTwoEmptySquares, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // fromLocale factory
  // ---------------------------------------------------------------------------
  group('RuleSettings.fromLocale', () {
    test('Afrikaans (af) → MorabarabaRuleSettings', () {
      final RuleSettings r = RuleSettings.fromLocale(const Locale('af'));

      expect(r, isA<MorabarabaRuleSettings>());
      expect(r.piecesCount, 12);
      expect(r.hasDiagonalLines, isTrue);
      expect(r.boardFullAction, BoardFullAction.agreeToDraw);
      expect(r.endgameNMoveRule, 10);
      expect(r.restrictRepeatedMillsFormation, isTrue);
    });

    test('Zulu (zu) → MorabarabaRuleSettings', () {
      final RuleSettings r = RuleSettings.fromLocale(const Locale('zu'));
      expect(r, isA<MorabarabaRuleSettings>());
    });

    test('Farsi (fa) → TwelveMensMorrisRuleSettings', () {
      final RuleSettings r = RuleSettings.fromLocale(const Locale('fa'));

      expect(r, isA<TwelveMensMorrisRuleSettings>());
      expect(r.piecesCount, 12);
      expect(r.hasDiagonalLines, isTrue);
    });

    test('Sinhala (si) → TwelveMensMorrisRuleSettings', () {
      final RuleSettings r = RuleSettings.fromLocale(const Locale('si'));
      expect(r, isA<TwelveMensMorrisRuleSettings>());
    });

    test('Russian (ru) → OneTimeMillRuleSettings', () {
      final RuleSettings r = RuleSettings.fromLocale(const Locale('ru'));

      expect(r, isA<OneTimeMillRuleSettings>());
      expect(r.oneTimeUseMill, isTrue);
      expect(r.mayRemoveFromMillsAlways, isTrue);
    });

    test('Korean (ko) → ChamGonuRuleSettings', () {
      final RuleSettings r = RuleSettings.fromLocale(const Locale('ko'));

      expect(r, isA<ChamGonuRuleSettings>());
      expect(r.piecesCount, 12);
      expect(r.hasDiagonalLines, isTrue);
      expect(
        r.millFormationActionInPlacingPhase,
        MillFormationActionInPlacingPhase.markAndDelayRemovingPieces,
      );
      expect(r.mayFly, isFalse);
      expect(r.mayRemoveFromMillsAlways, isTrue);
    });

    test('English (en) → default RuleSettings', () {
      final RuleSettings r = RuleSettings.fromLocale(const Locale('en'));

      expect(r.piecesCount, 9);
      expect(r.hasDiagonalLines, isFalse);
    });

    test('null locale → default RuleSettings', () {
      final RuleSettings r = RuleSettings.fromLocale(null);

      expect(r.piecesCount, 9);
    });
  });

  // ---------------------------------------------------------------------------
  // isLikely* detection methods
  // ---------------------------------------------------------------------------
  group('isLikely* methods', () {
    test('default RuleSettings isLikelyNineMensMorris', () {
      const RuleSettings r = RuleSettings();
      expect(r.isLikelyNineMensMorris(), isTrue);
      expect(r.isLikelyTwelveMensMorris(), isFalse);
      expect(r.isLikelyElFilja(), isFalse);
    });

    test('NineMensMorrisRuleSettings isLikelyNineMensMorris', () {
      const NineMensMorrisRuleSettings r = NineMensMorrisRuleSettings();
      expect(r.isLikelyNineMensMorris(), isTrue);
    });

    test('TwelveMensMorrisRuleSettings isLikelyTwelveMensMorris', () {
      const TwelveMensMorrisRuleSettings r = TwelveMensMorrisRuleSettings();
      expect(r.isLikelyTwelveMensMorris(), isTrue);
      expect(r.isLikelyNineMensMorris(), isFalse);
    });

    test('ELFiljaRuleSettings isLikelyElFilja', () {
      const ELFiljaRuleSettings r = ELFiljaRuleSettings();
      expect(r.isLikelyElFilja(), isTrue);
      expect(r.isLikelyNineMensMorris(), isFalse);
      expect(r.isLikelyTwelveMensMorris(), isFalse);
    });

    test('custom settings with diagonal and custodian is not NineMens', () {
      const RuleSettings r = RuleSettings(
        piecesCount: 9,
        enableCustodianCapture: true,
      );
      expect(r.isLikelyNineMensMorris(), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Named variant classes
  // ---------------------------------------------------------------------------
  group('Named variant classes', () {
    test('NineMensMorrisRuleSettings', () {
      const NineMensMorrisRuleSettings r = NineMensMorrisRuleSettings();
      expect(r.piecesCount, 9);
      expect(r.hasDiagonalLines, isFalse);
    });

    test('TwelveMensMorrisRuleSettings', () {
      const TwelveMensMorrisRuleSettings r = TwelveMensMorrisRuleSettings();
      expect(r.piecesCount, 12);
      expect(r.hasDiagonalLines, isTrue);
    });

    test('MorabarabaRuleSettings', () {
      const MorabarabaRuleSettings r = MorabarabaRuleSettings();
      expect(r.piecesCount, 12);
      expect(r.hasDiagonalLines, isTrue);
      expect(r.boardFullAction, BoardFullAction.agreeToDraw);
      expect(r.endgameNMoveRule, 10);
      expect(r.restrictRepeatedMillsFormation, isTrue);
    });

    test('DoozRuleSettings', () {
      const DoozRuleSettings r = DoozRuleSettings();
      expect(r.piecesCount, 12);
      expect(r.hasDiagonalLines, isTrue);
      expect(
        r.millFormationActionInPlacingPhase,
        MillFormationActionInPlacingPhase
            .removeOpponentsPieceFromHandThenOpponentsTurn,
      );
      expect(r.boardFullAction, BoardFullAction.sideToMoveRemovePiece);
      expect(r.mayRemoveFromMillsAlways, isTrue);
    });

    test('LaskerMorrisSettings', () {
      const LaskerMorrisSettings r = LaskerMorrisSettings();
      expect(r.piecesCount, 10);
      expect(r.mayMoveInPlacingPhase, isTrue);
    });

    test('OneTimeMillRuleSettings', () {
      const OneTimeMillRuleSettings r = OneTimeMillRuleSettings();
      expect(r.oneTimeUseMill, isTrue);
      expect(r.mayRemoveFromMillsAlways, isTrue);
    });

    test('ChamGonuRuleSettings', () {
      const ChamGonuRuleSettings r = ChamGonuRuleSettings();
      expect(r.piecesCount, 12);
      expect(r.hasDiagonalLines, isTrue);
      expect(
        r.millFormationActionInPlacingPhase,
        MillFormationActionInPlacingPhase.markAndDelayRemovingPieces,
      );
      expect(r.mayFly, isFalse);
    });

    test('ZhiQiRuleSettings', () {
      const ZhiQiRuleSettings r = ZhiQiRuleSettings();
      expect(r.piecesCount, 12);
      expect(r.hasDiagonalLines, isTrue);
      expect(
        r.boardFullAction,
        BoardFullAction.firstAndSecondPlayerRemovePiece,
      );
      expect(r.mayFly, isFalse);
    });

    test('ChengSanQiRuleSettings', () {
      const ChengSanQiRuleSettings r = ChengSanQiRuleSettings();
      expect(r.piecesCount, 9);
      expect(
        r.millFormationActionInPlacingPhase,
        MillFormationActionInPlacingPhase.markAndDelayRemovingPieces,
      );
      expect(r.mayFly, isFalse);
    });

    test('DaSanQiRuleSettings', () {
      const DaSanQiRuleSettings r = DaSanQiRuleSettings();
      expect(r.piecesCount, 12);
      expect(r.hasDiagonalLines, isTrue);
      expect(r.isDefenderMoveFirst, isTrue);
      expect(r.mayRemoveMultiple, isTrue);
      expect(r.mayFly, isFalse);
    });

    test('MulMulanRuleSettings', () {
      const MulMulanRuleSettings r = MulMulanRuleSettings();
      expect(r.piecesCount, 9);
      expect(r.hasDiagonalLines, isTrue);
      expect(r.enableInterventionCapture, isTrue);
      expect(r.mayFly, isFalse);
    });

    test('NerenchiRuleSettings', () {
      const NerenchiRuleSettings r = NerenchiRuleSettings();
      expect(r.piecesCount, 12);
      expect(r.hasDiagonalLines, isTrue);
      expect(r.isDefenderMoveFirst, isTrue);
    });

    test('ELFiljaRuleSettings', () {
      const ELFiljaRuleSettings r = ELFiljaRuleSettings();
      expect(r.piecesCount, 12);
      expect(
        r.millFormationActionInPlacingPhase,
        MillFormationActionInPlacingPhase.removalBasedOnMillCounts,
      );
      expect(
        r.boardFullAction,
        BoardFullAction.firstAndSecondPlayerRemovePiece,
      );
      expect(r.mayFly, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // ruleSetProperties map
  // ---------------------------------------------------------------------------
  group('ruleSetProperties map', () {
    test('should contain an entry for every RuleSet value', () {
      for (final RuleSet ruleSet in RuleSet.values) {
        expect(
          ruleSetProperties.containsKey(ruleSet),
          isTrue,
          reason: 'Missing ruleSetProperties entry for $ruleSet',
        );
      }
    });

    test('should contain an entry for every RuleSet in descriptions', () {
      for (final RuleSet ruleSet in RuleSet.values) {
        expect(
          ruleSetDescriptions.containsKey(ruleSet),
          isTrue,
          reason: 'Missing ruleSetDescriptions entry for $ruleSet',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Enum utility
  // ---------------------------------------------------------------------------
  group('enumName', () {
    test('should map BoardFullAction values', () {
      expect(enumName(BoardFullAction.firstPlayerLose), '0-1');
      expect(enumName(BoardFullAction.firstAndSecondPlayerRemovePiece), 'W->B');
      expect(enumName(BoardFullAction.secondAndFirstPlayerRemovePiece), 'B->W');
      expect(enumName(BoardFullAction.sideToMoveRemovePiece), 'X');
      expect(enumName(BoardFullAction.agreeToDraw), '=');
    });

    test('should map StalemateAction values', () {
      expect(enumName(StalemateAction.endWithStalemateLoss), '0-1');
      expect(enumName(StalemateAction.changeSideToMove), '->');
      expect(
        enumName(StalemateAction.removeOpponentsPieceAndMakeNextMove),
        'XM',
      );
      expect(
        enumName(StalemateAction.removeOpponentsPieceAndChangeSideToMove),
        'X ->',
      );
      expect(enumName(StalemateAction.endWithStalemateDraw), '=');
      expect(enumName(StalemateAction.bothPlayersRemoveOpponentsPiece), 'XX');
    });

    test('should return empty string for unknown enum entry', () {
      // Using an unrelated object to trigger the default case
      expect(enumName('unknown'), '');
    });
  });
}
