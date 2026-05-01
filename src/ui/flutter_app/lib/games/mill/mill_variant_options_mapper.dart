// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Converts persisted Dart RuleSettings into the typed Rust/FRB Mill variant
// options.  This is the migration path away from the legacy UCI `setoption`
// string fan-out in engine.dart.

import '../../general_settings/models/general_settings.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../src/rust/api/simple.dart' as tgf;

extension MillVariantOptionsMapper on RuleSettings {
  /// Convert the subset of settings currently supported by Rust-native
  /// MillRules into the FRB DTO.  Unsupported fields remain on the legacy
  /// C++ path until the corresponding Rust rule is implemented.
  ///
  /// `generalSettings` carries the engine-behavior toggles (mobility,
  /// blocking paths) that the legacy C++ engine read from the global
  /// `gameOptions` singleton.  When omitted the FRB defaults
  /// (`consider_mobility=true`, `focus_on_blocking_paths=false`) apply,
  /// matching the C++ initialisation in option.h.
  tgf.MillVariantOptions toTgfMillVariantOptions({
    GeneralSettings? generalSettings,
  }) {
    return tgf.MillVariantOptions(
      pieceCount: piecesCount,
      flyPieceCount: flyPieceCount,
      piecesAtLeastCount: piecesAtLeastCount,
      mayFly: mayFly,
      hasDiagonalLines: hasDiagonalLines,
      millFormationActionInPlacingPhase: _toTgfMillFormationAction(
        millFormationActionInPlacingPhase,
      ),
      mayRemoveFromMillsAlways: mayRemoveFromMillsAlways,
      mayRemoveMultiple: mayRemoveMultiple,
      nMoveRule: nMoveRule,
      endgameNMoveRule: endgameNMoveRule,
      mayMoveInPlacingPhase: mayMoveInPlacingPhase,
      isDefenderMoveFirst: isDefenderMoveFirst,
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
      stalemateAction: _toTgfStalemateAction(stalemateAction),
      considerMobility: generalSettings?.considerMobility ?? true,
      focusOnBlockingPaths: generalSettings?.focusOnBlockingPaths ?? false,
    );
  }

  static tgf.MillBoardFullAction _toTgfBoardFullAction(BoardFullAction? value) {
    return switch (value ?? BoardFullAction.firstPlayerLose) {
      BoardFullAction.firstPlayerLose =>
        tgf.MillBoardFullAction.firstPlayerLose,
      BoardFullAction.firstAndSecondPlayerRemovePiece =>
        tgf.MillBoardFullAction.firstAndSecondPlayerRemovePiece,
      BoardFullAction.secondAndFirstPlayerRemovePiece =>
        tgf.MillBoardFullAction.secondAndFirstPlayerRemovePiece,
      BoardFullAction.sideToMoveRemovePiece =>
        tgf.MillBoardFullAction.sideToMoveRemovePiece,
      BoardFullAction.agreeToDraw => tgf.MillBoardFullAction.agreeToDraw,
    };
  }

  static tgf.MillFormationActionInPlacingPhase _toTgfMillFormationAction(
    MillFormationActionInPlacingPhase? value,
  ) {
    return switch (value ??
        MillFormationActionInPlacingPhase.removeOpponentsPieceFromBoard) {
      MillFormationActionInPlacingPhase.removeOpponentsPieceFromBoard =>
        tgf.MillFormationActionInPlacingPhase.removeOpponentsPieceFromBoard,
      MillFormationActionInPlacingPhase
          .removeOpponentsPieceFromHandThenOpponentsTurn =>
        tgf
            .MillFormationActionInPlacingPhase
            .removeOpponentsPieceFromHandThenOpponentsTurn,
      MillFormationActionInPlacingPhase
          .removeOpponentsPieceFromHandThenYourTurn =>
        tgf
            .MillFormationActionInPlacingPhase
            .removeOpponentsPieceFromHandThenYourTurn,
      MillFormationActionInPlacingPhase.opponentRemovesOwnPiece =>
        tgf.MillFormationActionInPlacingPhase.opponentRemovesOwnPiece,
      MillFormationActionInPlacingPhase.markAndDelayRemovingPieces =>
        tgf.MillFormationActionInPlacingPhase.markAndDelayRemovingPieces,
      MillFormationActionInPlacingPhase.removalBasedOnMillCounts =>
        tgf.MillFormationActionInPlacingPhase.removalBasedOnMillCounts,
    };
  }

  static tgf.StalemateAction _toTgfStalemateAction(StalemateAction? value) {
    return switch (value ?? StalemateAction.endWithStalemateLoss) {
      StalemateAction.endWithStalemateLoss =>
        tgf.StalemateAction.endWithStalemateLoss,
      StalemateAction.changeSideToMove => tgf.StalemateAction.changeSideToMove,
      StalemateAction.removeOpponentsPieceAndMakeNextMove =>
        tgf.StalemateAction.removeOpponentsPieceAndMakeNextMove,
      StalemateAction.removeOpponentsPieceAndChangeSideToMove =>
        tgf.StalemateAction.removeOpponentsPieceAndChangeSideToMove,
      StalemateAction.endWithStalemateDraw =>
        tgf.StalemateAction.endWithStalemateDraw,
      StalemateAction.bothPlayersRemoveOpponentsPiece =>
        tgf.StalemateAction.bothPlayersRemoveOpponentsPiece,
    };
  }
}
