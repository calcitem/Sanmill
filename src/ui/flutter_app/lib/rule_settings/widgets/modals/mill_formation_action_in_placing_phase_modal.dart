// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// mill_formation_action_in_placing_phase_modal.dart

part of 'package:sanmill/rule_settings/widgets/rule_settings_page.dart';

class _MillFormationActionInPlacingPhaseModal extends StatelessWidget {
  const _MillFormationActionInPlacingPhaseModal({
    required this.millFormationActionInPlacingPhase,
    required this.onChanged,
  });

  final MillFormationActionInPlacingPhase millFormationActionInPlacingPhase;
  final Function(MillFormationActionInPlacingPhase?)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('mill_formation_action_in_placing_phase_semantics'),
      label: S.of(context).whenFormingMillsDuringPlacingPhase,
      child: SingleChildScrollView(
        key: const Key('mill_formation_action_in_placing_phase_scroll_view'),
        child: Column(
          key: const Key('mill_formation_action_in_placing_phase_column'),
          mainAxisSize: MainAxisSize.min,
          children: _buildRadioListTiles(context),
        ),
      ),
    );
  }

  List<Widget> _buildRadioListTiles(BuildContext context) {
    return <Widget>[
      _buildRadioListTile(
        context,
        S.of(context).removeOpponentsPieceFromBoard,
        MillFormationActionInPlacingPhase.removeOpponentsPieceFromBoard,
      ),
      _buildRadioListTile(
        context,
        S.of(context).removeOpponentsPieceFromHandThenOpponentsTurn,
        MillFormationActionInPlacingPhase
            .removeOpponentsPieceFromHandThenOpponentsTurn,
      ),
      _buildRadioListTile(
        context,
        S.of(context).removeOpponentsPieceFromHandThenYourTurn,
        MillFormationActionInPlacingPhase
            .removeOpponentsPieceFromHandThenYourTurn,
      ),
      /*
      // TODO: Implement
      _buildRadioListTile(
        context,
        S.of(context).opponentRemovesOwnPiece,
        MillFormationActionInPlacingPhase.opponentRemovesOwnPiece,
      ),
      */
      _buildRadioListTile(
        context,
        S.of(context).markAndDelayRemovingPieces,
        MillFormationActionInPlacingPhase.markAndDelayRemovingPieces,
      ),
      _buildRadioListTile(
        context,
        S.of(context).removalBasedOnMillCounts,
        MillFormationActionInPlacingPhase.removalBasedOnMillCounts,
      ),
    ];
  }

  Widget _buildRadioListTile(
    BuildContext context,
    String title,
    MillFormationActionInPlacingPhase value,
  ) {
    final String keySuffix =
        title.toLowerCase().replaceAll(' ', '_').replaceAll('then_', 'then_');
    return Semantics(
      label: title,
      child: RadioListTile<MillFormationActionInPlacingPhase>(
        key: Key("radio_$keySuffix"),
        title: Text(title),
        groupValue: millFormationActionInPlacingPhase,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
