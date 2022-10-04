// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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

part of '../game_toolbar.dart';

class GamePageToolBar extends StatelessWidget {
  final List<Widget> children;
  final Color? backgroundColor;
  final Color? itemColor;

  static const _padding = EdgeInsets.symmetric(vertical: 2);
  static const _margin = EdgeInsets.symmetric(vertical: 0.5);

  /// Gets the calculated height this widget adds to it's children.
  /// To get the absolute height add the surrounding [ButtonThemeData.height].
  static double get height => (_padding.vertical + _margin.vertical) * 2;

  const GamePageToolBar({
    Key? key,
    required this.children,
    this.backgroundColor,
    this.itemColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        color: backgroundColor,
      ),
      margin: _margin,
      padding: _padding,
      child: ToolbarItemTheme(
        data: ToolbarItemThemeData(
          style: ToolbarItem.styleFrom(primary: itemColor),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ButtonBar(
            buttonPadding: EdgeInsets.zero,
            alignment: MainAxisAlignment.spaceAround,
            children: children,
          ),
        ),
      ),
    );
  }
}

class SetupPositionToolBar extends StatefulWidget {
  const SetupPositionToolBar({Key? key}) : super(key: key);

  @override
  State<SetupPositionToolBar> createState() => SetupPositionToolBarState();
}

class SetupPositionToolBarState extends State<SetupPositionToolBar> {
  final Color? backgroundColor = DB().colorSettings.mainToolbarBackgroundColor;
  final Color? itemColor = DB().colorSettings.mainToolbarIconColor;

  late GameMode gameModeBackup;
  final position = MillController().position;
  late Position positionBackup;

  Phase phase = Phase.placing;

  void initContext() {
    gameModeBackup = MillController().gameInstance.gameMode;
    MillController().gameInstance.gameMode = GameMode.setupPosition;

    positionBackup = MillController().position.clone();
    MillController().position.reset();
  }

  void restoreContext() {
    MillController().position.copyWith(positionBackup);
    MillController().gameInstance.gameMode = gameModeBackup;
  }

  @override
  void initState() {
    super.initState();
    initContext();
  }

  static const _padding = EdgeInsets.symmetric(vertical: 2);
  static const _margin = EdgeInsets.symmetric(vertical: 0.2);

  /// Gets the calculated height this widget adds to it's children.
  /// To get the absolute height add the surrounding [ButtonThemeData.height].
  static double get height => (_padding.vertical + _margin.vertical) * 2;

  setSetupPositionPiece(BuildContext context, PieceColor pieceColor) {
    MillController().position.sideToSetup = pieceColor;
    MillController().headerTipNotifier.showTip(pieceColor.pieceName(context));

    if (pieceColor == PieceColor.none) {
      position.action = Act.remove;
    } else {
      position.action = Act.place;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Piece
    final whitePieceButton = ToolbarItem.icon(
      onPressed: () => setSetupPositionPiece(context, PieceColor.white),
      icon: Icon(FluentIcons.circle_24_filled,
          color: DB().colorSettings.whitePieceColor),
      label: Text(S.of(context).whitePiece),
    );
    final blackPieceButton = ToolbarItem.icon(
      onPressed: () => setSetupPositionPiece(context, PieceColor.black),
      icon: Icon(FluentIcons.circle_24_filled,
          color: DB().colorSettings.blackPieceColor),
      label: Text(S.of(context).blackPiece),
    );
    final banPointButton = ToolbarItem.icon(
      onPressed: () => setSetupPositionPiece(context, PieceColor.ban),
      icon: const Icon(FluentIcons.prohibited_24_regular),
      label: Text(S.of(context).banPoint),
    );
    final emptyPointButton = ToolbarItem.icon(
      onPressed: () => setSetupPositionPiece(context, PieceColor.none),
      icon: const Icon(FluentIcons.add_24_regular),
      label: Text(S.of(context).emptyPoint),
    );

    // Clear
    final clearButton = ToolbarItem.icon(
      onPressed: () {
        MillController().position.reset();
        MillController()
            .headerTipNotifier
            .showTip(S.of(context).restart); // TODO: reset
      },
      icon: const Icon(FluentIcons.eraser_24_regular),
      label: const Text("Clean"), // TODO: l10n
    );

    // Phase
    final placingButton = ToolbarItem.icon(
      onPressed: () => {phase = Phase.placing},
      icon: const Icon(FluentIcons.grid_dots_24_regular),
      label: const Text("Placing"),
    );

    final movingButton = ToolbarItem.icon(
      onPressed: () => {phase = Phase.moving},
      icon: const Icon(FluentIcons.arrow_move_24_regular),
      label: const Text("Moving"),
    );

    final pasteButton = ToolbarItem.icon(
      onPressed: () => {
        rootScaffoldMessengerKey.currentState!
            .showSnackBarClear(S.of(context).experimental)
      },
      icon: const Icon(FluentIcons.clipboard_paste_24_regular),
      label: const Text("Paste"),
    );

    // Cancel
    final cancelButton = ToolbarItem.icon(
      onPressed: () => {restoreContext()}, // TODO: setState();
      icon: const Icon(FluentIcons.dismiss_24_regular),
      label: Text(S.of(context).cancel),
    );

    final doneButton = ToolbarItem.icon(
      onPressed: () {
        MillController().gameInstance.gameMode = gameModeBackup;
        MillController().position.phase = phase;
        if (phase == Phase.placing) {
          MillController().position.action = Act.place;
        } else if (phase == Phase.moving) {
          MillController().position.action = Act.select;
        }
      }, // TODO: set position fen
      icon: const Icon(FluentIcons.hand_left_24_regular),
      label: Text(S.of(context).done),
    );

    final rowOne = <Widget>[
      whitePieceButton,
      blackPieceButton,
      //banPointButton,
      emptyPointButton,
      clearButton,
    ];

    final row2 = <Widget>[
      placingButton,
      movingButton,
      //pasteButton,
      cancelButton,
      doneButton,
    ];

    return Column(
      children: [
        SetupPositionButtonsContainer(
          backgroundColor: backgroundColor,
          margin: _margin,
          padding: _padding,
          itemColor: itemColor,
          child: rowOne,
        ),
        SetupPositionButtonsContainer(
          backgroundColor: backgroundColor,
          margin: _margin,
          padding: _padding,
          itemColor: itemColor,
          child: row2,
        ),
      ],
    );
  }
}

class SetupPositionButtonsContainer extends StatelessWidget {
  const SetupPositionButtonsContainer({
    Key? key,
    required this.backgroundColor,
    required EdgeInsets margin,
    required EdgeInsets padding,
    required this.itemColor,
    required this.child,
  })  : _margin = margin,
        _padding = padding,
        super(key: key);

  final Color? backgroundColor;
  final EdgeInsets _margin;
  final EdgeInsets _padding;
  final Color? itemColor;
  final List<Widget> child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        color: backgroundColor,
      ),
      margin: _margin,
      padding: _padding,
      child: ToolbarItemTheme(
        data: ToolbarItemThemeData(
          style: ToolbarItem.styleFrom(primary: itemColor),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ButtonBar(
            buttonPadding: EdgeInsets.zero,
            alignment: MainAxisAlignment.spaceAround,
            children: child,
          ),
        ),
      ),
    );
  }
}
