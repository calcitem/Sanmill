// SPDX-License-Identifier: AGPL-3.0-or-later
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
  MillSetupPositionController? get _controller =>
      GameController().setupPositionController;

  /// Fixed height for the three-row setup-position toolbar.
  static double get height => kLichessBottomBarHeight * 3;

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
    DiagnosticReplayGuard.requireAllowed('Setup clipboard exporting');
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
    DiagnosticReplayGuard.requireAllowed('Setup clipboard importing');
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

  IconData _paintColorIcon() {
    final PieceColor color = _controller?.paintColor ?? PieceColor.white;
    switch (color) {
      case PieceColor.white:
        return FluentIcons.circle_24_regular;
      case PieceColor.black:
        return FluentIcons.circle_24_filled;
      case PieceColor.marked:
        return FluentIcons.prohibited_24_regular;
      case PieceColor.none:
      case PieceColor.nobody:
      case PieceColor.draw:
        return FluentIcons.add_24_regular;
    }
  }

  String _paintColorLabel(BuildContext context) {
    final PieceColor color = _controller?.paintColor ?? PieceColor.white;
    switch (color) {
      case PieceColor.white:
        return S.of(context).white;
      case PieceColor.black:
        return S.of(context).black;
      case PieceColor.marked:
        return S.of(context).marked;
      case PieceColor.none:
      case PieceColor.nobody:
      case PieceColor.draw:
        return S.of(context).emptyPoint;
    }
  }

  IconData _phaseIcon() {
    final Phase phase = _controller?.phase ?? Phase.placing;
    return phase == Phase.moving
        ? FluentIcons.arrow_move_24_regular
        : FluentIcons.grid_dots_24_regular;
  }

  String _phaseLabel(BuildContext context) {
    final Phase phase = _controller?.phase ?? Phase.placing;
    return phase == Phase.moving ? S.of(context).moving : S.of(context).placing;
  }

  IconData _needRemoveIcon() {
    final MillSetupPositionController? controller = _controller;
    final PieceColor side = controller?.sideToMove ?? PieceColor.white;
    final int count = controller?.needRemove[side] ?? 0;
    return switch (count) {
      1 => FluentIcons.number_circle_1_24_regular,
      2 => FluentIcons.number_circle_2_24_regular,
      3 => FluentIcons.number_circle_3_24_regular,
      _ => FluentIcons.circle_24_regular,
    };
  }

  String _transformRecordingValue(String id) {
    switch (id) {
      case 'rotate':
        return 'rotate90';
      case 'horizontal_flip':
        return 'mirrorHorizontal';
      case 'vertical_flip':
        return 'mirrorVertical';
      case 'inner_outer_flip':
        return 'innerOuterFlip';
    }
    assert(false, 'Unknown setup-position transform action: $id');
    return id;
  }

  ToolbarItem _toolbarButton({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    Color? iconColor,
  }) {
    return ToolbarItem.icon(
      key: key,
      onPressed: onPressed,
      icon: Icon(icon, color: iconColor),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  @override
  Widget build(BuildContext context) {
    final MillSetupPositionController? controller = _controller;
    final S strings = S.of(context);
    final int placed = controller?.placedCount ?? 0;

    final List<Widget> row1 = <Widget>[
      Expanded(
        child: _toolbarButton(
          key: const Key('paint_color_button'),
          icon: _paintColorIcon(),
          label: _paintColorLabel(context),
          onPressed: _cyclePaintColor,
        ),
      ),
      Expanded(
        child: _toolbarButton(
          key: const Key('phase_button'),
          icon: _phaseIcon(),
          label: _phaseLabel(context),
          onPressed: _togglePhase,
        ),
      ),
      Expanded(
        child: _toolbarButton(
          key: const Key('remove_button'),
          icon: _needRemoveIcon(),
          label: strings.remove,
          onPressed: _cycleNeedRemove,
        ),
      ),
      Expanded(
        child: _toolbarButton(
          key: const Key('placed_button'),
          icon: FluentIcons.text_word_count_24_regular,
          label: strings.placedCount(placed),
          onPressed: () => unawaited(_showPlacedCountPicker()),
        ),
      ),
    ];

    final List<Widget> row2 = <Widget>[
      for (final MillBoardTransformAction action in millBoardTransformActions)
        Expanded(
          child: _toolbarButton(
            key: Key('${action.id}_button'),
            icon: action.icon,
            label: action.label(strings),
            onPressed: () =>
                _transform(action.type, _transformRecordingValue(action.id)),
          ),
        ),
    ];

    final List<Widget> row3 = <Widget>[
      Expanded(
        child: _toolbarButton(
          key: const Key('copy_button'),
          icon: FluentIcons.copy_24_regular,
          label: strings.copy,
          onPressed: () => unawaited(_copyFen()),
        ),
      ),
      Expanded(
        child: _toolbarButton(
          key: const Key('paste_button'),
          icon: FluentIcons.clipboard_paste_24_regular,
          label: strings.paste,
          onPressed: () => unawaited(_pasteFen()),
        ),
      ),
      Expanded(
        child: _toolbarButton(
          key: const Key('clear_button'),
          icon: FluentIcons.eraser_24_regular,
          label: strings.clean,
          onPressed: _clear,
        ),
      ),
      Expanded(
        child: _toolbarButton(
          key: const Key('cancel_button'),
          icon: FluentIcons.dismiss_24_regular,
          label: strings.cancel,
          onPressed: _cancel,
        ),
      ),
      Expanded(
        child: _toolbarButton(
          key: const Key('done_button'),
          icon: FluentIcons.checkmark_24_regular,
          label: strings.done,
          onPressed: _done,
        ),
      ),
    ];

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Column(
        key: const Key('setup_position_three_row_toolbar'),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SetupPositionButtonsContainer(
            key: const Key('setup_position_buttons_container_row1'),
            children: row1,
          ),
          SetupPositionButtonsContainer(
            key: const Key('setup_position_buttons_container_row2'),
            children: row2,
          ),
          SetupPositionButtonsContainer(
            key: const Key('setup_position_buttons_container_row3'),
            children: row3,
          ),
        ],
      ),
    );
  }
}

class SetupPositionButtonsContainer extends StatelessWidget {
  const SetupPositionButtonsContainer({super.key, required this.children})
    : assert(children.length > 0, 'Toolbar row must contain buttons.');

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final Color messageColor = DB().colorSettings.messageColor;
    return Container(
      height: kLichessBottomBarHeight,
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: ToolbarItemTheme(
        data: ToolbarItemThemeData(
          style: ToolbarItem.styleFrom(
            primary: messageColor,
            onSurface: messageColor,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: children,
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
