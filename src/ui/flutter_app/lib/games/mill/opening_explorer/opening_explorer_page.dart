// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../appearance_settings/models/color_settings.dart';
import '../../../game_page/services/transform/transform.dart';
import '../../../game_platform/game_session.dart';
import '../../../general_settings/models/general_settings.dart';
import '../../../generated/intl/l10n.dart';
import '../../../rule_settings/models/rule_settings.dart';
import '../../../shared/database/database.dart' show DB;
import '../../../shared/services/human_database_service.dart';
import '../../../shared/services/snackbar_service.dart';
import '../../../shared/themes/app_styles.dart';
import '../../../shared/themes/app_theme.dart';
import '../../../shared/widgets/lichess_bottom_bar.dart';
import '../../../shared/widgets/lichess_list_section.dart';
import '../../../src/rust/api/simple.dart' as tgf;
import '../mill_action_codec.dart';
import '../mill_board_coordinate_maps.dart';
import '../mill_board_geometry.dart';
import '../mill_board_transform_actions.dart';
import '../mill_human_database_provider.dart';
import '../mill_opening_book_symmetry.dart';
import '../mill_session_tap_controller.dart';
import '../native_mill_game_session.dart';
import '../native_mill_snapshot_board_view.dart';
import '../opening_book/opening_book_repository.dart';

class OpeningExplorerPage extends StatefulWidget {
  const OpeningExplorerPage({super.key, this.session});

  final GameSession? session;

  @override
  State<OpeningExplorerPage> createState() => _OpeningExplorerPageState();
}

typedef _OpeningExplorerPositionChanged =
    void Function({required String previousFen, required String currentFen});

class _OpeningExplorerPageState extends State<OpeningExplorerPage> {
  late final Future<void> _openingBookLoad = OpeningBookRepository.instance
      .ensureLoaded();
  final MillSessionTapController _tapController = MillSessionTapController();
  final List<String> _previousExplorerFens = <String>[];
  final List<String> _nextExplorerFens = <String>[];
  NativeMillGameSession? _explorerSession;

  @override
  void initState() {
    super.initState();
    _recreateExplorerSession();
  }

  @override
  void didUpdateWidget(covariant OpeningExplorerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.session, oldWidget.session)) {
      _recreateExplorerSession();
    }
  }

  @override
  void dispose() {
    _explorerSession?.dispose();
    super.dispose();
  }

  void _recreateExplorerSession() {
    _explorerSession?.dispose();
    _explorerSession = null;
    _previousExplorerFens.clear();
    _nextExplorerFens.clear();
    _tapController.clearSelection();

    final GameSession? source = widget.session;
    if (source is! NativeMillGameSession) {
      return;
    }

    final NativeMillGameSession explorer = NativeMillGameSession(
      rules: DB().ruleSettings,
      generalSettings: DB().generalSettings,
    );
    final bool loaded = explorer.loadFen(source.getFen());
    assert(loaded, 'Opening explorer source FEN must load into its session.');
    if (!loaded) {
      explorer.dispose();
      return;
    }
    _explorerSession = explorer;
  }

  Future<void> _applyExplorerAction(GameAction action) async {
    final NativeMillGameSession? session = _explorerSession;
    if (session == null) {
      return;
    }
    final String previousFen = session.getFen();
    await session.apply(action);
    final String currentFen = session.getFen();
    _tapController.clearSelection();
    if (mounted) {
      _recordExplorerPositionChange(
        previousFen: previousFen,
        currentFen: currentFen,
      );
    }
  }

  void _transformExplorerPosition(TransformationType type) {
    final NativeMillGameSession? session = _explorerSession;
    if (session == null) {
      return;
    }
    final String previousFen = session.getFen();
    final String transformed = transformFEN(previousFen, type);
    final bool loaded = session.loadFen(transformed);
    assert(loaded, 'Opening explorer transformation must keep a valid FEN.');
    if (!loaded) {
      return;
    }
    _tapController.clearSelection();
    _recordExplorerPositionChange(
      previousFen: previousFen,
      currentFen: session.getFen(),
    );
  }

  void _recordExplorerPositionChange({
    required String previousFen,
    required String currentFen,
  }) {
    assert(previousFen.isNotEmpty, 'Explorer previous FEN must not be empty.');
    assert(currentFen.isNotEmpty, 'Explorer current FEN must not be empty.');
    if (previousFen == currentFen) {
      setState(() {});
      return;
    }
    _previousExplorerFens.add(previousFen);
    _nextExplorerFens.clear();
    setState(() {});
  }

  bool _restoreExplorerFen(String fen) {
    assert(fen.isNotEmpty, 'Explorer history FEN must not be empty.');
    final NativeMillGameSession? session = _explorerSession;
    assert(session != null, 'Opening explorer history requires a session.');
    if (session == null) {
      return false;
    }
    final bool loaded = session.loadFen(fen);
    assert(loaded, 'Opening explorer history FEN must load.');
    if (!loaded) {
      return false;
    }
    _tapController.clearSelection();
    return true;
  }

  void _goToPreviousExplorerPosition() {
    final NativeMillGameSession? session = _explorerSession;
    assert(session != null, 'Opening explorer history requires a session.');
    if (session == null || _previousExplorerFens.isEmpty) {
      return;
    }
    final String currentFen = session.getFen();
    final String previousFen = _previousExplorerFens.last;
    if (!_restoreExplorerFen(previousFen)) {
      return;
    }
    _previousExplorerFens.removeLast();
    _nextExplorerFens.add(currentFen);
    setState(() {});
  }

  void _goToNextExplorerPosition() {
    final NativeMillGameSession? session = _explorerSession;
    assert(session != null, 'Opening explorer history requires a session.');
    if (session == null || _nextExplorerFens.isEmpty) {
      return;
    }
    final String currentFen = session.getFen();
    final String nextFen = _nextExplorerFens.last;
    if (!_restoreExplorerFen(nextFen)) {
      return;
    }
    _nextExplorerFens.removeLast();
    _previousExplorerFens.add(currentFen);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final NativeMillGameSession? session = _explorerSession;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.openingExplorer),
        actions: session == null
            ? null
            : <Widget>[
                IconButton(
                  key: const Key('opening_explorer_previous_button'),
                  tooltip: strings.previous,
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: _previousExplorerFens.isEmpty
                      ? null
                      : _goToPreviousExplorerPosition,
                ),
                IconButton(
                  key: const Key('opening_explorer_next_button'),
                  tooltip: strings.next,
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: _nextExplorerFens.isEmpty
                      ? null
                      : _goToNextExplorerPosition,
                ),
              ],
      ),
      bottomNavigationBar: session == null
          ? null
          : _OpeningExplorerBottomBar(onTransform: _transformExplorerPosition),
      body: session != null
          ? ValueListenableBuilder<GameStateSnapshot>(
              valueListenable: session.state,
              builder:
                  (BuildContext context, GameStateSnapshot _, Widget? child) {
                    return FutureBuilder<void>(
                      future: _openingBookLoad,
                      builder: (BuildContext context, AsyncSnapshot<void> _) {
                        final _OpeningExplorerSnapshot snapshot =
                            _OpeningExplorerSnapshot.fromSession(
                              session: session,
                              ruleSettings: DB().ruleSettings,
                              generalSettings: DB().generalSettings,
                            );
                        return _OpeningExplorerContent(
                          session: session,
                          snapshot: snapshot,
                          tapController: _tapController,
                          onMoveSelected: _applyExplorerAction,
                          onPositionChanged: _recordExplorerPositionChange,
                        );
                      },
                    );
                  },
            )
          : _OpeningExplorerMessage(
              message: strings.openingExplorerUnavailable,
            ),
    );
  }
}

