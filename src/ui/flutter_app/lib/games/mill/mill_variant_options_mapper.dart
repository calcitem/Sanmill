// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Converts persisted Dart RuleSettings into the typed Rust/FRB Mill variant
// options.  This is the migration path away from the legacy UCI `setoption`
// string fan-out in engine.dart.

import '../../rule_settings/models/rule_settings.dart';
import '../../src/rust/api/simple.dart' as tgf;

extension MillVariantOptionsMapper on RuleSettings {
  /// Convert the subset of settings currently supported by Rust-native
  /// MillRules into the FRB DTO.  Unsupported fields remain on the legacy
  /// C++ path until the corresponding Rust rule is implemented.
  tgf.MillVariantOptions toTgfMillVariantOptions() {
    return tgf.MillVariantOptions(
      pieceCount: piecesCount,
      flyPieceCount: flyPieceCount,
      piecesAtLeastCount: piecesAtLeastCount,
      mayFly: mayFly,
      hasDiagonalLines: hasDiagonalLines,
      mayRemoveFromMillsAlways: mayRemoveFromMillsAlways,
      mayRemoveMultiple: mayRemoveMultiple,
      nMoveRule: nMoveRule,
      endgameNMoveRule: endgameNMoveRule,
      mayMoveInPlacingPhase: mayMoveInPlacingPhase,
      restrictRepeatedMillsFormation: restrictRepeatedMillsFormation,
      oneTimeUseMill: oneTimeUseMill,
      stopPlacingWhenTwoEmptySquares: stopPlacingWhenTwoEmptySquares,
      boardFullAction: _toTgfBoardFullAction(boardFullAction),
      threefoldRepetitionRule: threefoldRepetitionRule,
      custodianCapture: tgf.CaptureRuleConfig(
        enabled: enableCustodianCapture,
        onSquareEdges: custodianCaptureOnSquareEdges,
        onCrossLines: custodianCaptureOnCrossLines,
        onDiagonalLines: custodianCaptureOnDiagonalLines,
        inPlacingPhase: custodianCaptureInPlacingPhase,
        inMovingPhase: custodianCaptureInMovingPhase,
        onlyAvailableWhenOwnPiecesLeq3: custodianCaptureOnlyWhenOwnPiecesLeq3,
      ),
      interventionCapture: tgf.CaptureRuleConfig(
        enabled: enableInterventionCapture,
        onSquareEdges: interventionCaptureOnSquareEdges,
        onCrossLines: interventionCaptureOnCrossLines,
        onDiagonalLines: interventionCaptureOnDiagonalLines,
        inPlacingPhase: interventionCaptureInPlacingPhase,
        inMovingPhase: interventionCaptureInMovingPhase,
        onlyAvailableWhenOwnPiecesLeq3:
            interventionCaptureOnlyWhenOwnPiecesLeq3,
      ),
      leapCapture: tgf.CaptureRuleConfig(
        enabled: enableLeapCapture,
        onSquareEdges: leapCaptureOnSquareEdges,
        onCrossLines: leapCaptureOnCrossLines,
        onDiagonalLines: leapCaptureOnDiagonalLines,
        inPlacingPhase: leapCaptureInPlacingPhase,
        inMovingPhase: leapCaptureInMovingPhase,
        onlyAvailableWhenOwnPiecesLeq3: leapCaptureOnlyWhenOwnPiecesLeq3,
      ),
    );
  }

  static tgf.MillBoardFullAction _toTgfBoardFullAction(BoardFullAction? value) {
    return switch (value ?? BoardFullAction.firstPlayerLose) {
      BoardFullAction.firstPlayerLose => tgf.MillBoardFullAction.firstPlayerLose,
      BoardFullAction.firstAndSecondPlayerRemovePiece =>
        tgf.MillBoardFullAction.firstAndSecondPlayerRemovePiece,
      BoardFullAction.secondAndFirstPlayerRemovePiece =>
        tgf.MillBoardFullAction.secondAndFirstPlayerRemovePiece,
      BoardFullAction.sideToMoveRemovePiece =>
        tgf.MillBoardFullAction.sideToMoveRemovePiece,
      BoardFullAction.agreeToDraw => tgf.MillBoardFullAction.agreeToDraw,
    };
  }
}
