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

class SetupPositionToolBar extends StatefulWidget {
  const SetupPositionToolBar({super.key});

  @override
  State<SetupPositionToolBar> createState() => SetupPositionToolBarState();
}

class SetupPositionToolBarState extends State<SetupPositionToolBar> {
  final Color? backgroundColor = DB().colorSettings.mainToolbarBackgroundColor;
  final Color? itemColor = DB().colorSettings.mainToolbarIconColor;

  PieceColor newPieceColor = PieceColor.white;
  Phase newPhase = Phase.moving;
  int newPieceCountNeedRemove = 0;
  int newPlaced = 0; // For White

  late GameMode gameModeBackup;
  final Position position = MillController().position;
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

    if (newPhase == Phase.moving) {
      newPlaced = DB().ruleSettings.piecesCount;
    } else if (newPhase == Phase.placing) {
      /*
      int c = MillController().recorder.placeCount;

      if (MillController().position.sideToMove == PieceColor.white) {
        newPlaced = (c + 1) ~/ 2;
      } else if (MillController().position.sideToMove == PieceColor.black) {
        newPlaced = c ~/ 2;
      }
      */

      setSetupPositionPlacedUpdateBegin();
    }

    newPieceCountNeedRemove = MillController().position.pieceToRemoveCount;

    MillController().position.phase = newPhase;
    MillController().position.winner = PieceColor.nobody;

    // Zero rule50, and do not zero gamePly.
    MillController().position.st.rule50 = 0;

