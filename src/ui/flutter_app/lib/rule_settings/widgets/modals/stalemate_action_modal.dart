// This file is part of Sanmill.
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)
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

class _StalemateActionModal extends StatelessWidget {
  const _StalemateActionModal({
    required this.stalemateAction,
    required this.onChanged,
  });

  final StalemateAction stalemateAction;
  final Function(StalemateAction?)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: S.of(context).whenStalemate,
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
        S.of(context).endWithStalemateLoss,
        StalemateAction.endWithStalemateLoss,
        key: const Key('end_with_stalemate_loss'),
      ),
      _buildRadioListTile(
        context,
        S.of(context).changeSideToMove,
        StalemateAction.changeSideToMove,
        key: const Key('change_side_to_move'),
      ),
      _buildRadioListTile(
        context,
        S.of(context).removeOpponentsPieceAndMakeNextMove,
        StalemateAction.removeOpponentsPieceAndMakeNextMove,
        key: const Key('remove_opponents_piece_and_make_next_move'),
      ),
      _buildRadioListTile(
        context,
        S.of(context).removeOpponentsPieceAndChangeSideToMove,
        StalemateAction.removeOpponentsPieceAndChangeSideToMove,
        key: const Key('remove_opponents_piece_and_change_side_to_move'),
      ),
      _buildRadioListTile(
        context,
        S.of(context).endWithStalemateDraw,
        StalemateAction.endWithStalemateDraw,
        key: const Key('end_with_stalemate_draw'),
      ),
    ];
  }

  Widget _buildRadioListTile(
    BuildContext context,
    String title,
    StalemateAction value, {
    Key? key,
  }) {
    return Semantics(
      label: title,
      child: RadioListTile<StalemateAction>(
        key: key,
        title: Text(title),
        groupValue: stalemateAction,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
