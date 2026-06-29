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
  MillSetupPositionController? get _controller =>
      GameController().setupPositionController;

  /// Fixed Lichess-style action bar height.
  static double get height => kLichessBottomBarHeight;

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
        return S.of(context).empty;
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

  void _showSetupMenu() {
    final int placed = _controller?.placedCount ?? 0;

    unawaited(
      showLichessActionSheet<void>(
        context: context,
        sheetKey: const Key('setup_position_action_sheet'),
        title: Text(S.of(context).setupPosition),
        actions: <LichessActionSheetAction>[
          LichessActionSheetAction(
            key: const Key('setup_placed_count_button'),
            leading: const Icon(FluentIcons.text_word_count_24_regular),
            makeLabel: (BuildContext context) =>
                Text(S.of(context).placedCount(placed)),
            onPressed: () => unawaited(_showPlacedCountPicker()),
          ),
          LichessActionSheetAction(
            key: const Key('setup_need_remove_button'),
            leading: Icon(_needRemoveIcon()),
            makeLabel: (BuildContext context) => Text(S.of(context).remove),
            onPressed: _cycleNeedRemove,
          ),
          LichessActionSheetAction(
            key: const Key('setup_copy_button'),
            leading: const Icon(FluentIcons.copy_24_regular),
            makeLabel: (BuildContext context) => Text(S.of(context).copy),
            onPressed: () => unawaited(_copyFen()),
          ),
          LichessActionSheetAction(
            key: const Key('setup_paste_button'),
            leading: const Icon(FluentIcons.clipboard_paste_24_regular),
            makeLabel: (BuildContext context) => Text(S.of(context).paste),
            onPressed: () => unawaited(_pasteFen()),
          ),
          LichessActionSheetAction(
            key: const Key('setup_clear_button'),
            leading: const Icon(FluentIcons.eraser_24_regular),
            makeLabel: (BuildContext context) => Text(S.of(context).clean),
            onPressed: _clear,
          ),
          LichessActionSheetAction(
            key: const Key('setup_cancel_button'),
            leading: const Icon(FluentIcons.dismiss_24_regular),
            makeLabel: (BuildContext context) => Text(S.of(context).cancel),
            onPressed: _cancel,
            isDestructiveAction: true,
          ),
        ],
      ),
    );
  }

  void _showTransformMenu() {
    unawaited(
      showLichessActionSheet<void>(
        context: context,
        sheetKey: const Key('setup_transform_action_sheet'),
        title: Text(S.of(context).boardOrientation),
        actions: <LichessActionSheetAction>[
          for (final MillBoardTransformAction action
              in millBoardTransformActions)
            LichessActionSheetAction(
              key: Key('setup_${action.id}_button'),
              leading: Icon(action.icon),
              makeLabel: (BuildContext context) =>
                  Text(action.label(S.of(context))),
              onPressed: () => _transform(action.type, action.id),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LichessBottomBar(
      key: const Key('setup_position_lichess_bottom_bar'),
      children: <Widget>[
        LichessBottomBarButton(
          key: const Key('setup_menu_button'),
          icon: Icons.menu_rounded,
          label: S.of(context).menu,
          showLabel: true,
          onTap: _showSetupMenu,
        ),
        LichessBottomBarButton(
          key: const Key('setup_paint_color_button'),
          icon: _paintColorIcon(),
          label: _paintColorLabel(context),
          showLabel: true,
          highlighted: true,
          onTap: _cyclePaintColor,
        ),
        LichessBottomBarButton(
          key: const Key('setup_phase_button'),
          icon: _phaseIcon(),
          label: _phaseLabel(context),
          showLabel: true,
          onTap: _togglePhase,
        ),
        LichessBottomBarButton(
          key: const Key('setup_transform_menu_button'),
          icon: FluentIcons.arrow_rotate_clockwise_24_regular,
          label: S.of(context).boardOrientation,
          showLabel: true,
          onTap: _showTransformMenu,
        ),
        LichessBottomBarButton(
          key: const Key('setup_done_button'),
          icon: FluentIcons.checkmark_24_regular,
          label: S.of(context).done,
          showLabel: true,
          highlighted: true,
          onTap: _done,
        ),
      ],
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
