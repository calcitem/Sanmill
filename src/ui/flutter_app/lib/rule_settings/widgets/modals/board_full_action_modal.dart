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

class _BoardFullActionModal extends StatelessWidget {
  const _BoardFullActionModal({
    required this.boardFullAction,
    required this.onChanged,
  });

  final BoardFullAction boardFullAction;
  final Function(BoardFullAction?)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('board_full_action_modal_semantics'),
      label: S.of(context).whenBoardIsFull,
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
        S.of(context).firstPlayerLose,
        BoardFullAction.firstPlayerLose,
        const Key('radio_first_player_lose'),
      ),
      _buildRadioListTile(
        context,
        S.of(context).firstAndSecondPlayerRemovePiece,
        BoardFullAction.firstAndSecondPlayerRemovePiece,
        const Key('radio_first_and_second_player_remove_piece'),
      ),
      _buildRadioListTile(
        context,
        S.of(context).secondAndFirstPlayerRemovePiece,
        BoardFullAction.secondAndFirstPlayerRemovePiece,
        const Key('radio_second_and_first_player_remove_piece'),
      ),
      _buildRadioListTile(
        context,
        S.of(context).sideToMoveRemovePiece,
        BoardFullAction.sideToMoveRemovePiece,
        const Key('radio_side_to_move_remove_piece'),
      ),
      _buildRadioListTile(
        context,
        S.of(context).agreeToDraw,
        BoardFullAction.agreeToDraw,
        const Key('radio_agree_to_draw'),
      ),
    ];
  }

  Widget _buildRadioListTile(
    BuildContext context,
    String title,
    BoardFullAction value,
    Key key,
  ) {
    return Semantics(
      label: title,
      child: RadioListTile<BoardFullAction>(
        key: key,
        title: Text(title),
        groupValue: boardFullAction,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