class _OpeningExplorerContent extends StatelessWidget {
  const _OpeningExplorerContent({
    required this.session,
    required this.snapshot,
    required this.tapController,
    required this.onMoveSelected,
    required this.onPositionChanged,
  });

  final NativeMillGameSession session;
  final _OpeningExplorerSnapshot snapshot;
  final MillSessionTapController tapController;
  final ValueChanged<GameAction> onMoveSelected;
  final _OpeningExplorerPositionChanged onPositionChanged;

  @override
  Widget build(BuildContext context) {
    return ListTileTheme.merge(
      iconColor: Theme.of(context).colorScheme.primary,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool useSideBySide =
              constraints.maxWidth >= 720 &&
              constraints.maxWidth > constraints.maxHeight;
          final Widget content = useSideBySide
              ? Row(
                  children: <Widget>[
                    Expanded(
                      flex: 5,
                      child: ListView(
                        key: const Key('opening_explorer_board_pane'),
                        padding: const EdgeInsets.only(top: 16, bottom: 24),
                        children: <Widget>[
                          _buildBoardSection(boardHeightFactor: 0.78),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      flex: 6,
                      child: ListView(
                        key: const Key('opening_explorer_data_pane'),
                        padding: const EdgeInsets.only(top: 16, bottom: 24),
                        children: _buildDataSections(context),
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.only(top: 16, bottom: 24),
                  children: <Widget>[
                    _buildBoardSection(),
                    ..._buildDataSections(context),
                  ],
                );

          return KeyedSubtree(
            key: const Key('opening_explorer_list'),
            child: content,
          );
        },
      ),
    );
  }

  Widget _buildBoardSection({double boardHeightFactor = 0.56}) {
    return _ExplorerBoardSection(
      session: session,
      tapController: tapController,
      boardHeightFactor: boardHeightFactor,
      onPositionChanged: onPositionChanged,
    );
  }

  List<Widget> _buildDataSections(BuildContext context) {
    final S strings = S.of(context);

    return <Widget>[
      if (!snapshot.isRuleSupported)
        _OpeningExplorerMessage(
          message: strings.openingExplorerRuleUnsupported,
          inList: true,
        ),
      _PositionSection(snapshot: snapshot),
      if (snapshot.moves.isEmpty)
        _OpeningExplorerMessage(
          message: strings.openingExplorerNoData,
          inList: true,
        )
      else
        LichessListSection(
          header: Text(strings.openingExplorerMoves),
          cardKey: const Key('opening_explorer_moves_card'),
          children: <Widget>[
            const _OpeningExplorerMovesHeader(),
            for (final (int index, _OpeningExplorerMove move)
                in snapshot.moves.indexed)
              _OpeningMoveTile(
                index: index,
                move: move,
                onSelected: () => onMoveSelected(move.action),
              ),
            if (snapshot.aggregateHumanStats != null)
              _OpeningExplorerTotalTile(
                stats: snapshot.aggregateHumanStats!,
                rowIndex: snapshot.moves.length,
              ),
          ],
        ),
    ];
  }
}

class _ExplorerBoardSection extends StatelessWidget {
  const _ExplorerBoardSection({
    required this.session,
    required this.tapController,
    required this.boardHeightFactor,
    required this.onPositionChanged,
  });

  final NativeMillGameSession session;
  final MillSessionTapController tapController;
  final double boardHeightFactor;
  final _OpeningExplorerPositionChanged onPositionChanged;

  @override
  Widget build(BuildContext context) {
    return LichessListSection(
      hasLeading: false,
      cardKey: const Key('opening_explorer_board_card'),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            children: <Widget>[
              _OpeningExplorerBoard(
                session: session,
                tapController: tapController,
                heightFactor: boardHeightFactor,
                onPositionChanged: onPositionChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OpeningExplorerBottomBar extends StatelessWidget {
  const _OpeningExplorerBottomBar({required this.onTransform});

  final ValueChanged<TransformationType> onTransform;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    return LichessBottomBar(
      key: const Key('opening_explorer_bottom_bar'),
      children: <Widget>[
        for (final MillBoardTransformAction action in millBoardTransformActions)
          LichessBottomBarButton(
            key: Key('opening_explorer_${action.id}_button'),
            icon: action.icon,
            label: action.label(strings),
            showLabel: true,
            onTap: () => onTransform(action.type),
          ),
      ],
    );
  }
}

class _OpeningExplorerBoard extends StatefulWidget {
  const _OpeningExplorerBoard({
    required this.session,
    required this.tapController,
    required this.heightFactor,
    required this.onPositionChanged,
  });

  final NativeMillGameSession session;
  final MillSessionTapController tapController;
  final double heightFactor;
  final _OpeningExplorerPositionChanged onPositionChanged;

  @override
  State<_OpeningExplorerBoard> createState() => _OpeningExplorerBoardState();
}

class _OpeningExplorerBoardState extends State<_OpeningExplorerBoard> {
  Future<void> _handleTap(Offset localPosition, Size size) async {
    final int node = MillBoardGeometry.nodeFromPosition(localPosition, size);
    if (node < 0) {
      widget.tapController.clearSelection();
      setState(() {});
      return;
    }
    final String notation = MillBoardCoordinateMaps.nodeToNotation(node);
    assert(notation.isNotEmpty, 'Opening explorer node must have notation.');
    final String previousFen = widget.session.getFen();
    final MillSessionTapResult result = await widget.tapController.tap(
      session: widget.session,
      tappedLabel: notation,
    );
    if (!mounted) {
      return;
    }
    if (result.status == MillSessionTapStatus.applied) {
      widget.onPositionChanged(
        previousFen: previousFen,
        currentFen: widget.session.getFen(),
      );
    }
    if (result.status != MillSessionTapStatus.ignored) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorSettings colors = DB().colorSettings;
    final RuleSettings rules = DB().ruleSettings;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double available = math.min(
          constraints.maxWidth,
          MediaQuery.sizeOf(context).height * widget.heightFactor,
        );
        final double side = available.isFinite ? available : 320;

        return Center(
          child: SizedBox.square(
            key: const Key('opening_explorer_board'),
            dimension: side,
            child: ValueListenableBuilder<GameStateSnapshot>(
              valueListenable: widget.session.state,
              builder:
                  (
                    BuildContext context,
                    GameStateSnapshot snapshot,
                    Widget? child,
                  ) {
                    final _OpeningExplorerLegalHints hints =
                        _OpeningExplorerLegalHints.fromActions(
                          legalActions: widget.session.legalActions,
                          selectedFrom: widget.tapController.selectedFrom,
                        );
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (TapUpDetails details) =>
                          _handleTap(details.localPosition, Size.square(side)),
                      child: CustomPaint(
                        painter: _OpeningExplorerBoardPainter(
                          snapshot: snapshot,
                          selectedFrom: widget.tapController.selectedFrom,
                          legalHints: hints,
                          hasDiagonalLines: rules.hasDiagonalLines,
                          boardBackgroundColor: colors.boardBackgroundColor,
                          boardLineColor: colors.boardLineColor,
                          whitePieceColor: colors.whitePieceColor,
                          blackPieceColor: colors.blackPieceColor,
                          pieceHighlightColor: colors.pieceHighlightColor,
                          hintColor: colorScheme.primary,
                          removeHintColor: colorScheme.error,
                          shadowColor: colorScheme.shadow,
                        ),
                        child: child,
                      ),
                    );
                  },
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}

class _OpeningExplorerLegalHints {
  const _OpeningExplorerLegalHints({
    required this.sources,
    required this.targets,
    required this.removals,
  });

  factory _OpeningExplorerLegalHints.fromActions({
    required Iterable<GameAction> legalActions,
    required String? selectedFrom,
  }) {
    final Set<int> sources = <int>{};
    final Set<int> targets = <int>{};
    final Set<int> removals = <int>{};
    final String? selected = selectedFrom?.toLowerCase();

    for (final GameAction action in legalActions) {
      final String? move = MillActionCodec.moveStringFrom(action);
      if (move == null || move.isEmpty) {
        continue;
      }
      if (action.type == MillActionTypes.remove && move.startsWith('x')) {
        _addNotationNode(removals, move.substring(1));
        continue;
      }
      if (action.type == MillActionTypes.place) {
        _addNotationNode(targets, move);
        continue;
      }
      if (action.type != MillActionTypes.move || !move.contains('-')) {
        continue;
      }

      final List<String> parts = move.split('-');
      if (parts.length != 2) {
        continue;
      }
      final String from = parts[0].toLowerCase();
      final String to = parts[1].toLowerCase();
      if (selected == null || selected.isEmpty) {
        _addNotationNode(sources, from);
      } else if (from == selected) {
        _addNotationNode(targets, to);
      }
    }

    return _OpeningExplorerLegalHints(
      sources: sources,
      targets: targets,
      removals: removals,
    );
  }

  final Set<int> sources;
  final Set<int> targets;
  final Set<int> removals;

  static void _addNotationNode(Set<int> nodes, String notation) {
    final int node = MillBoardCoordinateMaps.notationToNode(notation);
    if (node >= 0) {
      nodes.add(node);
    }
  }
}

class _OpeningExplorerBoardPainter extends CustomPainter {
  const _OpeningExplorerBoardPainter({
    required this.snapshot,
    required this.selectedFrom,
    required this.legalHints,
    required this.hasDiagonalLines,
    required this.boardBackgroundColor,
    required this.boardLineColor,
    required this.whitePieceColor,
    required this.blackPieceColor,
    required this.pieceHighlightColor,
    required this.hintColor,
    required this.removeHintColor,
    required this.shadowColor,
  });

  final GameStateSnapshot snapshot;
  final String? selectedFrom;
  final _OpeningExplorerLegalHints legalHints;
  final bool hasDiagonalLines;
  final Color boardBackgroundColor;
  final Color boardLineColor;
  final Color whitePieceColor;
  final Color blackPieceColor;
  final Color pieceHighlightColor;
  final Color hintColor;
  final Color removeHintColor;
  final Color shadowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final NativeMillSnapshotBoardView? board =
        NativeMillSnapshotBoardView.fromSnapshot(snapshot);

    final RRect background = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.shortestSide * 0.035),
    );
    canvas.drawRRect(background, Paint()..color = boardBackgroundColor);

    _drawLines(canvas, size);
    _drawPoints(canvas, size);
    _drawHints(canvas, size, legalHints.sources, hintColor, filled: false);
    _drawHints(canvas, size, legalHints.targets, hintColor, filled: true);
    _drawHints(
      canvas,
      size,
      legalHints.removals,
      removeHintColor,
      filled: true,
    );

    if (board != null) {
      _drawPieces(canvas, size, board);
    }
    _drawSelectedNode(canvas, size);
  }

  void _drawLines(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..color = boardLineColor
      ..strokeWidth = math.max(2, size.shortestSide * 0.007)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final List<List<int>> lines = hasDiagonalLines
        ? MillBoardCoordinateMaps.diagonalMillNodeLines
        : MillBoardCoordinateMaps.standardMillNodeLines;
    for (final List<int> line in lines) {
      final Path path = Path();
      for (int i = 0; i < line.length; i++) {
        final Offset p = MillBoardGeometry.nodeOffset(line[i], size);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, linePaint);
    }
  }

  void _drawPoints(Canvas canvas, Size size) {
    final Paint pointPaint = Paint()..color = boardLineColor;
    final double radius = size.shortestSide * 0.013;
    for (int node = 0; node < MillBoardGeometry.nodeCount; node++) {
      canvas.drawCircle(
        MillBoardGeometry.nodeOffset(node, size),
        radius,
        pointPaint,
      );
    }
  }

  void _drawHints(
    Canvas canvas,
    Size size,
    Set<int> nodes,
    Color color, {
    required bool filled,
  }) {
    if (nodes.isEmpty) {
      return;
    }
    final Paint paint = Paint()
      ..color = color.withValues(alpha: filled ? 0.24 : 0.82)
      ..strokeWidth = math.max(2, size.shortestSide * 0.006)
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke;
    final double radius = size.shortestSide * (filled ? 0.035 : 0.052);
    for (final int node in nodes) {
      canvas.drawCircle(
        MillBoardGeometry.nodeOffset(node, size),
        radius,
        paint,
      );
    }
  }

  void _drawPieces(
    Canvas canvas,
    Size size,
    NativeMillSnapshotBoardView board,
  ) {
    final double radius = size.shortestSide * 0.052;
    final Paint shadowPaint = Paint()
      ..color = shadowColor.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final Paint outlinePaint = Paint()
      ..color = boardLineColor.withValues(alpha: 0.55)
      ..strokeWidth = math.max(1, size.shortestSide * 0.004)
      ..style = PaintingStyle.stroke;

    for (int node = 0; node < MillBoardGeometry.nodeCount; node++) {
      final PlayerSeat? seat = board.pieceAtNode(node);
      if (seat == null) {
        continue;
      }
      final Offset center = MillBoardGeometry.nodeOffset(node, size);
      final Color pieceColor = seat == PlayerSeat.first
          ? whitePieceColor
          : blackPieceColor;
      final Paint piecePaint = Paint()..color = pieceColor;
      canvas.drawCircle(center.translate(1.5, 2), radius, shadowPaint);
      canvas.drawCircle(center, radius, piecePaint);
      canvas.drawCircle(center, radius, outlinePaint);
      if (board.markedNodes.contains(node)) {
        final Paint markedPaint = Paint()
          ..color = pieceHighlightColor
          ..strokeWidth = math.max(2, size.shortestSide * 0.007)
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(center, radius * 1.22, markedPaint);
      }
    }
  }

  void _drawSelectedNode(Canvas canvas, Size size) {
    final String? selected = selectedFrom;
    if (selected == null || selected.isEmpty) {
      return;
    }
    final int node = MillBoardCoordinateMaps.notationToNode(selected);
    if (node < 0) {
      return;
    }
    final Paint paint = Paint()
      ..color = hintColor
      ..strokeWidth = math.max(2, size.shortestSide * 0.009)
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(
      MillBoardGeometry.nodeOffset(node, size),
      size.shortestSide * 0.068,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _OpeningExplorerBoardPainter oldDelegate) {
    return oldDelegate.snapshot != snapshot ||
        oldDelegate.selectedFrom != selectedFrom ||
        oldDelegate.legalHints != legalHints ||
        oldDelegate.hasDiagonalLines != hasDiagonalLines ||
        oldDelegate.boardBackgroundColor != boardBackgroundColor ||
        oldDelegate.boardLineColor != boardLineColor ||
        oldDelegate.whitePieceColor != whitePieceColor ||
        oldDelegate.blackPieceColor != blackPieceColor ||
        oldDelegate.pieceHighlightColor != pieceHighlightColor ||
        oldDelegate.hintColor != hintColor ||
        oldDelegate.removeHintColor != removeHintColor;
  }
}

class _PositionSection extends StatelessWidget {
  const _PositionSection({required this.snapshot});

  final _OpeningExplorerSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return LichessListSection(
      header: Text(strings.openingExplorerCurrentPosition),
      cardKey: const Key('opening_explorer_position_card'),
      children: <Widget>[
        ListTile(
          key: const Key('opening_explorer_position_fen'),
          leading: const Icon(Icons.location_searching_rounded),
          title: Text(strings.copyFen),
          subtitle: Text(
            snapshot.fen,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant.withValues(
                alpha: AppStyles.subtitleOpacity,
              ),
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: snapshot.fen));
            SnackBarService.showRootSnackBar(strings.fenCopiedToClipboard);
          },
        ),
        ListTile(
          key: const Key('opening_explorer_position_sources'),
          leading: const Icon(Icons.data_object_rounded),
          title: Text(strings.openingExplorerSources),
          subtitle: Text(snapshot.sourceSummary(strings)),
        ),
      ],
    );
  }
}

class _OpeningMoveTile extends StatelessWidget {
  const _OpeningMoveTile({
    required this.index,
    required this.move,
    required this.onSelected,
  });

  final int index;
  final _OpeningExplorerMove move;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TextStyle sourceStyle =
        theme.textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(
            alpha: AppStyles.subtitleOpacity,
          ),
          letterSpacing: 0,
        ) ??
        AppStyles.tileSubtitle.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(
            alpha: AppStyles.subtitleOpacity,
          ),
        );

    return ColoredBox(
      color: _openingExplorerRowColor(context, index),
      child: InkWell(
        key: Key('opening_explorer_move_${move.notation}'),
        onTap: onSelected,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: <Widget>[
              Expanded(flex: 20, child: _MoveCell(move: move)),
              const SizedBox(width: 8),
              Expanded(flex: 35, child: _MoveGamesCell(move: move)),
              const SizedBox(width: 8),
              Expanded(
                flex: 45,
                child: move.humanStats == null
                    ? Text(
                        _sourceOnlySubtitle(strings, move),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: sourceStyle,
                      )
                    : _HumanStatsBar(stats: move.humanStats!),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _sourceOnlySubtitle(S strings, _OpeningExplorerMove move) {
    if (move.isPerfectMove && move.bookRank != null) {
      return '${strings.openingExplorerPerfectMove} · '
          '${strings.openingExplorerBookMove} #${move.bookRank! + 1}';
    }
    if (move.isPerfectMove) {
      return strings.openingExplorerPerfectMove;
    }
    if (move.bookRank != null) {
      return '${strings.openingExplorerBookMove} #${move.bookRank! + 1}';
    }
    return strings.openingExplorerNoData;
  }
}

class _OpeningExplorerMovesHeader extends StatelessWidget {
  const _OpeningExplorerMovesHeader();

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextStyle style =
        Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ) ??
        AppStyles.tileSubtitle.copyWith(color: colorScheme.onSurfaceVariant);

    return ColoredBox(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.62),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: <Widget>[
            Expanded(flex: 20, child: Text(strings.move, style: style)),
            const SizedBox(width: 8),
            Expanded(
              flex: 35,
              child: Text(
                strings.openingExplorerGames,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 45,
              child: Text(
                '${strings.wins} / ${strings.draws} / ${strings.losses}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoveCell extends StatelessWidget {
  const _MoveCell({required this.move});

  final _OpeningExplorerMove move;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          move.notation,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 5,
          runSpacing: 4,
          children: <Widget>[
            if (move.isPerfectMove)
              _SourceBadge(
                label: strings.perfectDatabaseSettings,
                color: colorScheme.primary,
                icon: Icons.verified_rounded,
              ),
            if (move.bookRank != null)
              _SourceBadge(
                label: strings.openingBookSettings,
                color: colorScheme.tertiary,
                icon: Icons.menu_book_rounded,
              ),
            if (move.humanStats != null)
              _SourceBadge(
                label: strings.humanGameDatabaseSettings,
                color: colorScheme.secondary,
                icon: Icons.people_alt_rounded,
              ),
          ],
        ),
      ],
    );
  }
}

class _MoveGamesCell extends StatelessWidget {
  const _MoveGamesCell({required this.move});

  final _OpeningExplorerMove move;

  @override
  Widget build(BuildContext context) {
    final _HumanMoveStats? stats = move.humanStats;
    final String text = _formatExplorerGamesText(
      games: stats?.total ?? 0,
      percent: stats == null ? 0 : move.gamesPercent,
    );
    final TextStyle? style = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      letterSpacing: 0,
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(text, maxLines: 1, style: style),
      ),
    );
  }
}

class _OpeningExplorerTotalTile extends StatelessWidget {
  const _OpeningExplorerTotalTile({
    required this.stats,
    required this.rowIndex,
  });

  final _HumanMoveStats stats;
  final int rowIndex;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextStyle textStyle =
        Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ) ??
        AppStyles.tileSubtitle.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        );

    return ColoredBox(
      color: _openingExplorerRowColor(context, rowIndex),
      child: Padding(
        key: const Key('opening_explorer_total_row'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: <Widget>[
            Expanded(
              flex: 20,
              child: Icon(
                Icons.functions,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 35,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _formatExplorerGamesText(games: stats.total, percent: 100),
                    maxLines: 1,
                    style: textStyle,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(flex: 45, child: _HumanStatsBar(stats: stats)),
          ],
        ),
      ),
    );
  }
}

Color _openingExplorerRowColor(BuildContext context, int index) {
  final AppCustomColors? customColors = Theme.of(
    context,
  ).extension<AppCustomColors>();
  assert(customColors != null, 'Opening explorer requires AppCustomColors.');
  return index.isEven ? customColors!.rowEven : customColors!.rowOdd;
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: SizedBox.square(
            dimension: 22,
            child: Icon(icon, size: 14, color: color),
          ),
        ),
      ),
    );
  }
}

