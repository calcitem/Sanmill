// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// setup_position_toolbar.dart

part of '../game_toolbar.dart';

/// Bottom toolbar shown while [GameMode.setupPosition] is active.
///
/// It is a thin view over [MillSetupPositionController]: every button maps
/// to a controller intent (paint a piece type, toggle phase, set the
/// pending-removal count, transform, copy/paste FEN, clear) and the board
/// itself updates through the native session that the controller drives.
class SetupPositionToolbar extends StatefulWidget {
  const SetupPositionToolbar({super.key});

  @override
  State<SetupPositionToolbar> createState() => SetupPositionToolbarState();
}

class SetupPositionToolbarState extends State<SetupPositionToolbar> {
  final Color? backgroundColor = DB().colorSettings.mainToolbarBackgroundColor;
  final Color? itemColor = DB().colorSettings.mainToolbarIconColor;

  MillSetupPositionController? get _controller =>
      GameController().setupPositionController;

  static const EdgeInsets _padding = EdgeInsets.symmetric(vertical: 2);
  static const EdgeInsets _margin = EdgeInsets.symmetric(vertical: 0.2);

  /// Calculated height this widget adds to its children.
  static double get height => (_padding.vertical + _margin.vertical) * 2;

  @override
  void initState() {
    super.initState();
    GameController().setupPositionNotifier.addListener(_onModelChanged);

    if (DB().ruleSettings.enableCustodianCapture ||
        DB().ruleSettings.enableInterventionCapture) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        rootScaffoldMessengerKey.currentState?.showSnackBarClear(
          S.of(context).experimental,
        );
      });
    }
  }

  @override
  void dispose() {
    GameController().setupPositionNotifier.removeListener(_onModelChanged);
    super.dispose();
  }

  void _onModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _record(
    String action, [
    Map<String, dynamic> extra = const <String, dynamic>{},
  ]) {
    RecordingService().recordEvent(
      RecordingEventType.setupPositionAction,
      <String, dynamic>{'action': action, ...extra},
    );
  }

  void _cyclePaintColor() {
    final MillSetupPositionController? controller = _controller;
    if (controller == null) {
      return;
    }
    controller.cyclePaintColor();
    _record('selectPiece', <String, dynamic>{
      'value': controller.paintColor.string,
    });
    GameController().headerTipNotifier.showTip(
      controller.paintColor.pieceName(context),
    );
    GameController().headerIconsNotifier.showIcons();
    setState(() {});
  }

  void _togglePhase() {
    final MillSetupPositionController? controller = _controller;
    if (controller == null) {
      return;
    }
    final Phase next = controller.phase == Phase.placing
        ? Phase.moving
        : Phase.placing;
    controller.setPhase(next);
    _record('selectPhase', <String, dynamic>{
      'value': next == Phase.moving ? 'moving' : 'placing',
    });
    GameController().headerTipNotifier.showTip(
      next == Phase.moving
          ? S.of(context).movingPhase
          : S.of(context).placingPhase,
    );
    setState(() {});
  }

  Future<void> _showPlacedCountPicker() async {
    final MillSetupPositionController? controller = _controller;
    if (controller == null) {
      return;
    }
    if (controller.phase != Phase.placing) {
      GameController().headerTipNotifier.showTip(S.of(context).notPlacingPhase);
      return;
    }

    final int? selected = await showModalBottomSheet<int>(
      context: context,
      builder: (BuildContext context) => _PlacedCountModal(
        placedGroupValue: controller.placedCount,
        begin: controller.placedCountModalBegin,
        piecesCount: controller.piecesCount,
      ),
    );
    if (!mounted || selected == null) {
      return;
    }

    controller.setPlacedCount(selected);
    _record('setPlacedCount', <String, dynamic>{'value': selected});
    GameController().headerTipNotifier.showTip(
      S.of(context).hasPlacedPieceCount(selected),
    );
    setState(() {});
  }

  void _cycleNeedRemove() {
    final MillSetupPositionController? controller = _controller;
    if (controller == null) {
      return;
    }
    final PieceColor side = controller.sideToMove;
    final int current = controller.needRemove[side] ?? 0;
    final int next = current >= 3 ? 0 : current + 1;
    controller.setNeedRemove(side, next);
    final int applied = controller.needRemove[side] ?? 0;
    _record('setNeedRemove', <String, dynamic>{'value': applied});
    GameController().headerTipNotifier.showTip(
      applied == 0
          ? S.of(context).noPiecesCanBeRemoved
          : S.of(context).pieceCountNeedToRemove(applied),
    );
    setState(() {});
  }

  void _clear() {
    _controller?.clear();
    _record('clear');
    GameController().headerTipNotifier.showTip(S.of(context).cleanedUp);
    setState(() {});
  }

  void _transform(TransformationType type, String value) {
    _controller?.transform(type);
    _record('transform', <String, dynamic>{'value': value});
    setState(() {});
  }

  Future<void> _copyFen() async {
    final MillSetupPositionController? controller = _controller;
    if (controller == null) {
      return;
    }
    _record('copy');
    final String copyLabel = S.of(context).copy;
    final String fen = controller.exportFen();
    await Clipboard.setData(ClipboardData(text: fen));
    rootScaffoldMessengerKey.currentState?.showSnackBarClear(
      "$copyLabel FEN: $fen",
    );
  }

  Future<void> _pasteFen() async {
    final MillSetupPositionController? controller = _controller;
    if (controller == null) {
      return;
    }
    _record('paste');
    final String tipFailed = S.of(context).cannotPaste;
    final String tipDone = S.of(context).pasteDone;
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String? text = data?.text;
    if (text == null || text.trim().isEmpty) {
      GameController().headerTipNotifier.showTip(tipFailed);
      return;
    }
    if (controller.pasteFen(text)) {
      GameController().headerTipNotifier.showTip(tipDone);
      if (mounted) {
        rootScaffoldMessengerKey.currentState?.showSnackBarClear(
          "FEN: ${text.trim()}",
        );
      }
    } else {
      GameController().headerTipNotifier.showTip(tipFailed);
    }
    setState(() {});
  }

  void _cancel() {
    _record('cancel');
    GameController().headerTipNotifier.showTip(S.of(context).restoredPosition);
    GameController().cancelSetupPosition();
  }

  void _done() {
    final MillSetupPositionController? controller = _controller;
    if (controller == null) {
      return;
    }
    _record('done');
    final String? fen = controller.commit();
    if (fen == null) {
      rootScaffoldMessengerKey.currentState?.showSnackBarClear(
        S.of(context).invalidPosition,
      );
      return;
    }
    GameController().finishSetupPosition(fen);
    GameController().headerTipNotifier.showTip(S.of(context).gameStarted);
  }

  ToolbarItem _paintColorButton(BuildContext context) {
    final PieceColor color = _controller?.paintColor ?? PieceColor.white;
    switch (color) {
      case PieceColor.white:
        return ToolbarItem.icon(
          key: const Key('setup_paint_color_button'),
          onPressed: _cyclePaintColor,
          icon: Icon(
            FluentIcons.circle_24_filled,
            color:
                (DB().colorSettings.mainToolbarBackgroundColor ==
                        Colors.white &&
                    DB().colorSettings.whitePieceColor == Colors.white)
                ? Colors.grey[300]
                : DB().colorSettings.whitePieceColor,
          ),
          label: _ellipsisText(S.of(context).white),
        );
      case PieceColor.black:
        return ToolbarItem.icon(
          key: const Key('setup_paint_color_button'),
          onPressed: _cyclePaintColor,
          icon: Icon(
            FluentIcons.circle_24_filled,
            color: DB().colorSettings.blackPieceColor,
          ),
          label: _ellipsisText(S.of(context).black),
        );
      case PieceColor.marked:
        return ToolbarItem.icon(
          key: const Key('setup_paint_color_button'),
          onPressed: _cyclePaintColor,
          icon: const Icon(FluentIcons.prohibited_24_regular),
          label: _ellipsisText(S.of(context).marked),
        );
      case PieceColor.none:
      case PieceColor.nobody:
      case PieceColor.draw:
        return ToolbarItem.icon(
          key: const Key('setup_paint_color_button'),
          onPressed: _cyclePaintColor,
          icon: const Icon(FluentIcons.add_24_regular),
          label: _ellipsisText(S.of(context).empty),
        );
    }
  }

  ToolbarItem _phaseButton(BuildContext context) {
    final Phase phase = _controller?.phase ?? Phase.placing;
    return ToolbarItem.icon(
      key: const Key('setup_phase_button'),
      onPressed: _togglePhase,
      icon: Icon(
        phase == Phase.moving
            ? FluentIcons.arrow_move_24_regular
            : FluentIcons.grid_dots_24_regular,
      ),
      label: _ellipsisText(
        phase == Phase.moving ? S.of(context).moving : S.of(context).placing,
      ),
    );
  }

  ToolbarItem _needRemoveButton(BuildContext context) {
    final MillSetupPositionController? controller = _controller;
    final PieceColor side = controller?.sideToMove ?? PieceColor.white;
    final int count = controller?.needRemove[side] ?? 0;
    final IconData icon = switch (count) {
      1 => FluentIcons.number_circle_1_24_regular,
      2 => FluentIcons.number_circle_2_24_regular,
      3 => FluentIcons.number_circle_3_24_regular,
      _ => FluentIcons.circle_24_regular,
    };
    return ToolbarItem.icon(
      key: const Key('setup_need_remove_button'),
      onPressed: _cycleNeedRemove,
      icon: Icon(icon),
      label: _ellipsisText(S.of(context).remove),
    );
  }

  ToolbarItem _placedCountButton(BuildContext context) {
    final int placed = _controller?.placedCount ?? 0;
    return ToolbarItem.icon(
      key: const Key('setup_placed_count_button'),
      onPressed: _showPlacedCountPicker,
      icon: const Icon(FluentIcons.text_word_count_24_regular),
      label: _ellipsisText(S.of(context).placedCount(placed)),
    );
  }

  static Text _ellipsisText(String label) =>
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);

  @override
  Widget build(BuildContext context) {
    final ToolbarItem clearButton = ToolbarItem.icon(
      key: const Key('setup_clear_button'),
      onPressed: _clear,
      icon: const Icon(FluentIcons.eraser_24_regular),
      label: _ellipsisText(S.of(context).clean),
    );

    final ToolbarItem rotateButton = ToolbarItem.icon(
      key: const Key('setup_rotate_button'),
      onPressed: () => _transform(TransformationType.rotate90, 'rotate90'),
      icon: const Icon(FluentIcons.arrow_rotate_clockwise_24_regular),
      label: _ellipsisText(S.of(context).rotate),
    );
    final ToolbarItem horizontalFlipButton = ToolbarItem.icon(
      key: const Key('setup_horizontal_flip_button'),
      onPressed: () =>
          _transform(TransformationType.mirrorHorizontal, 'mirrorHorizontal'),
      icon: const Icon(FluentIcons.flip_horizontal_24_regular),
      label: _ellipsisText(S.of(context).horizontalFlip),
    );
    final ToolbarItem verticalFlipButton = ToolbarItem.icon(
      key: const Key('setup_vertical_flip_button'),
      onPressed: () =>
          _transform(TransformationType.mirrorVertical, 'mirrorVertical'),
      icon: const Icon(FluentIcons.flip_vertical_24_regular),
      label: _ellipsisText(S.of(context).verticalFlip),
    );
    final ToolbarItem innerOuterFlipButton = ToolbarItem.icon(
      key: const Key('setup_inner_outer_flip_button'),
      onPressed: () => _transform(TransformationType.swap, 'innerOuterFlip'),
      icon: const Icon(FluentIcons.arrow_expand_24_regular),
      label: _ellipsisText(S.of(context).innerOuterFlip),
    );

    final ToolbarItem copyButton = ToolbarItem.icon(
      key: const Key('setup_copy_button'),
      onPressed: _copyFen,
      icon: const Icon(FluentIcons.copy_24_regular),
      label: _ellipsisText(S.of(context).copy),
    );
    final ToolbarItem pasteButton = ToolbarItem.icon(
      key: const Key('setup_paste_button'),
      onPressed: _pasteFen,
      icon: const Icon(FluentIcons.clipboard_paste_24_regular),
      label: _ellipsisText(S.of(context).paste),
    );
    final ToolbarItem cancelButton = ToolbarItem.icon(
      key: const Key('setup_cancel_button'),
      onPressed: _cancel,
      icon: const Icon(FluentIcons.dismiss_24_regular),
      label: _ellipsisText(S.of(context).cancel),
    );
    final ToolbarItem doneButton = ToolbarItem.icon(
      key: const Key('setup_done_button'),
      onPressed: _done,
      icon: const Icon(FluentIcons.checkmark_24_regular),
      label: _ellipsisText(S.of(context).done),
    );

    final List<Widget> row1 = <Widget>[
      Expanded(child: _paintColorButton(context)),
      Expanded(child: _phaseButton(context)),
      Expanded(child: _needRemoveButton(context)),
      Expanded(child: _placedCountButton(context)),
    ];
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
      Expanded(child: doneButton),
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
}

