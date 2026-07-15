// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../appearance_settings/models/color_settings.dart';
import '../../../game_page/services/mill.dart'
    show ExtMove, GameController, GameMode, MoveType;
import '../../../game_page/services/transform/transform.dart';
import '../../../game_page/widgets/game_page.dart';
import '../../../game_platform/game_session.dart';
import '../../../general_settings/models/general_settings.dart';
import '../../../generated/intl/l10n.dart';
import '../../../rule_settings/models/rule_settings.dart';
import '../../../shared/database/database.dart' show DB;
import '../../../shared/services/human_database_service.dart';
import '../../../shared/services/logger.dart';
import '../../../shared/services/snackbar_service.dart';
import '../../../shared/themes/app_styles.dart';
import '../../../shared/themes/app_theme.dart';
import '../../../shared/widgets/lichess_action_sheet.dart';
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
import '../opening_book/mill_opening_recognizer.dart';
import '../opening_book/opening_book_models.dart';
import '../opening_book/opening_book_repository.dart';

typedef OpeningExplorerMoveSelected = Future<bool> Function(GameAction action);

class OpeningExplorerPage extends StatefulWidget {
  const OpeningExplorerPage({
    super.key,
    this.session,
    this.startFromSession = false,
    this.embedded = false,
    this.showBoard = true,
    this.onMoveSelected,
  });

  final GameSession? session;
  final bool startFromSession;
  final bool embedded;
  final bool showBoard;
  final OpeningExplorerMoveSelected? onMoveSelected;

  @override
  State<OpeningExplorerPage> createState() => _OpeningExplorerPageState();
}

typedef _OpeningExplorerPositionChanged =
    void Function({
      required String previousFen,
      required String currentFen,
      required String label,
    });

typedef _OpeningExplorerTransformSelected =
    void Function(TransformationType type, String label);

const int _explorerMoveColumnFlex = 15;
const int _explorerGamesColumnFlex = 35;
const int _explorerStatsColumnFlex = 50;
const double _explorerColumnGap = 8;
const List<String> _openingExplorerVerticalCoordinates = <String>[
  '7',
  '6',
  '5',
  '4',
  '3',
  '2',
  '1',
];
const List<String> _openingExplorerHorizontalCoordinates = <String>[
  'a',
  'b',
  'c',
  'd',
  'e',
  'f',
  'g',
];

/// Sentinel used only for sorting engine-backfill rows: any real evaluation
/// outranks a missing one.
const int _engineScoreFloor = -1 << 30;

/// Search parameters for the engine heuristic-fill backfill. Deliberately a
/// small, fixed budget independent of the user's Analysis-panel settings:
/// this runs automatically in the background whenever the book/human/perfect
/// sources have nothing at all for the current position, so it must stay
/// fast rather than reflect the user's (possibly much longer) deliberate
/// analysis time preference.
const int _explorerEngineBackfillDepth = 20;
const int _explorerEngineBackfillMoveLimitMs = 1200;
const int _explorerEngineBackfillLineCount = 4;
const String _openingExplorerLogTag = '[OpeningExplorer]';

/// Delay between plies while "watching a line play out".
const Duration _explorerLinePlaybackStepInterval = Duration(milliseconds: 650);

class _OpeningExplorerHistoryEntry {
  const _OpeningExplorerHistoryEntry({required this.label, required this.fen});

  final String label;
  final String fen;
}

String _openingExplorerLabelFromAction(GameAction action) {
  final String? label = MillActionCodec.moveStringFrom(action);
  assert(
    label != null && label.isNotEmpty,
    'Opening explorer action must provide move notation.',
  );
  if (label == null || label.isEmpty) {
    throw StateError('Opening explorer action must provide move notation.');
  }
  return label;
}

List<String> _placementMovesFromRecorder(List<ExtMove> moves) {
  return <String>[
    for (final ExtMove move in moves)
      if (move.type == MoveType.place && _isPlacementMoveLabel(move.move))
        move.move,
  ];
}

bool _isPlacementMoveLabel(String label) {
  return !label.startsWith('x') &&
      !label.contains('-') &&
      MillBoardCoordinateMaps.notationToNode(label) >= 0;
}

class _OpeningExplorerPageState extends State<OpeningExplorerPage> {
  late final Future<void> _openingBookLoad = OpeningBookRepository.instance
      .ensureLoaded();
  final MillSessionTapController _tapController = MillSessionTapController();
  final List<_OpeningExplorerHistoryEntry> _explorerHistory =
      <_OpeningExplorerHistoryEntry>[];
  NativeMillGameSession? _explorerSession;
  ValueListenable<GameStateSnapshot>? _sourceState;
  String? _initialExplorerFen;
  String? _lastSourceFen;
  List<String> _initialPlacementMoves = const <String>[];
  int _explorerCursor = 0;

  // Engine heuristic-fill state (see `_maybeStartEngineBackfill`). Keyed by
  // FEN so a stale result never gets applied after the user has already
  // navigated elsewhere by the time the background search completes.
  String? _engineFillFen;
  List<NativeMillPrincipalVariation> _engineFillMoves =
      const <NativeMillPrincipalVariation>[];
  bool _engineFillInFlight = false;

  // "Watch it play out" line-playback state. `_linePlaybackToken` is bumped
  // on every start/stop so an in-flight async playback loop can notice it
  // has been superseded or cancelled without needing a raw `Timer` handle.
  bool _isLinePlaybackActive = false;
  int _linePlaybackToken = 0;

  @override
  void initState() {
    super.initState();
    _attachSourceStateListener();
    _recreateExplorerSession();
  }