class _HumanStatsBar extends StatelessWidget {
  const _HumanStatsBar({required this.stats});

  final _HumanMoveStats stats;

  @override
  Widget build(BuildContext context) {
    final int total = stats.total;
    if (total <= 0) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 20,
        child: Row(
          children: <Widget>[
            if (stats.wins > 0)
              _HumanStatsBarSegment(
                count: stats.wins,
                total: total,
                flex: _explorerBarFlex(stats.wins, total),
                color: _explorerWinBoxColor(context),
                textColor: Colors.black,
              ),
            if (stats.draws > 0)
              _HumanStatsBarSegment(
                count: stats.draws,
                total: total,
                flex: _explorerBarFlex(stats.draws, total),
                color: Colors.grey,
                textColor: Colors.white,
              ),
            if (stats.losses > 0)
              _HumanStatsBarSegment(
                count: stats.losses,
                total: total,
                flex: _explorerBarFlex(stats.losses, total),
                color: _explorerLossBoxColor(context),
                textColor: Colors.white,
              ),
          ],
        ),
      ),
    );
  }
}

Color _explorerWinBoxColor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? Colors.white.withValues(alpha: 0.8)
      : Colors.white;
}

Color _explorerLossBoxColor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.light
      ? Colors.black.withValues(alpha: 0.7)
      : Colors.black;
}

