// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

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
      label: S.of(context).whenFormingMillsDuringPlacingPhase,
      child: SingleChildScrollView(
        child: Column(
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
    return Semantics(
      label: title,
      child: RadioListTile<MillFormationActionInPlacingPhase>(
        title: Text(title),
        groupValue: millFormationActionInPlacingPhase,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