  @override
  void didUpdateWidget(covariant OpeningExplorerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.session, oldWidget.session) ||
        widget.startFromSession != oldWidget.startFromSession ||
        widget.embedded != oldWidget.embedded) {
      _detachSourceStateListener();
      _attachSourceStateListener();
      _recreateExplorerSession();
    }
  }

  @override
  void dispose() {
    _detachSourceStateListener();
    _linePlaybackToken++;
    _explorerSession?.dispose();
    super.dispose();
  }

  NativeMillGameSession? _sourceNativeSession() {
    if (!widget.startFromSession) {
      return null;
    }
    final GameSession? source = widget.session;
    return source is NativeMillGameSession ? source : null;
  }

  void _attachSourceStateListener() {
    if (!widget.embedded) {
      return;
    }
    final NativeMillGameSession? source = _sourceNativeSession();
    if (source == null) {
      _lastSourceFen = null;
      return;
    }
    _sourceState = source.state;
    _lastSourceFen = source.getFen();
    _sourceState!.addListener(_handleSourceStateChanged);
  }

  void _detachSourceStateListener() {
    _sourceState?.removeListener(_handleSourceStateChanged);
    _sourceState = null;
  }

  void _handleSourceStateChanged() {
    final NativeMillGameSession? source = _sourceNativeSession();
    if (source == null) {
      return;
    }
    final String sourceFen = source.getFen();
    if (sourceFen == _lastSourceFen) {
      return;
    }
    _lastSourceFen = sourceFen;
    if (!mounted) {
      return;
    }
    setState(_recreateExplorerSession);
  }

  void _recreateExplorerSession() {
    _explorerSession?.dispose();
    _explorerSession = null;
    _initialExplorerFen = null;
    _initialPlacementMoves = const <String>[];
    _explorerHistory.clear();
    _explorerCursor = 0;
    _tapController.clearSelection();
    _engineFillFen = null;
    _engineFillMoves = const <NativeMillPrincipalVariation>[];
    _linePlaybackToken++;
    _isLinePlaybackActive = false;

    final NativeMillGameSession explorer = NativeMillGameSession(
      rules: DB().ruleSettings,
      generalSettings: DB().generalSettings,
    );
    final GameSession? source = widget.startFromSession ? widget.session : null;
    if (source is NativeMillGameSession) {
      _lastSourceFen = source.getFen();
      final bool loaded = explorer.loadFen(source.getFen());
      assert(loaded, 'Opening explorer source FEN must load into its session.');
      if (!loaded) {
        explorer.dispose();
        return;
      }
      if (identical(source, GameController().activeNativeMillSession)) {
        _initialPlacementMoves = _placementMovesFromRecorder(
          GameController().gameRecorder.currentPath,
        );
      }
    }
    _explorerSession = explorer;
    _initialExplorerFen = explorer.getFen();
  }

  List<String> _currentPlacementMoves() {
    return <String>[
      ..._initialPlacementMoves,
      for (final _OpeningExplorerHistoryEntry entry in _explorerHistory.take(
        _explorerCursor,
      ))
        if (_isPlacementMoveLabel(entry.label)) entry.label,
    ];
  }

  /// Kicks off a background heuristic-search backfill for [snapshot.fen]
  /// when the book/human/perfect sources found nothing at all. Safe to call
  /// from every `build()` (including the two independent snapshot
  /// constructions for the body and the bottom bar): the FEN/in-flight
  /// guards make repeated calls for the same position a no-op.
  void _maybeStartEngineBackfill(_OpeningExplorerSnapshot snapshot) {
    if (!snapshot.needsEngineFallback) {
      return;
    }
    if (_engineFillInFlight || _engineFillFen == snapshot.fen) {
      return;
    }
    unawaited(_runEngineBackfill(snapshot.fen));
  }

  Future<void> _runEngineBackfill(String fen) async {
    final NativeMillGameSession? session = _explorerSession;
    if (session == null) {
      return;
    }
    _engineFillInFlight = true;
    try {
      final List<NativeMillPrincipalVariation> variations = await session
          .searchPrincipalVariations(
            depth: _explorerEngineBackfillDepth,
            moveLimitMs: _explorerEngineBackfillMoveLimitMs,
            multiPv: _explorerEngineBackfillLineCount,
            engineSettings: DB().generalSettings,
          );
      // The explorer may have navigated away (or even torn down its
      // session) while the search was running; only apply a result that
      // still matches where the user currently is.
      if (!mounted ||
          !identical(session, _explorerSession) ||
          session.getFen() != fen) {
        return;
      }
      setState(() {
        _engineFillFen = fen;
        _engineFillMoves = variations;
      });
    } on Object catch (e) {
      logger.w('$_openingExplorerLogTag engine backfill failed for $fen: $e');
    } finally {
      _engineFillInFlight = false;
    }
  }

  List<NativeMillPrincipalVariation> _engineSuggestionsFor(String fen) {
    return _engineFillFen == fen
        ? _engineFillMoves
        : const <NativeMillPrincipalVariation>[];
  }

  /// The standard starting FEN for the currently active rule settings. Used
  /// to rewind the board before "watching a line play out", since named
  /// opening lines are always placement sequences from an empty board,
  /// regardless of where the explorer currently happens to be browsing.
  String _standardInitialFen() {
    final NativeMillGameSession scratch = NativeMillGameSession(
      rules: DB().ruleSettings,
      generalSettings: DB().generalSettings,
    );
    final String fen = scratch.getFen();
    scratch.dispose();
    return fen;
  }

  /// Plays [moves] one at a time on the explorer's own session, starting
  /// from the standard empty board, pausing [_explorerLinePlaybackStepInterval]
  /// between plies so the user can watch the line unfold. Stops early and
  /// cleanly if the explorer is disposed, the session is recreated, or
  /// [_stopLinePlayback] is called (including implicitly, by starting a new
  /// playback before this one finishes).
  Future<void> _startLinePlayback(List<String> moves) async {
    final NativeMillGameSession? session = _explorerSession;
    if (session == null || moves.isEmpty) {
      return;
    }
    final int token = ++_linePlaybackToken;
    final bool loaded = session.loadFen(_standardInitialFen());
    assert(loaded, 'Opening explorer line playback needs a fresh start FEN.');
    if (!loaded) {
      return;
    }
    setState(() {
      _explorerHistory.clear();
      _explorerCursor = 0;
      _tapController.clearSelection();
      _isLinePlaybackActive = true;
    });

    for (final String notation in moves) {
      if (!mounted || token != _linePlaybackToken) {
        return;
      }
      await Future<void>.delayed(_explorerLinePlaybackStepInterval);
      if (!mounted || token != _linePlaybackToken) {
        return;
      }
      GameAction? action;
      for (final GameAction candidate in session.legalActions) {
        if (MillActionCodec.moveStringFrom(candidate) == notation) {
          action = candidate;
          break;
        }
      }
      if (action == null) {
        // The line no longer matches a legal move under the active rule
        // set (e.g. rules changed since the book line was curated); stop
        // cleanly at whatever position playback reached.
        break;
      }
      final String previousFen = session.getFen();
      await session.apply(action);
      if (!mounted || token != _linePlaybackToken) {
        return;
      }
      _recordExplorerPositionChange(
        previousFen: previousFen,
        currentFen: session.getFen(),
        label: notation,
      );
    }

    if (mounted && token == _linePlaybackToken) {
      setState(() => _isLinePlaybackActive = false);
    }
  }

  void _stopLinePlayback() {
    _linePlaybackToken++;
    if (_isLinePlaybackActive) {
      setState(() => _isLinePlaybackActive = false);
    }
  }

  void _showPracticeSheet(BuildContext context) {
    final NativeMillGameSession? session = _explorerSession;
    if (session == null) {
      return;
    }
    final bool isElFilja = DB().ruleSettings.isLikelyElFilja();
    final List<OpeningEntry> openings = OpeningBookRepository.instance
        .openingsFor(isElFilja: isElFilja);
    final List<String> currentLine = <String>[
      for (final _OpeningExplorerHistoryEntry entry in _explorerHistory.take(
        _explorerCursor,
      ))
        entry.label,
    ];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) {
        return _OpeningExplorerPracticeSheet(
          openings: openings,
          currentLine: currentLine,
          onSelectLine: (List<String> moves) {
            Navigator.of(sheetContext).pop();
            unawaited(_startLinePlayback(moves));
          },
          onContinueVsAi: (GameMode mode) {
            Navigator.of(sheetContext).pop();
            _continueVsAi(context, mode: mode);
          },
        );
      },
    );
  }

  void _continueVsAi(BuildContext context, {required GameMode mode}) {
    final NativeMillGameSession? session = _explorerSession;
    if (session == null) {
      return;
    }
    _stopLinePlayback();
    final String fen = session.getFen();
    final bool started = GameController().startGameFromFen(
      mode: mode,
      fen: fen,
    );
    assert(started, 'Opening explorer practice must start from its own FEN.');
    if (!started) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/openingExplorerPractice/${mode.name}'),
        builder: (BuildContext routeContext) =>
            _OpeningExplorerContinueGameRoute(mode: mode),
      ),
    );
  }

  Future<void> _applyExplorerAction(GameAction action) async {
    final OpeningExplorerMoveSelected? applyToSource = widget.onMoveSelected;
    if (applyToSource != null) {
      final bool applied = await applyToSource(action);
      assert(applied, 'Embedded opening explorer move must apply to source.');
      return;
    }

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
        label: _openingExplorerLabelFromAction(action),
      );
    }
  }

  void _transformExplorerPosition(TransformationType type, String label) {
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
      label: label,
    );
  }

  void _recordExplorerPositionChange({
    required String previousFen,
    required String currentFen,
    required String label,
  }) {
    assert(previousFen.isNotEmpty, 'Explorer previous FEN must not be empty.');
    assert(currentFen.isNotEmpty, 'Explorer current FEN must not be empty.');
    assert(label.isNotEmpty, 'Explorer history label must not be empty.');
    if (previousFen == currentFen) {
      setState(() {});
      return;
    }
    if (_explorerCursor < _explorerHistory.length) {
      _explorerHistory.removeRange(_explorerCursor, _explorerHistory.length);
    }
    _explorerHistory.add(
      _OpeningExplorerHistoryEntry(label: label, fen: currentFen),
    );
    _explorerCursor = _explorerHistory.length;
    setState(() {});
  }

  String _fenAtExplorerCursor(int cursor) {
    assert(cursor >= 0, 'Explorer cursor must not be negative.');
    assert(
      cursor <= _explorerHistory.length,
      'Explorer cursor cannot exceed history length.',
    );
    final String? initialFen = _initialExplorerFen;
    assert(initialFen != null, 'Explorer initial FEN must be recorded.');
    if (initialFen == null) {
      throw StateError('Explorer initial FEN must be recorded.');
    }
    if (cursor == 0) {
      return initialFen;
    }
    return _explorerHistory[cursor - 1].fen;
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
    if (_explorerCursor <= 0) {
      return;
    }
    final String previousFen = _fenAtExplorerCursor(_explorerCursor - 1);
    if (!_restoreExplorerFen(previousFen)) {
      return;
    }
    _explorerCursor--;
    setState(() {});
  }

  void _goToNextExplorerPosition() {
    if (_explorerCursor >= _explorerHistory.length) {
      return;
    }
    final String nextFen = _fenAtExplorerCursor(_explorerCursor + 1);
    if (!_restoreExplorerFen(nextFen)) {
      return;
    }
    _explorerCursor++;
    setState(() {});
  }

  void _jumpToExplorerPosition(int cursor) {
    assert(cursor >= 0, 'Explorer move-list cursor must not be negative.');
    assert(
      cursor <= _explorerHistory.length,
      'Explorer move-list cursor cannot exceed history length.',
    );
    if (cursor == _explorerCursor) {
      return;
    }
    if (!_restoreExplorerFen(_fenAtExplorerCursor(cursor))) {
      return;
    }
    _explorerCursor = cursor;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final NativeMillGameSession? session = _explorerSession;
    final Widget body = session != null
        ? ValueListenableBuilder<GameStateSnapshot>(
            valueListenable: session.state,
            builder:
                (BuildContext context, GameStateSnapshot _, Widget? child) {
                  return FutureBuilder<void>(
                    future: _openingBookLoad,
                    builder:
                        (
                          BuildContext context,
                          AsyncSnapshot<void> openingBookSnapshot,
                        ) {
                          final _OpeningExplorerSnapshot snapshot =
                              _OpeningExplorerSnapshot.fromSession(
                                session: session,
                                ruleSettings: DB().ruleSettings,
                                generalSettings: DB().generalSettings,
                                placementMoves: _currentPlacementMoves(),
                                engineSuggestions: _engineSuggestionsFor(
                                  session.getFen(),
                                ),
                              );
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => _maybeStartEngineBackfill(snapshot),
                          );
                          return _OpeningExplorerContent(
                            session: session,
                            snapshot: snapshot,
                            tapController: _tapController,
                            onMoveSelected: _applyExplorerAction,
                            onPositionChanged: _recordExplorerPositionChange,
                            showBoard: widget.showBoard,
                            isLoading:
                                openingBookSnapshot.connectionState !=
                                ConnectionState.done,
                            isEngineBackfilling:
                                snapshot.needsEngineFallback &&
                                _engineFillInFlight,
                          );
                        },
                  );
                },
          )
        : _OpeningExplorerMessage(message: strings.openingExplorerUnavailable);

    if (widget.embedded) {
      return KeyedSubtree(
        key: const Key('opening_explorer_embedded'),
        child: body,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.openingExplorer),
        bottom: session == null
            ? null
            : _OpeningExplorerMoveList(
                history: _explorerHistory,
                currentCursor: _explorerCursor,
                onSelected: _jumpToExplorerPosition,
              ),
      ),
      bottomNavigationBar: session == null
          ? null
          : ValueListenableBuilder<GameStateSnapshot>(
              valueListenable: session.state,
              builder:
                  (BuildContext context, GameStateSnapshot _, Widget? child) {
                    final _OpeningExplorerSnapshot snapshot =
                        _OpeningExplorerSnapshot.fromSession(
                          session: session,
                          ruleSettings: DB().ruleSettings,
                          generalSettings: DB().generalSettings,
                          placementMoves: _currentPlacementMoves(),
                          engineSuggestions: _engineSuggestionsFor(
                            session.getFen(),
                          ),
                        );
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _maybeStartEngineBackfill(snapshot),
                    );
                    return _OpeningExplorerBottomBar(
                      snapshot: snapshot,
                      canGoPrevious: _explorerCursor > 0,
                      canGoNext: _explorerCursor < _explorerHistory.length,
                      onPrevious: _goToPreviousExplorerPosition,
                      onNext: _goToNextExplorerPosition,
                      onTransform: _transformExplorerPosition,
                      isLinePlaybackActive: _isLinePlaybackActive,
                      onOpenPractice: _showPracticeSheet,
                      onStopPlayback: _stopLinePlayback,
                    );
                  },
            ),
      body: body,
    );
  }
}