    //TODO: newWhitePieceRemovedInPlacingPhase & newBlackPieceRemovedInPlacingPhase;
  }

  void restoreContext() {
    MillController().position.copyWith(positionBackup);
    MillController().gameInstance.gameMode = gameModeBackup;
    _updateSetupPositionIcons();
    MillController().headerTipNotifier.showTip(S.of(context).restoredPosition);
  }

  @override
  void initState() {
    super.initState();
    MillController()
        .setupPositionNotifier
        .addListener(_updateSetupPositionIcons);
    initContext();
  }

  static const EdgeInsets _padding = EdgeInsets.symmetric(vertical: 2);
  static const EdgeInsets _margin = EdgeInsets.symmetric(vertical: 0.2);

  /// Gets the calculated height this widget adds to it's children.
  /// To get the absolute height add the surrounding [ButtonThemeData.height].
  static double get height => (_padding.vertical + _margin.vertical) * 2;

  void setSetupPositionPiece(BuildContext context, PieceColor pieceColor) {
    MillController().isPositionSetupBanPiece = false; // WAR

    if (pieceColor == PieceColor.white) {
      newPieceColor = PieceColor.black;
    } else if (pieceColor == PieceColor.black) {
      if (DB().ruleSettings.hasBannedLocations && newPhase == Phase.placing) {
        newPieceColor = PieceColor.ban;
        MillController().isPositionSetupBanPiece = true;
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

    _updateSetupPositionIcons();

    MillController()
        .headerTipNotifier
        .showTip(newPieceColor.pieceName(context));
    MillController().headerIconsNotifier.showIcons();
    setState(() {});

    return;
  }

  void setSetupPositionPhase(BuildContext context, Phase phase) {
    if (phase == Phase.placing) {
      newPhase = Phase.moving;

      if (newPieceColor == PieceColor.ban) {
        setSetupPositionPiece(context, newPieceColor); // Jump to next
      }

      newPlaced = DB().ruleSettings.piecesCount;

      MillController().headerTipNotifier.showTip(S.of(context).movingPhase);
    } else if (phase == Phase.moving) {
      newPhase = Phase.placing;
      newPlaced = setSetupPositionPlacedGetBegin();
      MillController().headerTipNotifier.showTip(S.of(context).placingPhase);
    }

    _updateSetupPositionIcons();

    setState(() {});

    return;
  }

  Future<void> setSetupPositionNeedRemove(int count, bool next) async {
    assert(MillController().position.sideToMove == PieceColor.white ||
        MillController().position.sideToMove == PieceColor.black);

    final PieceColor sideToMove = MillController().position.sideToMove;

    int limit = MillController()
        .position
        .totalMillsCount(MillController().position.sideToMove);

    final int opponentCount =
        MillController().position.countPieceOnBoard(sideToMove.opponent);

    if (newPhase == Phase.placing) {
      if (limit > opponentCount) {
        limit = opponentCount;
      }
    } else if (newPhase == Phase.moving) {
      final int newLimit =
          opponentCount - DB().ruleSettings.piecesAtLeastCount + 1;
      if (limit > newLimit) {
        limit = newLimit;
        limit = limit < 0 ? 0 : limit;
      }
    }

    if (DB().ruleSettings.mayRemoveMultiple == false) {
      if (limit > 1) {
        limit = 1;
      }
    }

    if (next == true) {
      newPieceCountNeedRemove = count + 1;
    }

    if (newPieceCountNeedRemove > limit) {
      newPieceCountNeedRemove = 0;
    }

    MillController().position.pieceToRemoveCount = newPieceCountNeedRemove;

    if (next == true) {
      if (limit == 0 || newPieceCountNeedRemove == 0) {
        MillController()
            .headerTipNotifier
            .showTip(S.of(context).noPiecesCanBeRemoved);
      } else {
        MillController().headerTipNotifier.showTip(
            S.of(context).pieceCountNeedToRemove(newPieceCountNeedRemove));
      }
    }

    if (mounted) {
      setState(() {});
    }

    return;
  }

  Future<void> setSetupPositionCopy(BuildContext context) async {
    setSetupPositionDone();

    final String fen = MillController().position.fen;
    final String copyStr = S.of(context).copy;

    await Clipboard.setData(
      ClipboardData(text: MillController().position.fen),
    );

    if (mounted) {
      setState(() {});
    }

    rootScaffoldMessengerKey.currentState!
        .showSnackBarClear("$copyStr FEN: $fen");
  }

  Future<void> setSetupPositionPaste(BuildContext context) async {
    final String tipFailed = S.of(context).cannotPaste;
    final String tipDone = S.of(context).pasteDone;

    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);

    if (data?.text == null) {
      return;
    }

    final String fen = data!.text!;

    try {
      if (MillController().position.setFen(fen) == true) {
        MillController().headerTipNotifier.showTip(tipDone);
        initContext();
        _updateSetupPositionIcons();
        rootScaffoldMessengerKey.currentState!.showSnackBarClear("FEN: $fen");
      } else {
        MillController().headerTipNotifier.showTip(tipFailed);
      }
    } catch (e) {
      MillController().headerTipNotifier.showTip(tipFailed);
    }

    return;
  }

  int setSetupPositionPlacedGetBegin() {
    if (newPhase == Phase.moving) {
      return DB().ruleSettings.piecesCount;
    }

    final int white =
        MillController().position.countPieceOnBoard(PieceColor.white);
    final int black =
        MillController().position.countPieceOnBoard(PieceColor.black);
    late int begin;

    // TODO: Not accurate enough.
    //  If the difference between the number of pieces on the two sides is large,
    //  then it means that more values should be subtracted.
    if (DB().ruleSettings.hasBannedLocations) {
      //int ban = MillController().position.countPieceOnBoard(PieceColor.ban);
      begin = max(white, black); // TODO: How to use ban?
    } else {
      begin = max(white, black);
    }

    if (MillController().position.sideToMove == PieceColor.black &&
        white > black) {
      begin--;
    }

    return begin;
  }

  void setSetupPositionPlacedUpdateBegin() {
    final int val = setSetupPositionPlacedGetBegin();

    newPlaced = val;
    /*
    if (newPlaced > val) { // TODO: > or < ? How to Update?
      newPlaced =
          val; // TODO: So does it still make sense to read the length of the move list in initContext?
    }
    */

    if (mounted) {
      setState(() {});
    }
  }

  // TODO: Duplicate with InfoDialog._infoText
  String _infoText(BuildContext context) {
    final MillController controller = MillController();
    final StringBuffer buffer = StringBuffer();
    final Position pos = controller.position;

    late final String us;
    late final String them;
    switch (pos.sideToMove) {
      case PieceColor.white:
        us = S.of(context).player1;
        them = S.of(context).player2;
        break;
      case PieceColor.black:
        us = S.of(context).player2;
        them = S.of(context).player1;
        break;
      case PieceColor.ban:
      case PieceColor.draw:
      case PieceColor.none:
      case PieceColor.nobody:
        break;
    }

    buffer.write(pos.phase.getName(context));

    if (DB().generalSettings.screenReaderSupport) {
      buffer.writeln(":");
    } else {
      buffer.writeln();
    }

    final String? n1 = controller.recorder.current?.notation;
    // Last Move information
    if (n1 != null) {
      // $them is only shown with the screen reader. It is convenient for
      // the disabled to recognize whether the opponent has finished the moving.
      buffer.write(
        S.of(context).lastMove(
              DB().generalSettings.screenReaderSupport ? "$them, " : "",
            ),
      );

      if (n1.startsWith("x")) {
        buffer.writeln(
          controller.recorder[controller.recorder.length - 2].notation,
        );
      }
      buffer.writeComma(n1);
    }

    buffer.writePeriod(S.of(context).sideToMove(us));

    final String msg = MillController().headerTipNotifier.message;

    // the tip
    if (DB().generalSettings.screenReaderSupport &&
        msg.endsWith(".") &&
        msg.endsWith("!")) {
      buffer.writePeriod(msg);
    }

    buffer.writeln();
    buffer.writeln(S.of(context).pieceCount);
    buffer.writeComma(
      S.of(context).inHand(
            S.of(context).player1,
            pos.pieceInHandCount[PieceColor.white]!,
          ),
    );
    buffer.writeComma(
      S.of(context).inHand(
            S.of(context).player2,
            pos.pieceInHandCount[PieceColor.black]!,
          ),
    );
    buffer.writeComma(
      S.of(context).onBoard(
            S.of(context).player1,
            pos.pieceOnBoardCount[PieceColor.white]!,
          ),
    );
    buffer.writePeriod(
      S.of(context).onBoard(
            S.of(context).player2,
            pos.pieceOnBoardCount[PieceColor.black]!,
          ),
    );

    return buffer.toString();
  }

  Future<void> setSetupPositionPlaced(BuildContext context) async {
    void callback(int? placed) {
      newPlaced = placed!;
      updateSetupPositionPiecesCount();
      Navigator.pop(context);
      setState(() {});
      MillController().headerTipNotifier.showTip(
          S.of(context).hasPlacedPieceCount(newPlaced),
          snackBar: false); // TODO: How to show side to move?

      rootScaffoldMessengerKey.currentState!.showSnackBar(CustomSnackBar(
          _infoText(context),
          duration: const Duration(seconds: 6)));
    }

    if (newPhase != Phase.placing) {
      MillController().headerTipNotifier.showTip(S.of(context).notPlacingPhase);
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _PlacedModal(
        placedGroupValue: newPlaced, // TODO: placedGroupValue should be?
        onChanged: callback,
        begin: setSetupPositionPlacedGetBegin(),
      ),
    );
  }

  void _updateSetupPositionIcons() {
    setSetupPositionPlacedUpdateBegin();
    setSetupPositionNeedRemove(newPieceCountNeedRemove, false);
    updateSetupPositionPiecesCount();
    MillController().headerIconsNotifier.showIcons();
  }

  void updateSetupPositionPiecesCount() {
    final int w = MillController().position.countPieceOnBoard(PieceColor.white);
    final int b = MillController().position.countPieceOnBoard(PieceColor.black);

    MillController().position.pieceOnBoardCount[PieceColor.white] = w;
    MillController().position.pieceOnBoardCount[PieceColor.black] = b;

    final int piecesCount = DB().ruleSettings.piecesCount;

    // TODO: Update dynamically
    if (newPhase == Phase.placing) {
      MillController().position.pieceInHandCount[PieceColor.black] =
          piecesCount - newPlaced;
      if (MillController().position.sideToMove == PieceColor.white) {
        MillController().position.pieceInHandCount[PieceColor.white] =
            MillController().position.pieceInHandCount[PieceColor.black]!;
      } else if (MillController().position.sideToMove == PieceColor.black) {
        MillController().position.pieceInHandCount[PieceColor.white] =
            MillController().position.pieceInHandCount[PieceColor.black]! - 1;
      } else {
        assert(false);
      }
    } else if (newPhase == Phase.moving) {
      MillController().position.pieceInHandCount[PieceColor.white] =
          MillController().position.pieceInHandCount[PieceColor.black] = 0;
    } else {
      assert(false);
    }

    // TODO: Verify count in placing phase.
  }

  void setSetupPositionDone() {
    // TODO: set position fen, such as piece etc.
    //MillController().gameInstance.gameMode = gameModeBackup;

    // When the number of pieces is less than 3, it is impossible to be in the Moving Phase.
    if (MillController().position.countPieceOnBoard(PieceColor.white) <
            DB().ruleSettings.piecesAtLeastCount ||
        MillController().position.countPieceOnBoard(PieceColor.black) <
            DB().ruleSettings.piecesAtLeastCount) {
      newPhase = Phase.placing;
    }

    MillController().position.phase = newPhase;

    // Setup the Action.
    if (newPhase == Phase.placing) {
      MillController().position.action = Act.place;
    } else if (newPhase == Phase.moving) {
      MillController().position.action = Act.select;
    }

    // Correct newPieceColor and set sideToMove
    if (newPieceColor != PieceColor.white &&
        newPieceColor != PieceColor.black) {
      newPieceColor = PieceColor.white; // TODO: Right?
    }

    // TODO: Two sideToMove
    MillController().gameInstance.sideToMove =
        MillController().position.sideToMove = newPieceColor;

    updateSetupPositionPiecesCount();

    //MillController().recorder.clear(); // TODO: Set and parse fen.
    final String fen = position.fen;
    MillController().recorder =
        GameRecorder(lastPositionWithRemove: fen, setupPosition: fen);

    MillController().headerIconsNotifier.showIcons();
    MillController().boardSemanticsNotifier.updateSemantics();
  }

  @override
  Widget build(BuildContext context) {
    // Piece
    final ToolbarItem whitePieceButton = ToolbarItem.icon(
      onPressed: () => setSetupPositionPiece(context, PieceColor.white),
      icon: Icon(FluentIcons.circle_24_filled,
          color: DB().colorSettings.whitePieceColor),
      label: Text(S.of(context).white),
    );
    final ToolbarItem blackPieceButton = ToolbarItem.icon(
      onPressed: () => setSetupPositionPiece(context, PieceColor.black),
      icon: Icon(FluentIcons.circle_24_filled,
          color: DB().colorSettings.blackPieceColor),
      label: Text(S.of(context).black),
    );
    final ToolbarItem banPointButton = ToolbarItem.icon(
      onPressed: () => setSetupPositionPiece(context, PieceColor.ban),
      icon: const Icon(FluentIcons.prohibited_24_regular),
      label: Text(S.of(context).ban),
    );
    final ToolbarItem emptyPointButton = ToolbarItem.icon(
      onPressed: () => setSetupPositionPiece(context, PieceColor.none),
      icon: const Icon(FluentIcons.add_24_regular),
      label: Text(S.of(context).empty),
    );

    // Clear
    final ToolbarItem clearButton = ToolbarItem.icon(
      onPressed: () {
        MillController().position.reset();
        _updateSetupPositionIcons();
        MillController().headerTipNotifier.showTip(S.of(context).cleanedUp);
      },
      icon: const Icon(FluentIcons.eraser_24_regular),
      label: Text(S.of(context).clean),
    );

    // Phase
    final ToolbarItem placingButton = ToolbarItem.icon(
      onPressed: () => <void>{setSetupPositionPhase(context, Phase.placing)},
      icon: const Icon(FluentIcons.grid_dots_24_regular),
      label: Text(S.of(context).placing),
    );

    final ToolbarItem movingButton = ToolbarItem.icon(
      onPressed: () => <void>{setSetupPositionPhase(context, Phase.moving)},
      icon: const Icon(FluentIcons.arrow_move_24_regular),
      label: Text(S.of(context).moving),
    );

    // Remove
    final ToolbarItem removeZeroButton = ToolbarItem.icon(
      onPressed: () => <void>{setSetupPositionNeedRemove(0, true)},
      icon: const Icon(FluentIcons.circle_24_regular),
      label: Text(S.of(context).remove),
    );

    final ToolbarItem removeOneButton = ToolbarItem.icon(
      onPressed: () => <void>{setSetupPositionNeedRemove(1, true)},
      icon: const Icon(FluentIcons.number_circle_1_24_regular),
      label: Text(S.of(context).remove),
    );

    final ToolbarItem removeTwoButton = ToolbarItem.icon(
      onPressed: () => <void>{setSetupPositionNeedRemove(2, true)},
      icon: const Icon(FluentIcons.number_circle_2_24_regular),
      label: Text(S.of(context).remove),
    );

    final ToolbarItem removeThreeButton = ToolbarItem.icon(
      onPressed: () => <void>{setSetupPositionNeedRemove(3, true)},
      icon: const Icon(FluentIcons.number_circle_3_24_regular),
      label: Text(S.of(context).remove),
    );

    final ToolbarItem placedButton = ToolbarItem.icon(
      onPressed: () => <void>{setSetupPositionPlaced(context)},
      icon: const Icon(FluentIcons.text_word_count_24_regular),
      label: Text(S.of(context).placedCount(newPlaced.toString())),
    );

    final ToolbarItem copyButton = ToolbarItem.icon(
      onPressed: () => <void>{setSetupPositionCopy(context)},
      icon: const Icon(FluentIcons.copy_24_regular),
      label: Text(S.of(context).copy),
    );

    final ToolbarItem pasteButton = ToolbarItem.icon(
      onPressed: () => <void>{setSetupPositionPaste(context)},
      icon: const Icon(FluentIcons.clipboard_paste_24_regular),
      label: Text(S.of(context).paste),
    );

    // Cancel
    final ToolbarItem cancelButton = ToolbarItem.icon(
      onPressed: () => <void>{restoreContext()}, // TODO: setState();
      icon: const Icon(FluentIcons.dismiss_24_regular),
      label: Text(S.of(context).cancel),
    );

    final Map<PieceColor, ToolbarItem> colorButtonMap =
        <PieceColor, ToolbarItem>{
      PieceColor.white: whitePieceButton,
      PieceColor.black: blackPieceButton,
      PieceColor.ban: banPointButton,
      PieceColor.none: emptyPointButton,
    };

    final Map<Phase, ToolbarItem> phaseButtonMap = <Phase, ToolbarItem>{
      Phase.ready: placingButton,
      Phase.placing: placingButton,
      Phase.moving: movingButton,
      Phase.gameOver: movingButton,
    };

    final Map<int, ToolbarItem> removeButtonMap = <int, ToolbarItem>{
      0: removeZeroButton,
      1: removeOneButton,
      2: removeTwoButton,
      3: removeThreeButton,
    };

    final List<Widget> rowOne = <Widget>[
      colorButtonMap[newPieceColor]!,
      phaseButtonMap[newPhase]!,
      removeButtonMap[newPieceCountNeedRemove]!,
      placedButton,
    ];

    final List<Widget> row2 = <Widget>[
      copyButton,
      pasteButton,
      clearButton,
      cancelButton,
    ];

    return Column(
      children: <Widget>[
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
    MillController()
        .setupPositionNotifier
        .addListener(_updateSetupPositionIcons);
    setSetupPositionDone();
    super.dispose();
  }
}

class SetupPositionButtonsContainer extends StatelessWidget {
  const SetupPositionButtonsContainer({
    super.key,
    required this.backgroundColor,
    required EdgeInsets margin,
    required EdgeInsets padding,
    required this.itemColor,
    required this.child,
  })  : _margin = margin,
        _padding = padding;

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

class _PlacedModal extends StatelessWidget {
  const _PlacedModal({
    required this.placedGroupValue,
    required this.onChanged,
    required this.begin,
  });

  final int placedGroupValue;
  final Function(int?)? onChanged;

  final int begin;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: S.of(context).placedPieceCount,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = begin; i <= DB().ruleSettings.piecesCount; i++)
              RadioListTile<int>(
                title: Text(i.toString()),
                groupValue: placedGroupValue,
                value: i,
                onChanged: onChanged,
              ),
          ],
        ),
      ),
    );
  }
}
