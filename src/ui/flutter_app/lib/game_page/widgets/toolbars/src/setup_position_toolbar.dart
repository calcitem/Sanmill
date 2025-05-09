// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// setup_position_toolbar.dart

part of '../game_toolbar.dart';

class SetupPositionToolbar extends StatefulWidget {
  const SetupPositionToolbar({super.key});

  @override
  State<SetupPositionToolbar> createState() => SetupPositionToolbarState();
}

class SetupPositionToolbarState extends State<SetupPositionToolbar> {
  final Color? backgroundColor = DB().colorSettings.mainToolbarBackgroundColor;
  final Color? itemColor = DB().colorSettings.mainToolbarIconColor;

  PieceColor newPieceColor = PieceColor.white;
  Phase newPhase = Phase.moving;
  Map<PieceColor, int> newPieceCountNeedRemove = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
  };
  int newPlaced = 0; // For White

  late GameMode gameModeBackup;
  final Position position = GameController().position;
  late Position positionBackup;

  void initContext() {
    gameModeBackup = GameController().gameInstance.gameMode;
    GameController().gameInstance.gameMode = GameMode.setupPosition;

    positionBackup = GameController().position.clone();
    //GameController().position.reset();

    newPieceColor = GameController().position.sideToMove;

    if (GameController().position.countPieceOnBoard(PieceColor.white) +
            GameController().position.countPieceOnBoard(PieceColor.black) ==
        0) {
      newPhase = Phase.moving;
    } else {
      if (GameController().position.phase == Phase.moving) {
        newPhase = Phase.moving;
      } else if (GameController().position.phase == Phase.ready ||
          GameController().position.phase == Phase.placing) {
        newPhase = Phase.placing;
      } else if (GameController().position.phase == Phase.gameOver) {
        if (GameController().gameRecorder.mainlineMoves.length >
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
      int c = GameController().recorder.placeCount;

      if (GameController().position.sideToMove == PieceColor.white) {
        newPlaced = (c + 1) ~/ 2;
      } else if (GameController().position.sideToMove == PieceColor.black) {
        newPlaced = c ~/ 2;
      }
      */

      setSetupPositionPlacedUpdateBegin();
    }

    newPieceCountNeedRemove[PieceColor.white] =
        GameController().position.pieceToRemoveCount[PieceColor.white]!;
    newPieceCountNeedRemove[PieceColor.black] =
        GameController().position.pieceToRemoveCount[PieceColor.black]!;

    GameController().position.phase = newPhase;
    GameController().position.winner = PieceColor.nobody;

    // Zero rule50, and do not zero gamePly.
    GameController().position.st.rule50 = 0;

    //TODO: newWhitePieceRemovedInPlacingPhase & newBlackPieceRemovedInPlacingPhase;
  }

  void restoreContext() {
    GameController().position.copyWith(positionBackup);
    GameController().gameInstance.gameMode = gameModeBackup;
    _updateSetupPositionIcons();
    GameController().headerTipNotifier.showTip(S.of(context).restoredPosition);
  }

  @override
  void initState() {
    super.initState();
    GameController()
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
    GameController().isPositionSetupMarkedPiece = false; // WAR

    if (pieceColor == PieceColor.white) {
      newPieceColor = PieceColor.black;
    } else if (pieceColor == PieceColor.black) {
      if (DB().ruleSettings.millFormationActionInPlacingPhase ==
              MillFormationActionInPlacingPhase.markAndDelayRemovingPieces &&
          newPhase == Phase.placing) {
        newPieceColor = PieceColor.marked;
        GameController().isPositionSetupMarkedPiece = true;
      } else {
        newPieceColor = PieceColor.none;
      }
    } else if (pieceColor == PieceColor.marked) {
      newPieceColor = PieceColor.none;
    } else if (pieceColor == PieceColor.none) {
      newPieceColor = PieceColor.white;
    } else {
      logger.e("Invalid pieceColor: $pieceColor");
    }

    if (newPieceColor == PieceColor.none) {
      position.action = Act.remove;
    } else {
      position.action = Act.place;
    }

    if (newPieceColor == PieceColor.white ||
        newPieceColor == PieceColor.black) {
      // TODO: Duplicate: position/gameInstance.sideToMove
      GameController().position.sideToSetup = newPieceColor;
      GameController().position.sideToMove = newPieceColor;
    }

    _updateSetupPositionIcons();

    GameController()
        .headerTipNotifier
        .showTip(newPieceColor.pieceName(context));
    GameController().headerIconsNotifier.showIcons();
    setState(() {});

    return;
  }

  void setSetupPositionPhase(BuildContext context, Phase phase) {
    if (phase == Phase.placing) {
      newPhase = Phase.moving;

      if (newPieceColor == PieceColor.marked) {
        setSetupPositionPiece(context, newPieceColor); // Jump to next
      }

      newPlaced = DB().ruleSettings.piecesCount;

      GameController().headerTipNotifier.showTip(S.of(context).movingPhase);
    } else if (phase == Phase.moving) {
      newPhase = Phase.placing;
      newPlaced = setSetupPositionPlacedGetBegin();
      GameController().headerTipNotifier.showTip(S.of(context).placingPhase);
    }

    _updateSetupPositionIcons();

    setState(() {});

    return;
  }

  Future<void> setSetupPositionNeedRemove(int count, bool next) async {
    assert(GameController().position.sideToMove == PieceColor.white ||
        GameController().position.sideToMove == PieceColor.black);

    if (newPieceColor != PieceColor.white &&
        newPieceColor != PieceColor.black) {
      return;
    }

    final PieceColor sideToMove = GameController().position.sideToMove;

    int limit = GameController()
        .position
        .totalMillsCount(GameController().position.sideToMove);

    final int opponentCount =
        GameController().position.countPieceOnBoard(sideToMove.opponent);

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

    if (DB().ruleSettings.mayRemoveMultiple == false && limit > 1 ||
        newPhase == Phase.moving &&
            GameController().position.isStalemateRemoval(newPieceColor) ==
                true) {
      limit = 1;
    }

    if (next == true) {
      newPieceCountNeedRemove[newPieceColor] = count + 1;
    }

    if (newPieceCountNeedRemove[newPieceColor]! > limit) {
      newPieceCountNeedRemove[newPieceColor] = 0;
    }

    // TODO: BoardFullAction: Not adapted
    newPieceCountNeedRemove[newPieceColor.opponent] = 0;
    GameController().position.pieceToRemoveCount[newPieceColor.opponent] = 0;

    GameController().position.pieceToRemoveCount[newPieceColor] =
        newPieceCountNeedRemove[newPieceColor]!;

    if (DB().ruleSettings.millFormationActionInPlacingPhase ==
        MillFormationActionInPlacingPhase.removalBasedOnMillCounts) {
      // TODO: Adapt removalBasedOnMillCounts
      // final int whiteMills = GameController().position.totalMillsCount(PieceColor.white);
      // final int blackMills = GameController().position.totalMillsCount(PieceColor.black);
    }

    if (next == true) {
      if (limit == 0 || newPieceCountNeedRemove[newPieceColor] == 0) {
        GameController()
            .headerTipNotifier
            .showTip(S.of(context).noPiecesCanBeRemoved);
      } else {
        GameController().headerTipNotifier.showTip(S
            .of(context)
            .pieceCountNeedToRemove(newPieceCountNeedRemove[newPieceColor]!));
      }
    }

    if (mounted) {
      setState(() {});
    }

    return;
  }

  Future<void> setSetupPositionCopy(BuildContext context) async {
    if (setSetupPositionDone() == false) {
      rootScaffoldMessengerKey.currentState!
          .showSnackBarClear(S.of(context).invalidPosition);
      return;
    }

    final String? fen = GameController().position.fen;
    final String copyStr = S.of(context).copy;

    if (fen != null) {
      await Clipboard.setData(
        ClipboardData(text: fen),
      );
    } else {
      logger.e("FEN is null.");
    }

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
      if (GameController().position.setFen(fen) == true) {
        GameController().headerTipNotifier.showTip(tipDone);
        initContext();
        _updateSetupPositionIcons();
        rootScaffoldMessengerKey.currentState!.showSnackBarClear("FEN: $fen");
      } else {
        GameController().headerTipNotifier.showTip(tipFailed);
      }
    } catch (e) {
      GameController().headerTipNotifier.showTip(tipFailed);
    }

    return;
  }

  Future<void> setSetupPositionTransform(
      BuildContext context, TransformationType transformationType) async {
    final String? fen = GameController().position.fen;

    if (fen == null) {
      logger.e("FEN is null.");
      GameController().headerTipNotifier.showTip(S.of(context).cannotTransform);
      return;
    }

    transformSquareSquareAttributeList(transformationType);

    final String transformedFen = transformFEN(fen, transformationType);

    try {
      if (GameController().position.setFen(transformedFen) == true) {
        GameController().headerTipNotifier.showTip(S.of(context).transformed);
        initContext();
        _updateSetupPositionIcons();
      } else {
        GameController()
            .headerTipNotifier
            .showTip(S.of(context).cannotTransform);
      }
    } catch (e) {
      GameController().headerTipNotifier.showTip(S.of(context).cannotTransform);
    }

    if (mounted) {
      setState(() {});
    }
  }

  int setSetupPositionPlacedGetBegin() {
    if (newPhase == Phase.moving) {
      return DB().ruleSettings.piecesCount;
    }

    final int white =
        GameController().position.countPieceOnBoard(PieceColor.white);
    final int black =
        GameController().position.countPieceOnBoard(PieceColor.black);
    late int begin;

    // TODO: Not accurate enough.
    //  If the difference between the number of pieces on the two sides is large,
    //  then it means that more values should be subtracted.
    if (DB().ruleSettings.millFormationActionInPlacingPhase ==
        MillFormationActionInPlacingPhase.markAndDelayRemovingPieces) {
      //int marked = GameController().position.countPieceOnBoard(PieceColor.marked);
      begin = max(white, black); // TODO: How to use marked?
    } else {
      begin = max(white, black);
    }

    if (GameController().position.sideToMove == PieceColor.black &&
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
    final GameController controller = GameController();
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
      case PieceColor.marked:
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

    final String? n1 = controller.gameRecorder.activeNode?.data?.notation;
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
          controller
              .gameRecorder
              .mainlineMoves[controller.gameRecorder.mainlineMoves.length - 2]
              .notation,
        );
      }
      buffer.writeComma(n1);
    }

    buffer.writePeriod(S.of(context).sideToMove(us));

    final String msg = GameController().headerTipNotifier.message;

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
      setState(() {});
      GameController().headerTipNotifier.showTip(
          S.of(context).hasPlacedPieceCount(newPlaced),
          snackBar: false); // TODO: How to show side to move?

      rootScaffoldMessengerKey.currentState!.showSnackBar(CustomSnackBar(
          _infoText(context),
          duration: const Duration(seconds: 6)));

      Navigator.pop(context);
    }

    if (newPhase != Phase.placing) {
      GameController().headerTipNotifier.showTip(S.of(context).notPlacingPhase);
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
    if (newPieceColor == PieceColor.white ||
        newPieceColor == PieceColor.black) {
      setSetupPositionNeedRemove(
          newPieceCountNeedRemove[newPieceColor]!, false);
    }
    updateSetupPositionPiecesCount();
    GameController().headerIconsNotifier.showIcons();
    GameController().boardSemanticsNotifier.updateSemantics();
  }

  void updateSetupPositionPiecesCount() {
    final int w = GameController().position.countPieceOnBoard(PieceColor.white);
    final int b = GameController().position.countPieceOnBoard(PieceColor.black);

    GameController().position.pieceOnBoardCount[PieceColor.white] = w;
    GameController().position.pieceOnBoardCount[PieceColor.black] = b;

    final int piecesCount = DB().ruleSettings.piecesCount;

    // TODO: Update dynamically and adapt BoardFullAction = 1
    if (newPhase == Phase.placing) {
      GameController().position.pieceInHandCount[PieceColor.black] =
          piecesCount - newPlaced;
      if (GameController().position.pieceInHandCount[PieceColor.black]! < 0) {
        logger.e("Error: pieceInHandCount[black] < 0");
        GameController().position.pieceInHandCount[PieceColor.black] = 0;
      }
      if (GameController().position.sideToMove == PieceColor.white) {
        GameController().position.pieceInHandCount[PieceColor.white] =
            GameController().position.pieceInHandCount[PieceColor.black]!;
        if (GameController().position.pieceInHandCount[PieceColor.white]! < 0) {
          logger.e("Error: pieceInHandCount[white] < 0");
          GameController().position.pieceInHandCount[PieceColor.white] = 0;
        }
      } else if (GameController().position.sideToMove == PieceColor.black) {
        GameController().position.pieceInHandCount[PieceColor.white] =
            GameController().position.pieceInHandCount[PieceColor.black]! - 1;
        if (GameController().position.pieceInHandCount[PieceColor.white]! < 0) {
          logger.e("Error: pieceInHandCount[white] < 0");
          GameController().position.pieceInHandCount[PieceColor.white] = 0;
        }
      } else {
        logger.e("Error: sideToMove is not white or black");
      }
    } else if (newPhase == Phase.moving) {
      if (DB().ruleSettings.millFormationActionInPlacingPhase ==
              MillFormationActionInPlacingPhase
                  .removeOpponentsPieceFromHandThenYourTurn ||
          DB().ruleSettings.millFormationActionInPlacingPhase ==
              MillFormationActionInPlacingPhase
                  .removeOpponentsPieceFromHandThenOpponentsTurn) {
        // TODO: Right?
        GameController().position.pieceInHandCount[newPieceColor] = 0;
      } else {
        GameController().position.pieceInHandCount[PieceColor.white] =
            GameController().position.pieceInHandCount[PieceColor.black] = 0;
      }
    } else {
      logger.e("Error: Invalid phase");
    }

    // TODO: Verify count in placing phase.
  }

  bool setSetupPositionDone() {
    // TODO: set position fen, such as piece etc.
    //GameController().gameInstance.gameMode = gameModeBackup;

    // When the number of pieces is less than 3, it is impossible to be in the Moving Phase.
    if (GameController().position.countPieceOnBoard(PieceColor.white) <
            DB().ruleSettings.piecesAtLeastCount ||
        GameController().position.countPieceOnBoard(PieceColor.black) <
            DB().ruleSettings.piecesAtLeastCount) {
      newPhase = Phase.placing;
    }

    GameController().position.phase = newPhase;

    // Setup the Action.
    if (newPhase == Phase.placing) {
      GameController().position.action = Act.place;
    } else if (newPhase == Phase.moving) {
      GameController().position.action = Act.select;
    }

    if (GameController()
            .position
            .pieceToRemoveCount[GameController().position.sideToMove]!
            .abs() >
        0) {
      GameController().position.action = Act.remove;
    }

    // Correct newPieceColor and set sideToMove
    if (newPieceColor != PieceColor.white &&
        newPieceColor != PieceColor.black) {
      newPieceColor = PieceColor.white; // TODO: Right?
    }

    GameController().position.sideToMove = newPieceColor;

    updateSetupPositionPiecesCount();

    // TODO: WAR patch. Specifically for the initial position.
    //  The position is illegal after switching to the Setup Position
    //  and then switching back.
    if (GameController().position.pieceOnBoardCount[PieceColor.white]! <= 0 &&
        GameController().position.pieceOnBoardCount[PieceColor.black]! <= 0 &&
        GameController().position.pieceInHandCount[PieceColor.white]! <= 0 &&
        GameController().position.pieceInHandCount[PieceColor.black]! <= 0) {
      newPlaced = 0;
      newPhase = Phase.placing;
      newPieceCountNeedRemove[PieceColor.white] =
          newPieceCountNeedRemove[PieceColor.black] = 0;

      GameController().position.pieceOnBoardCount[PieceColor.white] =
          GameController().position.pieceOnBoardCount[PieceColor.black] = 0;
      GameController().position.pieceInHandCount[PieceColor.white] =
          GameController().position.pieceInHandCount[PieceColor.black] =
              DB().ruleSettings.piecesCount;
      // Note: _updateSetupPositionIcons -> setSetupPositionNeedRemove use newPieceCountNeedRemove to update pieceCountNeedRemove before, so maybe it it not need to do this.
      GameController().position.pieceToRemoveCount[PieceColor.white] =
          GameController().position.pieceToRemoveCount[PieceColor.black] = 0;

      GameController().reset(force: true);
    }

    //GameController().recorder.clear(); // TODO: Set and parse fen.
    final String? fen = position.fen;
    if (fen == null) {
      logger.e("FEN is null.");
      return false;
    }

    if (GameController().position.validateFen(fen) == false) {
      logger.e("Invalid FEN: $fen");
      return false;
    }

    GameController().gameRecorder =
        GameRecorder(lastPositionWithRemove: fen, setupPosition: fen);

    GameController().headerIconsNotifier.showIcons();
    GameController().boardSemanticsNotifier.updateSemantics();

    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Piece
    final ToolbarItem whitePieceButton = ToolbarItem.icon(
      key: const Key('white_piece_button'),
      onPressed: () => setSetupPositionPiece(context, PieceColor.white),
      icon: Icon(
        FluentIcons.circle_24_filled,
        color: (DB().colorSettings.mainToolbarBackgroundColor == Colors.white &&
                DB().colorSettings.whitePieceColor == Colors.white)
            ? Colors.grey[
                300] // Set to grey for better visibility if background is white
            : DB().colorSettings.whitePieceColor,
      ),
      label: Text(
        S.of(context).white,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    final ToolbarItem blackPieceButton = ToolbarItem.icon(
      key: const Key('black_piece_button'),
      onPressed: () => setSetupPositionPiece(context, PieceColor.black),
      icon: Icon(FluentIcons.circle_24_filled,
          color: DB().colorSettings.blackPieceColor),
      label: Text(
        S.of(context).black,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    final ToolbarItem markedPointButton = ToolbarItem.icon(
      key: const Key('marked_point_button'),
      onPressed: () => setSetupPositionPiece(context, PieceColor.marked),
      icon: const Icon(FluentIcons.prohibited_24_regular),
      label: Text(
        S.of(context).marked,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    final ToolbarItem emptyPointButton = ToolbarItem.icon(
      key: const Key('empty_point_button'),
      onPressed: () => setSetupPositionPiece(context, PieceColor.none),
      icon: const Icon(FluentIcons.add_24_regular),
      label: Text(
        S.of(context).empty,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    // Rotate
    final ToolbarItem rotateButton = ToolbarItem.icon(
      key: const Key('rotate_button'),
      onPressed: () => setSetupPositionTransform(
          context, TransformationType.rotate90Degrees),
      icon: const Icon(FluentIcons.arrow_rotate_clockwise_24_regular),
      label: Text(
        S.of(context).rotate,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    // Horizontal Flip
    final ToolbarItem horizontalFlipButton = ToolbarItem.icon(
      key: const Key('horizontal_flip_button'),
      onPressed: () =>
          setSetupPositionTransform(context, TransformationType.horizontalFlip),
      icon: const Icon(FluentIcons.flip_horizontal_24_regular),
      label: Text(
        S.of(context).horizontalFlip,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    // Vertical Flip
    final ToolbarItem verticalFlipButton = ToolbarItem.icon(
      key: const Key('vertical_flip_button'),
      onPressed: () =>
          setSetupPositionTransform(context, TransformationType.verticalFlip),
      icon: const Icon(FluentIcons.flip_vertical_24_regular),
      label: Text(
        S.of(context).verticalFlip,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    // Inner Outer Flip
    final ToolbarItem innerOuterFlipButton = ToolbarItem.icon(
      key: const Key('inner_outer_flip_button'),
      onPressed: () =>
          setSetupPositionTransform(context, TransformationType.innerOuterFlip),
      icon: const Icon(FluentIcons.arrow_expand_24_regular),
      label: Text(
        S.of(context).innerOuterFlip,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    // Clear
    final ToolbarItem clearButton = ToolbarItem.icon(
      key: const Key('clear_button'),
      onPressed: () {
        GameController().position.reset();
        _updateSetupPositionIcons();
        GameController().headerTipNotifier.showTip(S.of(context).cleanedUp);
      },
      icon: const Icon(FluentIcons.eraser_24_regular),
      label: Text(
        S.of(context).clean,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    // Phase
    final ToolbarItem placingButton = ToolbarItem.icon(
      key: const Key('placing_button'),
      onPressed: () => <void>{setSetupPositionPhase(context, Phase.placing)},
      icon: const Icon(FluentIcons.grid_dots_24_regular),
      label: Text(
        S.of(context).placing,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final ToolbarItem movingButton = ToolbarItem.icon(
      key: const Key('moving_button'),
      onPressed: () => <void>{setSetupPositionPhase(context, Phase.moving)},
      icon: const Icon(FluentIcons.arrow_move_24_regular),
      label: Text(
        S.of(context).moving,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    // Remove
    final ToolbarItem removeZeroButton = ToolbarItem.icon(
      key: const Key('remove_zero_button'),
      onPressed: () => <void>{setSetupPositionNeedRemove(0, true)},
      icon: const Icon(FluentIcons.circle_24_regular),
      label: Text(
        S.of(context).remove,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final ToolbarItem removeOneButton = ToolbarItem.icon(
      key: const Key('remove_one_button'),
      onPressed: () => <void>{setSetupPositionNeedRemove(1, true)},
      icon: const Icon(FluentIcons.number_circle_1_24_regular),
      label: Text(
        S.of(context).remove,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final ToolbarItem removeTwoButton = ToolbarItem.icon(
      key: const Key('remove_two_button'),
      onPressed: () => <void>{setSetupPositionNeedRemove(2, true)},
      icon: const Icon(FluentIcons.number_circle_2_24_regular),
      label: Text(
        S.of(context).remove,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final ToolbarItem removeThreeButton = ToolbarItem.icon(
      key: const Key('remove_three_button'),
      onPressed: () => <void>{setSetupPositionNeedRemove(3, true)},
      icon: const Icon(FluentIcons.number_circle_3_24_regular),
      label: Text(
        S.of(context).remove,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final ToolbarItem placedButton = ToolbarItem.icon(
      key: const Key('placed_button'),
      onPressed: () => <void>{setSetupPositionPlaced(context)},
      icon: const Icon(FluentIcons.text_word_count_24_regular),
      label: Text(
        S.of(context).placedCount(newPlaced),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final ToolbarItem copyButton = ToolbarItem.icon(
      key: const Key('copy_button'),
      onPressed: () => <void>{setSetupPositionCopy(context)},
      icon: const Icon(FluentIcons.copy_24_regular),
      label: Text(
        S.of(context).copy,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final ToolbarItem pasteButton = ToolbarItem.icon(
      key: const Key('paste_button'),
      onPressed: () => <void>{setSetupPositionPaste(context)},
      icon: const Icon(FluentIcons.clipboard_paste_24_regular),
      label: Text(
        S.of(context).paste,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    // Cancel
    final ToolbarItem cancelButton = ToolbarItem.icon(
      key: const Key('cancel_button'),
      onPressed: () => <void>{restoreContext()}, // TODO: setState();
      icon: const Icon(FluentIcons.dismiss_24_regular),
      label: Text(
        S.of(context).cancel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final Map<PieceColor, ToolbarItem> colorButtonMap =
        <PieceColor, ToolbarItem>{
      PieceColor.white: whitePieceButton,
      PieceColor.black: blackPieceButton,
      PieceColor.marked: markedPointButton,
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

    final List<Widget> row1 = <Widget>[
      Expanded(child: colorButtonMap[newPieceColor]!),
      Expanded(child: phaseButtonMap[newPhase]!),
      Expanded(
          child: newPieceColor == PieceColor.white ||
                  newPieceColor == PieceColor.black
              ? removeButtonMap[newPieceCountNeedRemove[newPieceColor]]!
              : removeZeroButton),
      Expanded(child: placedButton),
    ];

    // TODO: Other buttons
    final List<Widget> row2 = <Widget>[
      Expanded(child: rotateButton),
      Expanded(child: horizontalFlipButton),
      Expanded(child: verticalFlipButton),
      Expanded(child: innerOuterFlipButton),
    ];

    final List<Widget> row3 = <Widget>[
      Expanded(child: copyButton),
      Expanded(child: pasteButton),
      Expanded(child: clearButton),
      Expanded(child: cancelButton),
    ];

    return Column(
      children: <Widget>[
        SetupPositionButtonsContainer(
          key: const Key('setup_position_buttons_container_row1'),
          backgroundColor: backgroundColor,
          margin: _margin,
          padding: _padding,
          itemColor: itemColor,
          child: row1,
        ),
        SetupPositionButtonsContainer(
          key: const Key('setup_position_buttons_container_row2'),
          backgroundColor: backgroundColor,
          margin: _margin,
          padding: _padding,
          itemColor: itemColor,
          child: row2,
        ),
        SetupPositionButtonsContainer(
          key: const Key('setup_position_buttons_container_row3'),
          backgroundColor: backgroundColor,
          margin: _margin,
          padding: _padding,
          itemColor: itemColor,
          child: row3,
        ),
      ],
    );
  }

  @override
  void deactivate() {
    GameController()
        .setupPositionNotifier
        .addListener(_updateSetupPositionIcons);
    if (setSetupPositionDone() == false) {
      logger.e("Invalid Position.");
    }
    logger.i("FEN: ${GameController().position.fen}");

    super.deactivate();
  }

  @override
  void dispose() {
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
      key: key,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        color: backgroundColor,
      ),
      margin: _margin,
      padding: _padding,
      child: ToolbarItemTheme(
        key: const Key('toolbar_item_theme_container'),
        data: ToolbarItemThemeData(
          style: ToolbarItem.styleFrom(primary: itemColor),
        ),
        child: Directionality(
          key: const Key('toolbar_directionality_container'),
          textDirection: TextDirection.ltr,
          child: Row(
            key: const Key('toolbar_row_container'),
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                key: Key('placed_option_$i'),
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