class _OpeningExplorerMoveList extends StatelessWidget
    implements PreferredSizeWidget {
  const _OpeningExplorerMoveList({
    required this.history,
    required this.currentCursor,
    required this.onSelected,
  });

  final List<_OpeningExplorerHistoryEntry> history;
  final int currentCursor;
  final ValueChanged<int> onSelected;

  @override
  Size get preferredSize => const Size.fromHeight(40);

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextStyle? textStyle = Theme.of(context).textTheme.labelLarge
        ?.copyWith(letterSpacing: 0, fontWeight: FontWeight.w600);

    return DecoratedBox(
      key: const Key('opening_explorer_move_list'),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant),
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: SizedBox(
        height: preferredSize.height,
        child: history.isEmpty
            ? const SizedBox.expand()
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                itemBuilder: (BuildContext context, int index) {
                  final int cursor = index + 1;
                  final _OpeningExplorerHistoryEntry entry = history[index];
                  final bool selected = cursor == currentCursor;
                  return Semantics(
                    button: true,
                    selected: selected,
                    child: InkWell(
                      key: Key('opening_explorer_history_$cursor'),
                      borderRadius: BorderRadius.circular(
                        AppStyles.compactRadius,
                      ),
                      onTap: () => onSelected(cursor),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: selected
                              ? colorScheme.primaryContainer
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(
                            AppStyles.compactRadius,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          child: Text(
                            '$cursor. ${entry.label}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textStyle?.copyWith(
                              color: selected
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
                separatorBuilder: (BuildContext context, int index) =>
                    const SizedBox(width: 6),
                itemCount: history.length,
              ),
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
    required this.showBoard,
    required this.isLoading,
    required this.isEngineBackfilling,
  });

  final NativeMillGameSession session;
  final _OpeningExplorerSnapshot snapshot;
  final MillSessionTapController tapController;
  final ValueChanged<GameAction> onMoveSelected;
  final _OpeningExplorerPositionChanged onPositionChanged;
  final bool showBoard;
  final bool isLoading;
  final bool isEngineBackfilling;

  @override
  Widget build(BuildContext context) {
    return ListTileTheme.merge(
      iconColor: Theme.of(context).colorScheme.primary,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool useSideBySide =
              constraints.maxWidth >= 720 &&
              constraints.maxWidth > constraints.maxHeight;
          if (!showBoard) {
            return KeyedSubtree(
              key: const Key('opening_explorer_list'),
              child: ListView(
                key: const Key('opening_explorer_data_pane'),
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                children: _buildDataSections(context),
              ),
            );
          }
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
      if (!isLoading && snapshot.openingRecognition.isNamed)
        _OpeningNameSection(recognition: snapshot.openingRecognition),
      LichessListSection(
        header: Text(strings.openingExplorerMoves),
        cardKey: const Key('opening_explorer_moves_card'),
        children: <Widget>[
          const _OpeningExplorerMovesHeader(),
          if (isLoading)
            for (int index = 0; index < 6; index++)
              _OpeningExplorerLoadingTile(index: index)
          else if (snapshot.moves.isEmpty)
            isEngineBackfilling
                ? const _OpeningExplorerEngineSearchingTile()
                : const _OpeningExplorerNoDataTile()
          else ...<Widget>[
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
    final bool showPieceRows =
        DB().displaySettings.isUnplacedAndRemovedPiecesShown;
    return LichessListSection(
      hasLeading: false,
      cardKey: const Key('opening_explorer_board_card'),
      children: <Widget>[
        ValueListenableBuilder<GameStateSnapshot>(
          valueListenable: session.state,
          builder: (BuildContext context, GameStateSnapshot snapshot, _) {
            final _OpeningExplorerPieceCounts counts =
                _OpeningExplorerPieceCounts.fromSnapshot(
                  snapshot: snapshot,
                  piecesCount: DB().ruleSettings.piecesCount,
                );
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                children: <Widget>[
                  if (showPieceRows) ...<Widget>[
                    _ExplorerPieceCountRow(
                      key: const Key('opening_explorer_in_hand_row'),
                      firstKey: const Key(
                        'opening_explorer_first_in_hand_count',
                      ),
                      secondKey: const Key(
                        'opening_explorer_second_in_hand_count',
                      ),
                      firstCount: counts.firstInHand,
                      secondCount: counts.secondInHand,
                      muted: false,
                    ),
                    const SizedBox(height: 4),
                  ],
                  _OpeningExplorerBoard(
                    session: session,
                    tapController: tapController,
                    heightFactor: boardHeightFactor,
                    onPositionChanged: onPositionChanged,
                  ),
                  if (showPieceRows) ...<Widget>[
                    const SizedBox(height: 4),
                    _ExplorerPieceCountRow(
                      key: const Key('opening_explorer_removed_row'),
                      firstKey: const Key(
                        'opening_explorer_first_removed_count',
                      ),
                      secondKey: const Key(
                        'opening_explorer_second_removed_count',
                      ),
                      firstCount: counts.firstRemoved,
                      secondCount: counts.secondRemoved,
                      muted: true,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _OpeningExplorerPieceCounts {
  const _OpeningExplorerPieceCounts({
    required this.firstInHand,
    required this.secondInHand,
    required this.firstRemoved,
    required this.secondRemoved,
  });

  factory _OpeningExplorerPieceCounts.fromSnapshot({
    required GameStateSnapshot snapshot,
    required int piecesCount,
  }) {
    final Object? rawPayload = snapshot.payload['tgfPayload'];
    assert(
      rawPayload is List<int> && rawPayload.length >= 28,
      'Opening explorer piece counts require a native Mill payload.',
    );
    if (rawPayload is! List<int> || rawPayload.length < 28) {
      throw StateError(
        'Opening explorer piece counts require a native Mill payload.',
      );
    }

    final int firstInHand = rawPayload[24];
    final int secondInHand = rawPayload[25];
    final int firstOnBoard = rawPayload[26];
    final int secondOnBoard = rawPayload[27];
    assert(
      firstInHand >= 0 &&
          secondInHand >= 0 &&
          firstOnBoard >= 0 &&
          secondOnBoard >= 0,
      'Opening explorer piece counts must not be negative.',
    );
    assert(
      firstInHand + firstOnBoard <= piecesCount &&
          secondInHand + secondOnBoard <= piecesCount,
      'Opening explorer piece counts cannot exceed the configured piece count.',
    );

    return _OpeningExplorerPieceCounts(
      firstInHand: firstInHand,
      secondInHand: secondInHand,
      firstRemoved: piecesCount - firstInHand - firstOnBoard,
      secondRemoved: piecesCount - secondInHand - secondOnBoard,
    );
  }

  final int firstInHand;
  final int secondInHand;
  final int firstRemoved;
  final int secondRemoved;
}

class _ExplorerPieceCountRow extends StatelessWidget {
  const _ExplorerPieceCountRow({
    super.key,
    required this.firstKey,
    required this.secondKey,
    required this.firstCount,
    required this.secondCount,
    required this.muted,
  });

  final Key firstKey;
  final Key secondKey;
  final int firstCount;
  final int secondCount;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final ColorSettings colors = DB().colorSettings;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        _ExplorerPieceCountText(
          key: firstKey,
          count: firstCount,
          color: colors.whitePieceColor,
          muted: muted,
        ),
        _ExplorerPieceCountText(
          key: secondKey,
          count: secondCount,
          color: colors.blackPieceColor,
          muted: muted,
        ),
      ],
    );
  }
}

class _ExplorerPieceCountText extends StatelessWidget {
  const _ExplorerPieceCountText({
    super.key,
    required this.count,
    required this.color,
    required this.muted,
  }) : assert(count >= 0, 'Piece count text cannot be negative.');

  final int count;
  final Color color;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final int visibleDots = math.min(count, 3);
    final String dots = '●' * visibleDots;
    final String label = count <= 3 ? dots : '$dots $count';
    final Color textColor = muted ? color.withValues(alpha: 0.55) : color;

    return Text(
      label,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: textColor,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        shadows: const <Shadow>[
          Shadow(
            offset: Offset(0, 1),
            blurRadius: 2,
            color: Color.fromARGB(110, 0, 0, 0),
          ),
        ],
      ),
    );
  }
}

class _OpeningExplorerBottomBar extends StatelessWidget {
  const _OpeningExplorerBottomBar({
    required this.snapshot,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
    required this.onTransform,
    required this.isLinePlaybackActive,
    required this.onOpenPractice,
    required this.onStopPlayback,
  });

  final _OpeningExplorerSnapshot snapshot;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final _OpeningExplorerTransformSelected onTransform;
  final bool isLinePlaybackActive;
  final ValueChanged<BuildContext> onOpenPractice;
  final VoidCallback onStopPlayback;

  void _showSources(BuildContext context) {
    final S strings = S.of(context);
    showLichessActionSheet<void>(
      context: context,
      sheetKey: const Key('opening_explorer_sources_sheet'),
      title: Text(strings.openingExplorerSources),
      actions: <LichessActionSheetAction>[
        LichessActionSheetAction(
          key: const Key('opening_explorer_sources_summary'),
          makeLabel: (BuildContext context) => Text(
            snapshot.sourceSummary(strings),
            textAlign: TextAlign.center,
          ),
          onPressed: () {},
        ),
        LichessActionSheetAction(
          key: const Key('opening_explorer_sources_copy_fen'),
          leading: const Icon(Icons.location_searching_rounded),
          makeLabel: (BuildContext context) => Text(strings.copyFen),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: snapshot.fen));
            SnackBarService.showRootSnackBar(strings.fenCopiedToClipboard);
          },
        ),
      ],
    );
  }

  void _showTransformSheet(BuildContext context) {
    final S strings = S.of(context);
    showLichessActionSheet<void>(
      context: context,
      sheetKey: const Key('opening_explorer_transform_sheet'),
      title: Text(strings.flipBoard),
      actions: <LichessActionSheetAction>[
        for (final MillBoardTransformAction action in millBoardTransformActions)
          LichessActionSheetAction(
            key: Key('opening_explorer_${action.id}_button'),
            leading: Icon(action.icon),
            makeLabel: (BuildContext context) => Text(action.label(strings)),
            onPressed: () => onTransform(action.type, action.label(strings)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    return LichessBottomBar(
      key: const Key('opening_explorer_bottom_bar'),
      children: <Widget>[
        LichessBottomBarButton(
          key: const Key('opening_explorer_sources_button'),
          icon: Icons.tune_rounded,
          label: strings.openingExplorerSources,
          showLabel: true,
          onTap: () => _showSources(context),
        ),
        LichessBottomBarButton(
          key: const Key('opening_explorer_flip_button'),
          icon: Icons.flip_rounded,
          label: strings.flipBoard,
          showLabel: true,
          onTap: () => _showTransformSheet(context),
        ),
        LichessBottomBarButton(
          key: const Key('opening_explorer_practice_button'),
          icon: isLinePlaybackActive
              ? Icons.stop_circle_outlined
              : Icons.school_outlined,
          label: isLinePlaybackActive
              ? strings.stop
              : strings.openingExplorerPractice,
          showLabel: true,
          onTap: isLinePlaybackActive
              ? onStopPlayback
              : () => onOpenPractice(context),
        ),
        LichessBottomBarButton(
          key: const Key('opening_explorer_previous_button'),
          icon: Icons.chevron_left_rounded,
          label: strings.previous,
          showLabel: true,
          showTooltip: false,
          onTap: !isLinePlaybackActive && canGoPrevious ? onPrevious : null,
        ),
        LichessBottomBarButton(
          key: const Key('opening_explorer_next_button'),
          icon: Icons.chevron_right_rounded,
          label: strings.next,
          showLabel: true,
          showTooltip: false,
          onTap: !isLinePlaybackActive && canGoNext ? onNext : null,
        ),
      ],
    );
  }
}

/// Hosts a freshly-started game after "Continue vs AI" / "Over the board"
/// from the opening explorer. Mirrors `play_area.dart`'s private
/// `_ContinueFromHereGameRoute` (same reasoning: kick off the engine's first
/// move immediately when the practiced line hands the very first move to
/// the AI), duplicated locally rather than shared because that route is a
/// private implementation detail of a large, unrelated widget file.
class _OpeningExplorerContinueGameRoute extends StatefulWidget {
  const _OpeningExplorerContinueGameRoute({required this.mode});

  final GameMode mode;

  @override
  State<_OpeningExplorerContinueGameRoute> createState() =>
      _OpeningExplorerContinueGameRouteState();
}

class _OpeningExplorerContinueGameRouteState
    extends State<_OpeningExplorerContinueGameRoute> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.mode != GameMode.humanVsAi) {
        return;
      }
      final GameController controller = GameController();
      if (controller.gameInstance.isAiSideToMove) {
        unawaited(controller.engineToGo(context, isMoveNow: false));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GamePage(widget.mode);
  }
}

typedef _OpeningExplorerLineSelected = void Function(List<String> moves);
typedef _OpeningExplorerContinueVsAiSelected = void Function(GameMode mode);

/// "Practice" sheet: continue the current position against the AI, or pick
/// a named opening line (or the line already browsed) to watch play out
/// from the start.
class _OpeningExplorerPracticeSheet extends StatefulWidget {
  const _OpeningExplorerPracticeSheet({
    required this.openings,
    required this.currentLine,
    required this.onSelectLine,
    required this.onContinueVsAi,
  });

  final List<OpeningEntry> openings;
  final List<String> currentLine;
  final _OpeningExplorerLineSelected onSelectLine;
  final _OpeningExplorerContinueVsAiSelected onContinueVsAi;

  @override
  State<_OpeningExplorerPracticeSheet> createState() =>
      _OpeningExplorerPracticeSheetState();
}

class _OpeningExplorerPracticeSheetState
    extends State<_OpeningExplorerPracticeSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<OpeningEntry> get _filteredOpenings {
    if (_query.isEmpty) {
      return widget.openings;
    }
    final String needle = _query.toLowerCase();
    return widget.openings
        .where(
          (OpeningEntry entry) =>
              entry.name.toLowerCase().contains(needle) ||
              entry.family.toLowerCase().contains(needle) ||
              entry.aliases.any(
                (String alias) => alias.toLowerCase().contains(needle),
              ),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final List<OpeningEntry> openings = _filteredOpenings;

    return DraggableScrollableSheet(
      key: const Key('opening_explorer_practice_sheet'),
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController scrollController) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                strings.openingExplorerPractice,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.tonalIcon(
                      key: const Key(
                        'opening_explorer_practice_vs_computer_button',
                      ),
                      onPressed: () =>
                          widget.onContinueVsAi(GameMode.humanVsAi),
                      icon: const Icon(Icons.smart_toy_outlined),
                      label: Text(
                        strings.playAgainstComputer,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key(
                        'opening_explorer_practice_over_the_board_button',
                      ),
                      onPressed: () =>
                          widget.onContinueVsAi(GameMode.humanVsHuman),
                      icon: const Icon(Icons.groups_2_outlined),
                      label: Text(
                        strings.offlineBoard,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                strings.openingExplorerSelectLine,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const Key('opening_explorer_practice_search_field'),
                controller: _searchController,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: strings.search,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppStyles.compactRadius,
                    ),
                  ),
                ),
                onChanged: (String value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: 16),
                children: <Widget>[
                  if (widget.currentLine.isNotEmpty)
                    ListTile(
                      key: const Key('opening_explorer_practice_current_line'),
                      leading: const Icon(Icons.route_outlined),
                      title: Text(strings.openingExplorerCurrentLine),
                      subtitle: Text(
                        widget.currentLine.join(' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => widget.onSelectLine(widget.currentLine),
                    ),
                  if (openings.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 24,
                      ),
                      child: Text(
                        strings.openingExplorerNoData,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    )
                  else
                    for (final OpeningEntry entry in openings)
                      ListTile(
                        key: Key('opening_explorer_practice_line_${entry.id}'),
                        leading: const Icon(Icons.menu_book_rounded),
                        title: Text(entry.name),
                        subtitle: entry.family.isEmpty
                            ? null
                            : Text(
                                entry.family,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onTap: entry.lineMoves.isEmpty
                            ? null
                            : () => widget.onSelectLine(entry.lineMoves),
                      ),
                ],
              ),
            ),
          ],
        );
      },
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
      final GameAction? action = result.action;
      assert(action != null, 'Applied explorer tap must include its action.');
      if (action == null) {
        throw StateError('Applied explorer tap must include its action.');
      }
      widget.onPositionChanged(
        previousFen: previousFen,
        currentFen: widget.session.getFen(),
        label: _openingExplorerLabelFromAction(action),
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

    _drawCoordinates(canvas, size);
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

  void _drawCoordinates(Canvas canvas, Size size) {
    final double side = size.shortestSide;
    final double padding = side * MillBoardGeometry.defaultPaddingFraction;
    final double cell = (side - padding * 2) / 6;
    final double originX = (size.width - side) / 2 + padding;
    final double originY = (size.height - side) / 2 + padding;
    final TextStyle textStyle = TextStyle(
      color: boardLineColor.withValues(alpha: 1.0),
      fontSize: AppTheme.textScaler.scale(math.max(10, side * 0.045)),
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    );

    for (
      int index = 0;
      index < _openingExplorerVerticalCoordinates.length;
      index++
    ) {
      _paintCoordinate(
        canvas,
        text: _openingExplorerVerticalCoordinates[index],
        style: textStyle,
        center: Offset(originX - padding / 2, originY + index * cell),
      );
    }

    for (
      int index = 0;
      index < _openingExplorerHorizontalCoordinates.length;
      index++
    ) {
      final String label = DB().generalSettings.screenReaderSupport
          ? _openingExplorerHorizontalCoordinates[index].toUpperCase()
          : _openingExplorerHorizontalCoordinates[index];
      _paintCoordinate(
        canvas,
        text: label,
        style: textStyle,
        center: Offset(
          originX + index * cell,
          originY + cell * 6 + padding / 2,
        ),
      );
    }
  }

  void _paintCoordinate(
    Canvas canvas, {
    required String text,
    required TextStyle style,
    required Offset center,
  }) {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(style: style, text: text),
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
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

class _OpeningNameSection extends StatelessWidget {
  const _OpeningNameSection({required this.recognition});

  final MillOpeningRecognition recognition;

  @override
  Widget build(BuildContext context) {
    assert(recognition.isNamed, 'Opening name section requires a named line.');
    final S strings = S.of(context);
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final String title = _openingRecognitionTitle(recognition);
    final List<String> details = _openingRecognitionDetails(
      strings,
      recognition,
    );

    return LichessListSection(
      header: Text(strings.openingLabel),
      cardKey: const Key('opening_explorer_opening_card'),
      hasLeading: false,
      children: <Widget>[
        ColoredBox(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.62),
          child: Padding(
            key: const Key('opening_explorer_opening_header'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.auto_stories_rounded,
                  size: 20,
                  color: colorScheme.onSurface,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                      if (details.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          details.join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                letterSpacing: 0,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _openingRecognitionTitle(MillOpeningRecognition recognition) {
  if (recognition.status != MillOpeningStatus.deviation &&
      recognition.candidateFamilies.length > 1) {
    const int maxShown = 3;
    final Iterable<String> shown = recognition.candidateFamilies.take(maxShown);
    final String suffix = recognition.candidateFamilies.length > maxShown
        ? ' ...'
        : '';
    return '${shown.join(' / ')}$suffix';
  }
  if (recognition.status == MillOpeningStatus.deviation &&
      (recognition.branchName?.isNotEmpty ?? false)) {
    return recognition.branchName!;
  }
  final String? name = recognition.name;
  assert(name != null && name.isNotEmpty, 'Named recognition requires a name.');
  return name!;
}

List<String> _openingRecognitionDetails(
  S strings,
  MillOpeningRecognition recognition,
) {
  final List<String> details = <String>[];
  if (recognition.candidateFamilies.length <= 1 &&
      (recognition.family?.isNotEmpty ?? false)) {
    details.add('${strings.openingBookStudioFamily}: ${recognition.family!}');
  }
  final String reference = recognition.sourceReference ?? '';
  if (reference.isNotEmpty) {
    details.add(reference);
  }
  final String favoredSide = switch (recognition.favoredSide) {
    'W' => strings.white,
    'B' => strings.black,
    _ => '',
  };
  if (favoredSide.isNotEmpty) {
    details.add('${strings.openingFavours} $favoredSide');
  }
  final String nextMove = recognition.nextMove ?? '';
  if (nextMove.isNotEmpty) {
    details.add('${strings.openingBookStudioNextMove}: $nextMove');
  }
  return details;
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
    return ColoredBox(
      color: _openingExplorerRowColor(context, index),
      child: InkWell(
        key: Key('opening_explorer_move_${move.notation}'),
        onTap: onSelected,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: <Widget>[
              Expanded(
                flex: _explorerMoveColumnFlex,
                child: _MoveCell(move: move),
              ),
              const SizedBox(width: _explorerColumnGap),
              Expanded(
                flex: _explorerGamesColumnFlex,
                child: _MoveGamesCell(move: move),
              ),
              const SizedBox(width: _explorerColumnGap),
              Expanded(
                flex: _explorerStatsColumnFlex,
                child: move.humanStats == null
                    ? const SizedBox.shrink()
                    : _HumanStatsBar(stats: move.humanStats!),
              ),
            ],
          ),
        ),
      ),
    );
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
            Expanded(
              flex: _explorerMoveColumnFlex,
              child: Text(strings.move, style: style),
            ),
            const SizedBox(width: _explorerColumnGap),
            Expanded(
              flex: _explorerGamesColumnFlex,
              child: Text(
                strings.openingExplorerGames,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            const SizedBox(width: _explorerColumnGap),
            Expanded(
              flex: _explorerStatsColumnFlex,
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

class _OpeningExplorerLoadingTile extends StatelessWidget {
  const _OpeningExplorerLoadingTile({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _openingExplorerRowColor(context, index),
      child: Padding(
        key: Key('opening_explorer_loading_row_$index'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: const Row(
          children: <Widget>[
            Expanded(
              flex: _explorerMoveColumnFlex,
              child: _OpeningExplorerLoadingCell(),
            ),
            SizedBox(width: _explorerColumnGap),
            Expanded(
              flex: _explorerGamesColumnFlex,
              child: _OpeningExplorerLoadingCell(),
            ),
            SizedBox(width: _explorerColumnGap),
            Expanded(
              flex: _explorerStatsColumnFlex,
              child: _OpeningExplorerLoadingCell(),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpeningExplorerLoadingCell extends StatelessWidget {
  const _OpeningExplorerLoadingCell();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(5),
      ),
      child: const SizedBox(height: 20),
    );
  }
}

class _OpeningExplorerNoDataTile extends StatelessWidget {
  const _OpeningExplorerNoDataTile();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextStyle? textStyle = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: colorScheme.onSurfaceVariant, letterSpacing: 0);

    return ColoredBox(
      color: _openingExplorerRowColor(context, 0),
      child: Padding(
        key: const Key('opening_explorer_no_data_row'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: <Widget>[
            Expanded(
              flex: _explorerMoveColumnFlex,
              child: Icon(
                Icons.not_interested_outlined,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: _explorerColumnGap),
            Expanded(
              flex: _explorerGamesColumnFlex,
              child: Text(
                S.of(context).openingExplorerNoData,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
            ),
            const SizedBox(width: _explorerColumnGap),
            const Expanded(
              flex: _explorerStatsColumnFlex,
              child: SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpeningExplorerEngineSearchingTile extends StatelessWidget {
  const _OpeningExplorerEngineSearchingTile();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextStyle? textStyle = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: colorScheme.onSurfaceVariant, letterSpacing: 0);

    return ColoredBox(
      color: _openingExplorerRowColor(context, 0),
      child: Padding(
        key: const Key('opening_explorer_engine_searching_row'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: <Widget>[
            Expanded(
              flex: _explorerMoveColumnFlex,
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: _explorerColumnGap),
            Expanded(
              flex: _explorerGamesColumnFlex + _explorerStatsColumnFlex,
              child: Text(
                S.of(context).openingExplorerEngineSearching,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
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

    return Wrap(
      spacing: 5,
      runSpacing: 3,
      crossAxisAlignment: WrapCrossAlignment.center,
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
        if (move.isPerfectMove)
          _SourceBadge(
            label: strings.perfectDatabaseSettings,
            color: colorScheme.primary,
            icon: Icons.verified_rounded,
          ),
        if (move.bookRank != null)
          _SourceBadge(
            label: '${strings.openingBookSettings} #${move.bookRank! + 1}',
            color: colorScheme.tertiary,
            icon: Icons.menu_book_rounded,
          ),
        if (move.humanStats != null)
          _SourceBadge(
            label: strings.humanGameDatabaseSettings,
            color: colorScheme.secondary,
            icon: Icons.people_alt_rounded,
          ),
        if (move.engineScore != null)
          _SourceBadge(
            label: strings.openingExplorerEngineBadge,
            color: colorScheme.outline,
            icon: Icons.auto_awesome_rounded,
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
    final int? engineScore = move.engineScore;
    final TextStyle? style = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      letterSpacing: 0,
    );

    final String text = stats == null && engineScore != null
        ? _formatExplorerEngineScore(engineScore)
        : _formatExplorerGamesText(
            games: stats?.total ?? 0,
            percent: stats == null ? 0 : move.gamesPercent,
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
              flex: _explorerMoveColumnFlex,
              child: Icon(
                Icons.functions,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: _explorerColumnGap),
            Expanded(
              flex: _explorerGamesColumnFlex,
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
            const SizedBox(width: _explorerColumnGap),
            Expanded(
              flex: _explorerStatsColumnFlex,
              child: _HumanStatsBar(stats: stats),
            ),
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
            dimension: 18,
            child: Icon(icon, size: 12, color: color),
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

/// Formats a heuristic engine evaluation (mover's perspective) as a signed
/// number, e.g. `+42`, `-15`, `0`.
String _formatExplorerEngineScore(int score) {
  return score > 0 ? '+$score' : '$score';
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
    required this.usedEngineFallback,
    required this.openingRecognition,
    required this.aggregateHumanStats,
    required this.moves,
  });

  factory _OpeningExplorerSnapshot.fromSession({
    required NativeMillGameSession session,
    required RuleSettings ruleSettings,
    required GeneralSettings generalSettings,
    required List<String> placementMoves,
    List<NativeMillPrincipalVariation> engineSuggestions =
        const <NativeMillPrincipalVariation>[],
  }) {
    final String fen = session.getFen();
    final bool isRuleSupported =
        ruleSettings.isLikelyNineMensMorris() || ruleSettings.isLikelyElFilja();
    final bool isElFilja = ruleSettings.isLikelyElFilja();
    final List<OpeningEntry> openingLines = isRuleSupported
        ? OpeningBookRepository.instance.openingsFor(isElFilja: isElFilja)
        : const <OpeningEntry>[];
    final MillOpeningRecognition openingRecognition =
        MillOpeningRecognizer.recognize(placementMoves, openingLines);
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
          .oracleFor(isElFilja: isElFilja);
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

    // Heuristic fill: when the opening book, human database, and perfect
    // database all have nothing for this exact position, fall back to
    // whatever engine suggestions the caller already fetched (if any) so
    // the explorer is never simply empty for well-motivated deviations that
    // happen to be absent from every curated/recorded source.
    bool usedEngineFallback = false;
    if (moves.isEmpty && engineSuggestions.isNotEmpty) {
      for (final NativeMillPrincipalVariation variation in engineSuggestions) {
        if (!legalActions.containsKey(variation.move)) {
          continue;
        }
        ensureMove(variation.move).engineScore = variation.score;
        usedEngineFallback = true;
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
      usedEngineFallback: usedEngineFallback,
      openingRecognition: openingRecognition,
      aggregateHumanStats: aggregateHumanStats,
      moves: sortedMoves,
    );
  }

  final String fen;
  final bool isRuleSupported;
  final int openingBookMoveCount;
  final int humanDatabaseMoveCount;
  final bool perfectMoveAvailable;
  final bool usedEngineFallback;
  final MillOpeningRecognition openingRecognition;
  final _HumanMoveStats? aggregateHumanStats;
  final List<_OpeningExplorerMove> moves;

  /// True exactly when the book/human/perfect sources had nothing at all
  /// for this position and every listed move is instead a heuristic engine
  /// suggestion (see [_OpeningExplorerMove.engineScore]).
  bool get needsEngineFallback =>
      !usedEngineFallback && moves.isEmpty && isRuleSupported;

  String sourceSummary(S strings) {
    final List<String> parts = <String>[
      '${strings.openingBookSettings}: $openingBookMoveCount',
      '${strings.humanGameDatabaseSettings}: $humanDatabaseMoveCount',
      '${strings.perfectDatabaseSettings}: ${perfectMoveAvailable ? strings.openingExplorerAvailable : strings.openingExplorerNoDataShort}',
      if (usedEngineFallback)
        '${strings.openingExplorerEngineSource}: ${strings.openingExplorerAvailable}',
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
    // Only ever discriminates when every move is an engine-only backfill
    // suggestion (book/human/perfect fields above are all null/false/0 for
    // every candidate in that case); higher mover-relative eval sorts first.
    final int engineCompare = (b.engineScore ?? _engineScoreFloor).compareTo(
      a.engineScore ?? _engineScoreFloor,
    );
    if (engineCompare != 0) {
      return engineCompare;
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

  /// Heuristic search evaluation (mover's perspective; positive favors the
  /// side to move), populated only when [OpeningExplorerPage] had to fall
  /// back to an engine suggestion because the opening book, human database,
  /// and perfect database had no entry for this position at all. `null`
  /// whenever any real data source covers the move.
  int? engineScore;
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