class SetupPositionButtonsContainer extends StatelessWidget {
  const SetupPositionButtonsContainer({
    super.key,
    required this.backgroundColor,
    required EdgeInsets margin,
    required EdgeInsets padding,
    required this.itemColor,
    required this.child,
  }) : _margin = margin,
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
        key: const Key('setup_toolbar_item_theme_container'),
        data: ToolbarItemThemeData(
          style: ToolbarItem.styleFrom(primary: itemColor),
        ),
        child: Directionality(
          key: const Key('setup_toolbar_directionality_container'),
          textDirection: TextDirection.ltr,
          child: Row(
            key: const Key('setup_toolbar_row_container'),
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: child,
          ),
        ),
      ),
    );
  }
}

class _PlacedCountModal extends StatelessWidget {
  const _PlacedCountModal({
    required this.placedGroupValue,
    required this.begin,
    required this.piecesCount,
  });

  final int placedGroupValue;
  final int begin;
  final int piecesCount;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: S.of(context).placedPieceCount,
      child: SingleChildScrollView(
        child: RadioGroup<int>(
          groupValue: placedGroupValue,
          onChanged: (int? value) => Navigator.pop(context, value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (int i = begin; i <= piecesCount; i++)
                RadioListTile<int>(
                  key: Key('placed_option_$i'),
                  title: Text(i.toString()),
                  value: i,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
