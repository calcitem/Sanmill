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
          children: <Widget>[
            RadioListTile<StalemateAction>(
              title: Text(S.of(context).endWithStalemateLoss),
              groupValue: stalemateAction,
              value: StalemateAction.endWithStalemateLoss,
              onChanged: onChanged,
            ),
            RadioListTile<StalemateAction>(
              title: Text(S.of(context).changeSideToMove),
              groupValue: stalemateAction,
              value: StalemateAction.changeSideToMove,
              onChanged: onChanged,
            ),
            RadioListTile<StalemateAction>(
              title: Text(S.of(context).removeOpponentsPieceAndMakeNextMove),
              groupValue: stalemateAction,
              value: StalemateAction.removeOpponentsPieceAndMakeNextMove,
              onChanged: onChanged,
            ),
            RadioListTile<StalemateAction>(
              title: Text(S.of(context).removeOpponentsPieceAndChangeSideToMove),
              groupValue: stalemateAction,
              value: StalemateAction.removeOpponentsPieceAndChangeSideToMove,
              onChanged: onChanged,
            ),
            RadioListTile<StalemateAction>(
              title: Text(S.of(context).endWithStalemateDraw),
              groupValue: stalemateAction,
              value: StalemateAction.endWithStalemateDraw,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
