// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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
      label: S.of(context).whenBoardIsFull,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            RadioListTile<BoardFullAction>(
              title: Text(S.of(context).firstPlayerLose),
              groupValue: boardFullAction,
              value: BoardFullAction.firstPlayerLose,
              onChanged: onChanged,
            ),
            RadioListTile<BoardFullAction>(
              title: Text(S.of(context).firstAndSecondPlayerRemovePiece),
              groupValue: boardFullAction,
              value: BoardFullAction.firstAndSecondPlayerRemovePiece,
              onChanged: onChanged,
            ),
            RadioListTile<BoardFullAction>(
              title: Text(S.of(context).secondAndFirstPlayerRemovePiece),
              groupValue: boardFullAction,
              value: BoardFullAction.secondAndFirstPlayerRemovePiece,
              onChanged: onChanged,
            ),
            RadioListTile<BoardFullAction>(
              title: Text(S.of(context).sideToMoveRemovePiece),
              groupValue: boardFullAction,
              value: BoardFullAction.sideToMoveRemovePiece,
              onChanged: onChanged,
            ),
            RadioListTile<BoardFullAction>(
              title: Text(S.of(context).agreeToDraw),
              groupValue: boardFullAction,
              value: BoardFullAction.agreeToDraw,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