String _formatExplorerSampleCount(int count) {
  assert(count >= 0, 'Opening explorer sample count must not be negative.');
  return NumberFormat.decimalPatternDigits().format(count);
}

String _formatExplorerGamesText({required int games, required int percent}) {
  assert(games >= 0, 'Opening explorer games count must not be negative.');
  assert(percent >= 0, 'Opening explorer games percent must not be negative.');
  return '${_formatExplorerSampleCount(games)} ($percent%)';
}

int _explorerBarFlex(int count, int total) {
  assert(count > 0, 'Opening explorer bar segment count must be positive.');
  assert(total > 0, 'Opening explorer bar total must be positive.');
  assert(count <= total, 'Opening explorer bar segment cannot exceed total.');
  return math.max(1, (count * 1000 / total).round());
}

class _HumanStatsBarSegment extends StatelessWidget {
  const _HumanStatsBarSegment({
    required this.count,
    required this.total,
    required this.flex,
    required this.color,
    required this.textColor,
  });

  final int count;
  final int total;
  final int flex;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final int percent = (count * 100 / total).round();
    return Expanded(
      flex: flex,
      child: ColoredBox(
        color: color,
        child: Center(
          child: Text(
            percent < 20 ? '' : '$percent%',
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _OpeningExplorerMessage extends StatelessWidget {
  const _OpeningExplorerMessage({required this.message, this.inList = false});

  final String message;
  final bool inList;

  @override
  Widget build(BuildContext context) {
    final Widget child = Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );

    if (inList) {
      return LichessListSection(hasLeading: false, children: <Widget>[child]);
    }
    return child;
  }
}

class _OpeningExplorerSnapshot {
  const _OpeningExplorerSnapshot({
    required this.fen,
    required this.isRuleSupported,
    required this.openingBookMoveCount,
    required this.humanDatabaseMoveCount,
    required this.perfectMoveAvailable,
    required this.aggregateHumanStats,
    required this.moves,
  });

  factory _OpeningExplorerSnapshot.fromSession({
    required NativeMillGameSession session,
    required RuleSettings ruleSettings,
    required GeneralSettings generalSettings,
  }) {
    final String fen = session.getFen();
    final bool isRuleSupported =
        ruleSettings.isLikelyNineMensMorris() || ruleSettings.isLikelyElFilja();
    final Map<String, GameAction> legalActions = <String, GameAction>{};
    for (final GameAction action in session.legalActions) {
      final String? notation = MillActionCodec.moveStringFrom(action);
      if (notation != null && notation.isNotEmpty) {
        legalActions.putIfAbsent(notation, () => action);
      }
    }

    final Map<String, _OpeningExplorerMove> moves =
        <String, _OpeningExplorerMove>{};
    _OpeningExplorerMove ensureMove(String notation) {
      final GameAction? action = legalActions[notation];
      assert(
        action != null,
        'Opening explorer move must map to a legal action.',
      );
      if (action == null) {
        throw StateError('Opening explorer move is not legal: $notation');
      }
      return moves.putIfAbsent(
        notation,
        () => _OpeningExplorerMove(notation: notation, action: action),
      );
    }

    int openingBookMoveCount = 0;
    if (isRuleSupported && session.state.value.phase == 'placing') {
      final Map<String, List<String>> book = OpeningBookRepository.instance
          .oracleFor(isElFilja: ruleSettings.isLikelyElFilja());
      final List<String>? bookMoves = lookupCanonicalOpeningBook(
        book,
        normalizeOpeningBookFen(fen),
      );
      if (bookMoves != null) {
        for (int i = 0; i < bookMoves.length; i++) {
          final String notation = bookMoves[i];
          if (!legalActions.containsKey(notation)) {
            continue;
          }
          openingBookMoveCount++;
          ensureMove(notation).bookRank ??= i;
        }
      }
    }

    int humanDatabaseMoveCount = 0;
    if (_canQueryHumanDatabase(session, ruleSettings, generalSettings)) {
      final HumanDatabaseReadyResult ready = HumanDatabaseService.instance
          .ensureReadySync(generalSettings.humanDatabaseFilePath);
      if (ready.ready) {
        final tgf.MillHumanDatabaseQuery query = tgf.millHumanDbQuery(
          fen: fen,
          maxMoves: 24,
          minSamples: MillHumanDatabaseProvider.minSamplesForSkill(
            generalSettings.skillLevel,
          ),
        );
        if (query.available) {
          for (final tgf.MillHumanDatabaseMove humanMove in query.moves) {
            final String notation = _baseMoveFromHumanDatabase(
              humanMove.notation,
            );
            if (!legalActions.containsKey(notation)) {
              continue;
            }
            humanDatabaseMoveCount++;
            ensureMove(notation).humanStats = _HumanMoveStats(
              wins: humanMove.wins,
              losses: humanMove.losses,
              draws: humanMove.draws,
              total: humanMove.total,
              scoreDelta: humanMove.scoreDelta,
            );
          }
        }
      }
    }

    bool perfectMoveAvailable = false;
    // ignore: deprecated_member_use
    if (generalSettings.usePerfectDatabase) {
      final GameAction? perfectAction = session.perfectDatabaseBestAction(
        engineSettings: generalSettings,
      );
      if (perfectAction != null) {
        final String? notation = MillActionCodec.moveStringFrom(perfectAction);
        if (notation != null && legalActions.containsKey(notation)) {
          perfectMoveAvailable = true;
          ensureMove(notation).isPerfectMove = true;
        }
      }
    }

    final List<_OpeningExplorerMove> sortedMoves = moves.values.toList();
    sortedMoves.sort(_compareExplorerMoves);
    final int totalHumanSamples = sortedMoves.fold<int>(
      0,
      (int total, _OpeningExplorerMove move) =>
          total + (move.humanStats?.total ?? 0),
    );
    final _HumanMoveStats? aggregateHumanStats = totalHumanSamples <= 0
        ? null
        : _HumanMoveStats(
            wins: sortedMoves.fold<int>(
              0,
              (int total, _OpeningExplorerMove move) =>
                  total + (move.humanStats?.wins ?? 0),
            ),
            losses: sortedMoves.fold<int>(
              0,
              (int total, _OpeningExplorerMove move) =>
                  total + (move.humanStats?.losses ?? 0),
            ),
            draws: sortedMoves.fold<int>(
              0,
              (int total, _OpeningExplorerMove move) =>
                  total + (move.humanStats?.draws ?? 0),
            ),
            total: totalHumanSamples,
            scoreDelta: 0,
          );
    for (final _OpeningExplorerMove move in sortedMoves) {
      final int total = move.humanStats?.total ?? 0;
      move.gamesPercent = totalHumanSamples <= 0
          ? 0
          : (total * 100 / totalHumanSamples).round();
    }

    return _OpeningExplorerSnapshot(
      fen: fen,
      isRuleSupported: isRuleSupported,
      openingBookMoveCount: openingBookMoveCount,
      humanDatabaseMoveCount: humanDatabaseMoveCount,
      perfectMoveAvailable: perfectMoveAvailable,
      aggregateHumanStats: aggregateHumanStats,
      moves: sortedMoves,
    );
  }

  final String fen;
  final bool isRuleSupported;
  final int openingBookMoveCount;
  final int humanDatabaseMoveCount;
  final bool perfectMoveAvailable;
  final _HumanMoveStats? aggregateHumanStats;
  final List<_OpeningExplorerMove> moves;

  String sourceSummary(S strings) {
    final List<String> parts = <String>[
      '${strings.openingBookSettings}: $openingBookMoveCount',
      '${strings.humanGameDatabaseSettings}: $humanDatabaseMoveCount',
      '${strings.perfectDatabaseSettings}: ${perfectMoveAvailable ? strings.openingExplorerAvailable : strings.openingExplorerNoDataShort}',
    ];
    return parts.join(' · ');
  }

  static bool _canQueryHumanDatabase(
    NativeMillGameSession session,
    RuleSettings ruleSettings,
    GeneralSettings generalSettings,
  ) {
    if (!generalSettings.humanDatabaseEnabled ||
        generalSettings.humanDatabaseFilePath.trim().isEmpty ||
        session.outcome.isTerminal) {
      return false;
    }
    if (!_supportsHumanDatabaseRules(ruleSettings)) {
      return false;
    }
    return !session.legalActions.any(
      (GameAction action) => action.type == MillActionTypes.remove,
    );
  }

  static bool _supportsHumanDatabaseRules(RuleSettings ruleSettings) {
    return ruleSettings.isLikelyNineMensMorris() &&
        ruleSettings.flyPieceCount == 3 &&
        ruleSettings.mayFly &&
        !ruleSettings.mayRemoveMultiple &&
        !ruleSettings.mayRemoveFromMillsAlways;
  }

  static String _baseMoveFromHumanDatabase(String notation) {
    final int captureIndex = notation.indexOf('x');
    if (captureIndex < 0) {
      return notation;
    }
    final String baseMove = notation.substring(0, captureIndex);
    assert(
      baseMove.isNotEmpty,
      'Human Database move notation must include a base move.',
    );
    return baseMove;
  }

  static int _compareExplorerMoves(
    _OpeningExplorerMove a,
    _OpeningExplorerMove b,
  ) {
    if (a.isPerfectMove != b.isPerfectMove) {
      return a.isPerfectMove ? -1 : 1;
    }
    final int bookCompare = _compareNullableRank(a.bookRank, b.bookRank);
    if (bookCompare != 0) {
      return bookCompare;
    }
    final int humanTotalCompare = (b.humanStats?.total ?? 0).compareTo(
      a.humanStats?.total ?? 0,
    );
    if (humanTotalCompare != 0) {
      return humanTotalCompare;
    }
    final int humanScoreCompare = (b.humanStats?.scoreDelta ?? 0).compareTo(
      a.humanStats?.scoreDelta ?? 0,
    );
    if (humanScoreCompare != 0) {
      return humanScoreCompare;
    }
    return a.notation.compareTo(b.notation);
  }

  static int _compareNullableRank(int? a, int? b) {
    if (a == null && b == null) {
      return 0;
    }
    if (a == null) {
      return 1;
    }
    if (b == null) {
      return -1;
    }
    return a.compareTo(b);
  }
}

class _OpeningExplorerMove {
  _OpeningExplorerMove({required this.notation, required this.action});

  final String notation;
  final GameAction action;
  int? bookRank;
  _HumanMoveStats? humanStats;
  int gamesPercent = 0;
  bool isPerfectMove = false;
}

class _HumanMoveStats {
  const _HumanMoveStats({
    required this.wins,
    required this.losses,
    required this.draws,
    required this.total,
    required this.scoreDelta,
  }) : assert(wins >= 0, 'Human Database wins must not be negative.'),
       assert(losses >= 0, 'Human Database losses must not be negative.'),
       assert(draws >= 0, 'Human Database draws must not be negative.'),
       assert(total >= 0, 'Human Database total must not be negative.'),
       assert(
         total == wins + losses + draws,
         'Human Database total must equal wins + draws + losses.',
       );

  final int wins;
  final int losses;
  final int draws;
  final int total;
  final double scoreDelta;
}
