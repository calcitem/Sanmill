/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

part of './game_page.dart';

class GameHeader extends StatelessWidget {
  const GameHeader({
    required this.gameMode,
    Key? key,
  }) : super(key: key);

  final GameMode gameMode;

  @override
  Widget build(BuildContext context) {
    final iconRow = IconTheme(
      data: IconThemeData(
        color: LocalDatabaseService.colorSettings.messageColor,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(gameMode.leftHeaderIcon),
          Icon(
            MillController().gameInstance.sideToMove.icon,
          ),
          Icon(gameMode.rightHeaderIcon),
        ],
      ),
    );

    return BlockSemantics(
      child: Container(
        margin: EdgeInsets.only(
          top: LocalDatabaseService.display.boardTop +
              (Constants.isLargeScreen ? 39.0 : 0.0),
        ),
        child: Column(
          children: <Widget>[
            iconRow,
            Container(
              height: 4,
              width: 180,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: LocalDatabaseService.colorSettings.boardBackgroundColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _HeaderTip(),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderTip extends StatefulWidget {
  const _HeaderTip({Key? key}) : super(key: key);

  @override
  _HeaderStateTip createState() => _HeaderStateTip();
}

class _HeaderStateTip extends State<_HeaderTip> {
  String? message;

  void showTip() {
    final tipState = MillController().tip;

    if (tipState.showSnackBar && tipState.message != null) {
      ScaffoldMessenger.of(context).showSnackBarClear(tipState.message!);
    }
    setState(() => message = tipState.message);
  }

  @override
  void initState() {
    MillController().tip.addListener(showTip);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      message ?? S.of(context).welcome,
      maxLines: 1,
      style: TextStyle(
        color: LocalDatabaseService.colorSettings.messageColor,
      ),
    );
  }

  @override
  void dispose() {
    MillController().tip.removeListener(showTip);
    super.dispose();
  }
}
