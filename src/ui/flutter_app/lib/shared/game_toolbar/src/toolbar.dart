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

  PieceColor newPieceColor = PieceColor.white;
  Phase newPhase = Phase.moving;
  int newPieceCountNeedRemove = 0;
  int newWhitePieceRemovedInPlacingPhase = 0;
  int newBlackPieceRemovedInPlacingPhase = 0;

  late GameMode gameModeBackup;
  final position = MillController().position;
  late Position positionBackup;

  void initContext() {
    gameModeBackup = MillController().gameInstance.gameMode;
    MillController().gameInstance.gameMode = GameMode.setupPosition;

    positionBackup = MillController().position.clone();
    //MillController().position.reset();

    newPieceColor = MillController().position.sideToMove;

    if (MillController().position.countPieceOnBoard(PieceColor.white) +
            MillController().position.countPieceOnBoard(PieceColor.black) ==
        0) {
      newPhase = Phase.moving;
    } else {
      if (MillController().position.phase == Phase.moving) {
        newPhase = Phase.moving;
      } else if (MillController().position.phase == Phase.ready ||
          MillController().position.phase == Phase.placing) {
        newPhase = Phase.placing;
      } else if (MillController().position.phase == Phase.gameOver) {
        if (MillController().recorder.length >
            DB().ruleSettings.piecesCount * 2) {
          newPhase = Phase.moving;
        } else {
          newPhase = Phase.placing;
        }
      }
    }

    newPieceCountNeedRemove = MillController().position.pieceToRemoveCount;

    MillController().position.phase = newPhase;
    MillController().position.theWinner = PieceColor.nobody;

    //TODO: newWhitePieceRemovedInPlacingPhase & newBlackPieceRemovedInPlacingPhase;
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
    if (pieceColor == PieceColor.white) {
      newPieceColor = PieceColor.black;
    } else if (pieceColor == PieceColor.black) {
      if (DB().ruleSettings.hasBannedLocations) {
        newPieceColor = PieceColor.ban;
      } else {
        newPieceColor = PieceColor.none;
      }
    } else if (pieceColor == PieceColor.ban) {
      newPieceColor = PieceColor.none;
    } else if (pieceColor == PieceColor.none) {
      newPieceColor = PieceColor.white;
    } else {
      assert(false);
    }

    if (newPieceColor == PieceColor.none) {
      position.action = Act.remove;
    } else {
      position.action = Act.place;
    }

    if (newPieceColor == PieceColor.white ||
        newPieceColor == PieceColor.black) {
      // TODO: Duplicate: position/gameInstance.sideToMove
      MillController().position.sideToSetup = newPieceColor;
      MillController().gameInstance.sideToMove = newPieceColor;
    }

    MillController()
        .headerTipNotifier
        .showTip(newPieceColor.pieceName(context));
    MillController().headerIconsNotifier.showIcons();
    setState(() {});

    return;
  }

  setSetupPositionPhase(BuildContext context, Phase phase) {
    if (phase == Phase.placing) {
      newPhase = Phase.moving;
      MillController().headerTipNotifier.showTip(S.of(context).movingPhase);
    } else if (phase == Phase.moving) {
      newPhase = Phase.placing;
      MillController().headerTipNotifier.showTip(S.of(context).placingPhase);
    }

    setState(() {});
    return;
  }

  setSetupPositionNeedRemove(BuildContext context, int count) {
    // TODO: verify
    if (count == 0) {
      newPieceCountNeedRemove = 1;
    } else {
      if (DB().ruleSettings.mayRemoveMultiple) {
        if (count == 1) {
          newPieceCountNeedRemove = 2;
        } else if (count == 2) {
          newPieceCountNeedRemove = 3;
        } else if (count == 3) {
          newPieceCountNeedRemove = 0;
        }
      } else {
        newPieceCountNeedRemove = 0;
      }
    }

    MillController()
        .headerTipNotifier
        .showTip(newPieceCountNeedRemove.toString()); // TODO

    setState(() {});
    return;
  }

  setSetupPositionCopy(BuildContext context) async {
    //String str = S.of(context).moveHistoryCopied; // TODO: l10n

    String fen = MillController().position.fen;

    await Clipboard.setData(
      ClipboardData(text: MillController().position.fen),
    );

    rootScaffoldMessengerKey.currentState!.showSnackBarClear("Copy fen: $fen");
  }

  setSetupPositionPaste() {
    // TODO:
    return;
  }

  Future<void> setSetupPositionRemoval(BuildContext context) async {
    // TODO: l10n
    var selectValue = await showDialog<int?>(
      context: context,
      builder: (context) => const NumberPicker(
          start: 0, end: 4, newTitle: "Need to remove", showMoveString: false),
    );

    newPieceCountNeedRemove = selectValue ?? 0;

    if (newPhase == Phase.placing) {
      selectValue = await showDialog<int?>(
        context: context,
        builder: (context) => const NumberPicker(
            start: 0,
            end: 13, // TODO
            newTitle: "How many player1 pieces are removed?",
            showMoveString: false),
      );
      newWhitePieceRemovedInPlacingPhase = selectValue ?? 0;

      selectValue = await showDialog<int?>(
        context: context,
        builder: (context) => const NumberPicker(
            start: 0,
            end: 13, // TODO
            newTitle: "How many player2 pieces are removed?",
            showMoveString: false),
      );
      newBlackPieceRemovedInPlacingPhase = selectValue ?? 0;
    }

    return;
  }

  updateSetupPositionPiecesCount() {
    int w = MillController().position.countPieceOnBoard(PieceColor.white);
    int b = MillController().position.countPieceOnBoard(PieceColor.black);

    MillController().position.pieceOnBoardCount[PieceColor.white] = w;
    MillController().position.pieceOnBoardCount[PieceColor.black] = b;

    if (newPhase == Phase.placing) {
      MillController().position.pieceInHandCount[PieceColor.white] =
          DB().ruleSettings.piecesCount -
              w -
              newWhitePieceRemovedInPlacingPhase;
      MillController().position.pieceInHandCount[PieceColor.black] =
          DB().ruleSettings.piecesCount -
              b -
              newBlackPieceRemovedInPlacingPhase;
    } else if (newPhase == Phase.moving) {
      MillController().position.pieceInHandCount[PieceColor.white] =
          MillController().position.pieceInHandCount[PieceColor.black] = 0;
    } else {
      assert(false);
    }

    // TODO: Verify count in placing phase.
  }

  setSetupPositionDone() {
    // TODO: set position fen, such as piece ect.
    //MillController().gameInstance.gameMode = gameModeBackup;

    if (MillController().position.countPieceOnBoard(PieceColor.white) <
            DB().ruleSettings.piecesAtLeastCount ||
        MillController().position.countPieceOnBoard(PieceColor.black) <
            DB().ruleSettings.piecesAtLeastCount) {
      MillController().position.phase = Phase.placing;
    } else {
      MillController().position.phase = newPhase;
    }

    if (newPhase == Phase.placing) {
      MillController().position.action = Act.place;
    } else if (newPhase == Phase.moving) {
      MillController().position.action = Act.select;
    }

    if (newPieceColor != PieceColor.white &&
        newPieceColor != PieceColor.black) {
      newPieceColor = PieceColor.white; // TODO: Right?
    }

    // TODO: Two sideToMove
    MillController().gameInstance.sideToMove =
        MillController().position.sideToMove = newPieceColor;

    updateSetupPositionPiecesCount();

    MillController().isPositionSetup = true;

    //MillController().recorder.clear(); // TODO: Set and parse fen.
    MillController().recorder =
        GameRecorder(lastPositionWithRemove: position.fen);

    MillController().headerIconsNotifier.showIcons();
    MillController().boardSemanticsNotifier.updateSemantics();
  }

  @override
  Widget build(BuildContext context) {
    // Piece
    final whitePieceButton = ToolbarItem.icon(
      onPressed: () => setSetupPositionPiece(context, PieceColor.white),
      icon: Icon(FluentIcons.circle_24_filled,
          color: DB().colorSettings.whitePieceColor),
      label: Text(S.of(context).white),
    );
    final blackPieceButton = ToolbarItem.icon(
      onPressed: () => setSetupPositionPiece(context, PieceColor.black),
      icon: Icon(FluentIcons.circle_24_filled,
          color: DB().colorSettings.blackPieceColor),
      label: Text(S.of(context).black),
    );
    final banPointButton = ToolbarItem.icon(
      onPressed: () => setSetupPositionPiece(context, PieceColor.ban),
      icon: const Icon(FluentIcons.prohibited_24_regular),
      label: Text(S.of(context).banPoint), // TODO: l10n
    );
    final emptyPointButton = ToolbarItem.icon(
      onPressed: () => setSetupPositionPiece(context, PieceColor.none),
      icon: const Icon(FluentIcons.add_24_regular),
      label: Text(S.of(context).emptyPoint), // TODO: l10n
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
      onPressed: () => {setSetupPositionPhase(context, Phase.placing)},
      icon: const Icon(FluentIcons.grid_dots_24_regular),
      label: const Text("Placing"),
    );

    final movingButton = ToolbarItem.icon(
      onPressed: () => {setSetupPositionPhase(context, Phase.moving)},
      icon: const Icon(FluentIcons.arrow_move_24_regular),
      label: const Text("Moving"),
    );

    final removalButton = ToolbarItem.icon(
      onPressed: () => {setSetupPositionRemoval(context)},
      icon: const Icon(FluentIcons.text_word_count_24_regular),
      label: const Text("Removal"), // TODO: l10n
    );

    final copyButton = ToolbarItem.icon(
      onPressed: () => {setSetupPositionCopy(context)},
      icon: const Icon(FluentIcons.copy_24_regular),
      label: const Text("Copy"), // TODO: l10n
    );

    final pasteButton = ToolbarItem.icon(
      onPressed: () => {
        rootScaffoldMessengerKey.currentState!
            .showSnackBarClear(S.of(context).experimental)
      },
      icon: const Icon(FluentIcons.clipboard_paste_24_regular),
      label: const Text("Paste"), // TODO: l10n
    );

    // Cancel
    final cancelButton = ToolbarItem.icon(
      onPressed: () => {restoreContext()}, // TODO: setState();
      icon: const Icon(FluentIcons.dismiss_24_regular),
      label: Text(S.of(context).cancel),
    );

    final checkButton = ToolbarItem.icon(
      onPressed: () {
        rootScaffoldMessengerKey.currentState!
            .showSnackBarClear(S.of(context).experimental);
      },
      icon: const Icon(FluentIcons.hand_left_24_regular),
      label: const Text("Check"), // TODO: l10n
    );

    Map<PieceColor, ToolbarItem> colorButtonMap = {
      PieceColor.white: whitePieceButton,
      PieceColor.black: blackPieceButton,
      PieceColor.ban: banPointButton,
      PieceColor.none: emptyPointButton,
    };

    Map<Phase, ToolbarItem> phaseButtonMap = {
      Phase.ready: placingButton,
      Phase.placing: placingButton,
      Phase.moving: movingButton,
      Phase.gameOver: movingButton,
    };

    final rowOne = <Widget>[
      colorButtonMap[newPieceColor]!,
      phaseButtonMap[newPhase]!,
      removalButton,
      clearButton,
    ];

    final row2 = <Widget>[
      copyButton,
      pasteButton,
      cancelButton,
      checkButton,
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

  @override
  void dispose() {
    setSetupPositionDone();
    super.dispose();
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
