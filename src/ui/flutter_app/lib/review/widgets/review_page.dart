// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../game_page/services/analysis/move_feedback.dart';
import '../../game_page/services/import_export/pgn.dart';
import '../../game_page/widgets/mini_board.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/services/logger.dart';
import '../../shared/widgets/move_feedback_reasons.dart';
import '../../shared/widgets/quality_annotation_sheet.dart';
import '../models/review_models.dart';
import '../services/review_analysis_service.dart';
import '../services/review_nag_merge.dart';
import '../services/review_piece_numbers.dart';
import '../services/review_storage.dart';
import 'review_correction_page.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({
    super.key,
    required this.record,
    this.initialReport,
    this.autoAnalyze = true,
    this.analysisService,
    this.storage = ReviewStorage.instance,
    this.onCopyPgn,
    this.onSharePgn,
  });

  final PrivateGameRecord record;
  final ReviewReport? initialReport;
  final bool autoAnalyze;
  final ReviewAnalysisService? analysisService;
  final ReviewStorage storage;
  final Future<void> Function(String pgn)? onCopyPgn;
  final Future<void> Function(String pgn)? onSharePgn;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late final ReviewAnalysisService _analysisService;
  late final int _structuralTurnCount;
  late final int _structuralAtomicCount;
  late final int _structuralVariationCount;
  late final List<ReviewTurnBoundary> _timeline;

  ReviewReport? _report;
  Object? _error;
  int _completedActions = 0;
  int _analysisRun = 0;
  int _selectedGroup = 0;
  bool _analyzing = true;
  bool _deepening = false;
  bool _analysisCancelled = false;

  @override
  void initState() {
    super.initState();
    _analysisService = widget.analysisService ?? ReviewAnalysisService();
    final PgnGame<PgnNodeData> game = PgnGame.parsePgn(widget.record.sourcePgn);
    final List<PgnNodeData> turns = game.moves.mainline().toList();
    _structuralTurnCount = turns.length;
    _structuralAtomicCount = turns.fold<int>(
      0,
      (int total, PgnNodeData move) => total + splitMillSan(move.san).length,
    );
    _structuralVariationCount = _countVariations(game.moves);
    _report = widget.initialReport;
    _timeline = _report != null && _report!.turns.isNotEmpty
        ? List<ReviewTurnBoundary>.unmodifiable(_report!.turns)
        : _analysisService.buildTimeline(widget.record);
    _analyzing = widget.autoAnalyze;
    if (_report != null && _report!.turns.isNotEmpty) {
      _selectedGroup = _firstKeyGroup(_report!);
    } else if (_timeline.isNotEmpty) {
      _selectedGroup = _timeline.first.groupIndex;
    }
    if (widget.autoAnalyze) {
      unawaited(_runAnalysis());
    }
  }

  @override
  void dispose() {
    _analysisRun++;
    _analysisService.cancel();
    super.dispose();
  }

  Future<void> _runAnalysis({bool ignoreCache = false}) async {
    if (ignoreCache) {
      _analysisService.cancel();
    }
    final int analysisRun = ++_analysisRun;
    setState(() {
      _analyzing = true;
      _deepening = false;
      _analysisCancelled = false;
      _error = null;
      _completedActions = 0;
    });
    try {
      final ReviewReport report = await _analysisService.analyze(
        widget.record,
        ignoreCache: ignoreCache,
        onProgress: (int completed, int _) {
          if (mounted) {
            setState(() => _completedActions = completed);
          }
        },
      );
      if (!mounted || analysisRun != _analysisRun) {
        return;
      }
      setState(() {
        _report = report;
        _analyzing = false;
        _analysisCancelled = report.status == ReviewStatus.cancelled;
      });
    } on Object catch (error, stackTrace) {
      if (!mounted || analysisRun != _analysisRun) {
        return;
      }
      logger.e(
        '[Review] Analysis failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
      setState(() {
        _error = error;
        _analyzing = false;
        _analysisCancelled = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final String backLabel = MaterialLocalizations.of(
      context,
    ).backButtonTooltip;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('review_back'),
          tooltip: backLabel,
          onPressed: () => Navigator.maybePop(context),
          icon: Icon(Icons.arrow_back_rounded, semanticLabel: backLabel),
        ),
        title: Text(strings.reviewGame),
        actions: <Widget>[
          if (_analyzing || _deepening)
            IconButton(
              key: const Key('review_cancel_analysis'),
              tooltip: strings.cancelAnalysis,
              onPressed: () {
                final bool wasQuickAnalysis = _analyzing;
                _analysisRun++;
                _analysisService.cancel();
                setState(() {
                  _analyzing = false;
                  _deepening = false;
                  _analysisCancelled =
                      wasQuickAnalysis &&
                      (_report == null ||
                          _report!.status == ReviewStatus.cancelled);
                  _error = null;
                });
              },
              icon: Icon(
                Icons.stop_circle_outlined,
                semanticLabel: strings.cancelAnalysis,
              ),
            )
          else if (_report != null) ...<Widget>[
            IconButton(
              key: const Key('review_export'),
              tooltip: strings.exportGame,
              onPressed: _exportReview,
              icon: Icon(
                Icons.ios_share_rounded,
                semanticLabel: strings.exportGame,
              ),
            ),
            IconButton(
              key: const Key('review_reanalyze'),
              tooltip: strings.reanalyze,
              onPressed: () => unawaited(_runAnalysis(ignoreCache: true)),
              icon: Icon(
                Icons.refresh_rounded,
                semanticLabel: strings.reanalyze,
              ),
            ),
          ],
        ],
      ),
      body: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _selectAdjacentTurn(-1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _selectAdjacentTurn(1),
          const SingleActivator(LogicalKeyboardKey.home): () =>
              _selectBoundaryTurn(last: false),
          const SingleActivator(LogicalKeyboardKey.end): () =>
              _selectBoundaryTurn(last: true),
        },
        child: Focus(
          key: const Key('review_keyboard_shortcuts'),
          autofocus: true,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool sideBySide =
                  constraints.maxWidth >= 720 ||
                  constraints.maxWidth > constraints.maxHeight;
              final Widget board = _buildBoard(context);
              final Widget navigation = _buildTurnNavigation(context);
              final Widget panel = _buildPanel(
                context,
                useCollapsibleMoveList: !sideBySide,
              );
              if (sideBySide) {
                return Row(
                  key: const Key('review_wide_layout'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      flex: 5,
                      child: LayoutBuilder(
                        builder:
                            (
                              BuildContext context,
                              BoxConstraints boardConstraints,
                            ) {
                              const double navigationAllowance = 72;
                              final double heightLimitedExtent =
                                  boardConstraints.maxHeight -
                                  navigationAllowance;
                              final double availableExtent =
                                  boardConstraints.maxWidth <
                                      heightLimitedExtent
                                  ? boardConstraints.maxWidth
                                  : heightLimitedExtent;
                              final double boardExtent = availableExtent > 620
                                  ? 620
                                  : availableExtent;
                              assert(
                                boardExtent > 0,
                                'Wide review layout needs room for the board.',
                              );
                              return Center(
                                child: SizedBox(
                                  key: const Key('review_wide_board_column'),
                                  width: boardConstraints.maxWidth,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      SizedBox.square(
                                        dimension: boardExtent,
                                        child: board,
                                      ),
                                      navigation,
                                    ],
                                  ),
                                ),
                              );
                            },
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(flex: 4, child: panel),
                  ],
                );
              }
              return Column(
                key: const Key('review_phone_layout'),
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 560,
                          maxHeight: 560,
                        ),
                        child: board,
                      ),
                    ),
                  ),
                  navigation,
                  const Divider(height: 1),
                  Expanded(flex: 2, child: panel),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _selectAdjacentTurn(int offset) {
    assert(offset == -1 || offset == 1);
    if (_timeline.isEmpty) {
      return;
    }
    final int selectedIndex = _timeline.indexWhere(
      (ReviewTurnBoundary turn) => turn.groupIndex == _selectedGroup,
    );
    final int currentIndex = selectedIndex < 0 ? 0 : selectedIndex;
    final int targetIndex = (currentIndex + offset).clamp(
      0,
      _timeline.length - 1,
    );
    if (targetIndex == currentIndex) {
      return;
    }
    setState(() => _selectedGroup = _timeline[targetIndex].groupIndex);
  }

  void _selectBoundaryTurn({required bool last}) {
    if (_timeline.isEmpty) {
      return;
    }
    final int targetIndex = last ? _timeline.length - 1 : 0;
    if (_selectedGroup == _timeline[targetIndex].groupIndex) {
      return;
    }
    setState(() => _selectedGroup = _timeline[targetIndex].groupIndex);
  }

  Widget _buildTurnNavigation(BuildContext context) {
    if (_timeline.isEmpty) {
      return const SizedBox.shrink();
    }
    final int selectedIndex = _timeline.indexWhere(
      (ReviewTurnBoundary turn) => turn.groupIndex == _selectedGroup,
    );
    final int currentIndex = selectedIndex < 0 ? 0 : selectedIndex;
    final S strings = S.of(context);

    void selectIndex(int index) {
      assert(index >= 0 && index < _timeline.length);
      setState(() => _selectedGroup = _timeline[index].groupIndex);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        key: const Key('review_turn_navigation'),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            IconButton(
              key: const Key('review_first_turn'),
              tooltip: strings.reviewFirstMove,
              onPressed: currentIndex == 0 ? null : () => selectIndex(0),
              icon: Icon(
                Icons.first_page_rounded,
                semanticLabel: strings.reviewFirstMove,
              ),
            ),
            IconButton(
              key: const Key('review_previous_turn'),
              tooltip: strings.reviewPreviousMove,
              onPressed: currentIndex == 0
                  ? null
                  : () => selectIndex(currentIndex - 1),
              icon: Icon(
                Icons.chevron_left_rounded,
                semanticLabel: strings.reviewPreviousMove,
              ),
            ),
            Semantics(
              label: strings.reviewMoveProgress(
                currentIndex + 1,
                _timeline.length,
              ),
              child: Text(
                '${currentIndex + 1}/${_timeline.length}',
                key: const Key('review_turn_progress'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            IconButton(
              key: const Key('review_next_turn'),
              tooltip: strings.reviewNextMove,
              onPressed: currentIndex == _timeline.length - 1
                  ? null
                  : () => selectIndex(currentIndex + 1),
              icon: Icon(
                Icons.chevron_right_rounded,
                semanticLabel: strings.reviewNextMove,
              ),
            ),
            IconButton(
              key: const Key('review_last_turn'),
              tooltip: strings.reviewLastMove,
              onPressed: currentIndex == _timeline.length - 1
                  ? null
                  : () => selectIndex(_timeline.length - 1),
              icon: Icon(
                Icons.last_page_rounded,
                semanticLabel: strings.reviewLastMove,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoard(BuildContext context) {
    final ReviewReport? report = _report;
    ReviewTurnBoundary? selectedTurn;
    if (_timeline.isNotEmpty) {
      selectedTurn = _timeline.firstWhere(
        (ReviewTurnBoundary turn) => turn.groupIndex == _selectedGroup,
        orElse: () => _timeline.first,
      );
    }
    final String boardLayout =
        selectedTurn?.boardLayout ??
        widget.record.finalBoardLayout ??
        '********/********/********';
    final ReviewReport? completeReport = report?.status == ReviewStatus.complete
        ? report
        : null;
    final int? nag = selectedTurn == null || completeReport == null
        ? null
        : completeReport.effectiveQualityNagForTurn(selectedTurn.groupIndex);
    final String? qualityLabel = selectedTurn == null || nag == null
        ? null
        : '${_nagSymbol(nag)} ${_nagLabel(context, nag)}';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: AspectRatio(
        aspectRatio: 1,
        child: MiniBoard(
          key: const Key('review_board'),
          boardLayout: boardLayout,
          qualityNag: nag,
          qualityLabel: qualityLabel,
          badgeAnchorMove: selectedTurn?.anchorMove,
          hasDiagonalLines: widget.record.rules.hasDiagonalLines,
          showCoordinates: true,
          pieceNumbersByNode: selectedTurn == null
              ? const <int, int>{}
              : ReviewPieceNumbers.forTurn(_timeline, selectedTurn.groupIndex),
        ),
      ),
    );
  }

  Widget _buildPanel(
    BuildContext context, {
    required bool useCollapsibleMoveList,
  }) {
    final ReviewReport? completeReport =
        _report?.status == ReviewStatus.complete ? _report : null;
    return SingleChildScrollView(
      key: const Key('review_analysis_panel'),
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        children: <Widget>[
          if (completeReport != null &&
              completeReport.turns.isNotEmpty &&
              completeReport.actions.isNotEmpty)
            _buildQualityOverview(context, completeReport)
          else
            _buildStructureSummary(context),
          if (_timeline.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            if (useCollapsibleMoveList)
              _buildCollapsibleMoveList(context, completeReport)
            else
              _buildMoveList(context, completeReport),
          ],
          if (_analyzing) ...<Widget>[
            const SizedBox(height: 12),
            _buildProgress(context),
          ] else if (_analysisCancelled) ...<Widget>[
            const SizedBox(height: 12),
            _buildCancelled(context),
          ] else if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            _buildError(context),
          ] else if (_report?.status == ReviewStatus.cancelled) ...<Widget>[
            const SizedBox(height: 12),
            _buildCancelled(context),
          ],
          if (_timeline.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Card(child: ListTile(title: Text(S.of(context).noMove))),
            )
          else if (completeReport != null &&
              completeReport.actions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            _buildSelectedTurnDetail(context, completeReport),
            const SizedBox(height: 12),
            _buildCorrection(context, completeReport),
          ],
        ],
      ),
    );
  }

  Widget _buildStructureSummary(BuildContext context) {
    final S strings = S.of(context);
    return Card(
      key: const Key('review_structure_summary'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              strings.structuralSummary,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              strings.reviewStructureCounts(
                _structuralTurnCount,
                _structuralAtomicCount,
                _structuralVariationCount,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityOverview(BuildContext context, ReviewReport report) {
    final S strings = S.of(context);
    final Map<ReviewGrade, int> whiteCounts = report.gradeCountsForSide(
      ReviewSide.white,
    );
    final Map<ReviewGrade, int> blackCounts = report.gradeCountsForSide(
      ReviewSide.black,
    );
    final String whiteName = _reviewPlayerName(strings, widget.record.white);
    final String blackName = _reviewPlayerName(strings, widget.record.black);
    final String whiteLabel = strings.reviewPlayerName(
      strings.player1,
      whiteName,
    );
    final String blackLabel = strings.reviewPlayerName(
      strings.player2,
      blackName,
    );

    return Card(
      key: const Key('review_quality_overview'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              strings.reviewQualityOverview,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              strings.reviewStructureCounts(
                _structuralTurnCount,
                _structuralAtomicCount,
                _structuralVariationCount,
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 24),
            Row(
              children: <Widget>[
                const Expanded(flex: 5, child: SizedBox.shrink()),
                Expanded(
                  flex: 3,
                  child: _ReviewPlayerHeader(
                    seat: strings.player1,
                    player: whiteName,
                    pieceColor: Colors.white,
                    semanticLabel: whiteLabel,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: _ReviewPlayerHeader(
                    seat: strings.player2,
                    player: blackName,
                    pieceColor: Colors.black,
                    semanticLabel: blackLabel,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final ReviewGrade grade in ReviewGrade.values)
              _buildQualityRow(
                context,
                grade: grade,
                whiteCount: whiteCounts[grade]!,
                blackCount: blackCounts[grade]!,
                whiteLabel: whiteLabel,
                blackLabel: blackLabel,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityRow(
    BuildContext context, {
    required ReviewGrade grade,
    required int whiteCount,
    required int blackCount,
    required String whiteLabel,
    required String blackLabel,
  }) {
    final S strings = S.of(context);
    final String gradeLabel = _gradeLabel(context, grade);
    return SizedBox(
      height: 38,
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 5,
            child: Row(
              children: <Widget>[
                _ReviewGradeBadge(
                  symbol: _gradeSymbol(grade),
                  color: _gradeColor(grade),
                  foregroundColor: _gradeForegroundColor(grade),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    gradeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Semantics(
              key: Key('review_quality_white_${grade.name}'),
              label: strings.reviewPlayerGradeCount(
                whiteLabel,
                gradeLabel,
                whiteCount,
              ),
              excludeSemantics: true,
              child: Text('$whiteCount', textAlign: TextAlign.center),
            ),
          ),
          Expanded(
            flex: 3,
            child: Semantics(
              key: Key('review_quality_black_${grade.name}'),
              label: strings.reviewPlayerGradeCount(
                blackLabel,
                gradeLabel,
                blackCount,
              ),
              excludeSemantics: true,
              child: Text('$blackCount', textAlign: TextAlign.center),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    final S strings = S.of(context);
    final double? value = _structuralAtomicCount == 0
        ? null
        : _completedActions / _structuralAtomicCount;
    return Card(
      key: const Key('review_analysis_progress'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(strings.quickAnalysis),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: value),
            const SizedBox(height: 8),
            Text(
              strings.reviewProgress(_completedActions, _structuralAtomicCount),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final S strings = S.of(context);
    final Object error = _error!;
    final String message = error is ReviewCapacityException
        ? strings.reviewUnsupportedPosition(
            error.legalActionCount,
            error.capacity,
          )
        : strings.reviewAnalysisFailed;
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(message),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => unawaited(_runAnalysis(ignoreCache: true)),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(strings.retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCancelled(BuildContext context) {
    final S strings = S.of(context);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.pause_circle_outline_rounded),
        title: Text(strings.analysisCancelled),
        trailing: FilledButton.tonal(
          onPressed: () => unawaited(_runAnalysis(ignoreCache: true)),
          child: Text(strings.reanalyze),
        ),
      ),
    );
  }

  Widget _buildMoveList(BuildContext context, ReviewReport? report) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _buildMoveChips(report),
      ),
    );
  }

  Widget _buildCollapsibleMoveList(BuildContext context, ReviewReport? report) {
    final int selectedIndex = _timeline.indexWhere(
      (ReviewTurnBoundary turn) => turn.groupIndex == _selectedGroup,
    );
    return Card(
      key: const Key('review_collapsible_move_list'),
      child: ExpansionTile(
        title: Text(S.of(context).moves),
        subtitle: Text(
          '${selectedIndex + 1}/${_timeline.length}',
          textDirection: TextDirection.ltr,
        ),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: _buildMoveChips(report),
          ),
        ],
      ),
    );
  }

  Widget _buildMoveChips(ReviewReport? report) {
    return Wrap(
      key: const Key('review_move_list'),
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final ReviewTurnBoundary turn in _timeline)
          ChoiceChip(
            key: Key('review_move_${turn.groupIndex}'),
            selected: turn.groupIndex == _selectedGroup,
            label: Text(
              '${turn.groupIndex + 1}. ${turn.san}${_nagTextForTurn(report, turn)}',
              textDirection: TextDirection.ltr,
            ),
            onSelected: (_) {
              setState(() => _selectedGroup = turn.groupIndex);
            },
          ),
      ],
    );
  }

  Widget _buildSelectedTurnDetail(BuildContext context, ReviewReport report) {
    final S strings = S.of(context);
    final ReviewTurnBoundary turn = report.turns.firstWhere(
      (ReviewTurnBoundary value) => value.groupIndex == _selectedGroup,
      orElse: () => report.turns.first,
    );
    final ReviewGrade grade = report.gradeForTurn(turn.groupIndex);
    final int? nag = report.effectiveQualityNagForTurn(turn.groupIndex);
    final List<ReviewActionEvaluation> actions = report.actions
        .where(
          (ReviewActionEvaluation action) =>
              action.groupIndex == turn.groupIndex,
        )
        .toList(growable: false);
    final List<MoveFeedbackReason> feedbackReasons = report
        .effectiveFeedbackReasonsForTurn(turn.groupIndex);
    final List<String> feedbackReasonLabels = feedbackReasons
        .map(
          (MoveFeedbackReason reason) =>
              moveFeedbackReasonLabel(strings, reason),
        )
        .toList(growable: false);
    final bool isDeep = actions.every(
      (ReviewActionEvaluation action) => action.profile == ReviewProfile.deep,
    );
    return Card(
      key: const Key('review_turn_detail'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Semantics(
                    label: _gradeLabel(context, grade),
                    child: Text(
                      '${turn.san}${nag == null ? '' : _nagSymbol(nag)} · ${_gradeLabel(context, grade)}',
                      style: Theme.of(context).textTheme.titleMedium,
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('review_choose_nag'),
                  tooltip: strings.qualityAnnotation,
                  onPressed: () => _showNagChooser(report, turn.groupIndex),
                  icon: Icon(
                    Icons.rate_review_outlined,
                    semanticLabel: strings.qualityAnnotation,
                  ),
                ),
              ],
            ),
            if (feedbackReasonLabels.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      strings.moveFeedbackReasonsSummary(
                        feedbackReasonLabels.take(2).join(' · '),
                      ),
                      key: const Key('review_move_feedback_reasons'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    key: const Key('review_move_feedback_show_reasons'),
                    tooltip: strings.moveFeedbackShowReasons,
                    onPressed: () => unawaited(
                      showMoveFeedbackReasonsDialog(
                        context: context,
                        heading: nag == null
                            ? _gradeLabel(context, grade)
                            : '${_nagSymbol(nag)} ${_nagLabel(context, nag)}',
                        reasons: feedbackReasons,
                        reasonKeyPrefix: 'review_move_feedback_reason_',
                      ),
                    ),
                    icon: const Icon(Icons.info_outline),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              strings.reviewBestLine(
                _formatPrincipalVariation(
                  actions.first.candidates.first.line,
                  startingSide: turn.side,
                  startingMoveNumber: _moveNumberForTurn(report, turn),
                ),
              ),
              textDirection: TextDirection.ltr,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonalIcon(
                key: const Key('review_deepen_turn'),
                onPressed: isDeep || _deepening
                    ? null
                    : () => unawaited(_deepenTurn(report, turn.groupIndex)),
                icon: _deepening
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search_rounded),
                label: Text(strings.deepAnalysis),
              ),
            ),
            const Divider(height: 28),
            SwitchListTile.adaptive(
              key: const Key('review_export_annotations'),
              contentPadding: EdgeInsets.zero,
              title: Text(strings.exportReviewAnnotations),
              subtitle: Text(strings.exportReviewAnnotationsDescription),
              value: report.includeAnnotationsOnExport,
              onChanged: (bool value) => _setExportPreference(report, value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCorrection(BuildContext context, ReviewReport report) {
    final S strings = S.of(context);
    final List<ReviewActionEvaluation> corrections = report.correctionActions;
    if (corrections.isEmpty) {
      return Card(
        key: const Key('review_correction_empty'),
        child: ListTile(
          leading: const Icon(Icons.check_circle_outline_rounded),
          title: Text(strings.noHumanMistakesToCorrect),
        ),
      );
    }
    final ReviewActionEvaluation correction = corrections.first;
    final ReviewTurnBoundary turn = report.turns.firstWhere(
      (ReviewTurnBoundary value) => value.groupIndex == correction.groupIndex,
    );
    return Card(
      key: const Key('review_correction'),
      child: ListTile(
        leading: const Icon(Icons.school_outlined),
        title: Text(strings.interactiveCorrection),
        subtitle: Text(strings.correctionPrompt(turn.san)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '${corrections.length}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (BuildContext context) =>
                ReviewCorrectionPage(record: widget.record, report: report),
          ),
        ),
      ),
    );
  }

  Future<void> _deepenTurn(ReviewReport report, int groupIndex) async {
    final int analysisRun = ++_analysisRun;
    setState(() {
      _deepening = true;
      _analysisCancelled = false;
      _error = null;
    });
    try {
      final ReviewReport updated = await _analysisService.deepenTurn(
        widget.record,
        report,
        groupIndex,
      );
      if (mounted && analysisRun == _analysisRun) {
        setState(() {
          _report = updated;
          _deepening = false;
        });
      }
    } on Object catch (error, stackTrace) {
      if (mounted && analysisRun == _analysisRun) {
        logger.e(
          '[Review] Deep analysis failed: $error',
          error: error,
          stackTrace: stackTrace,
        );
        setState(() {
          _error = error;
          _deepening = false;
        });
      }
    }
  }

  Future<void> _exportReview() async {
    final ReviewReport? report = _report;
    if (report == null) {
      return;
    }
    final S strings = S.of(context);
    final String pgn = ReviewNagMerge.forExport(
      widget.record.sourcePgn,
      report,
    );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final bool showSystemCancel =
            Theme.of(sheetContext).platform == TargetPlatform.iOS;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    strings.shareAndExport,
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  key: const Key('review_export_copy'),
                  leading: const Icon(Icons.copy_all_rounded),
                  title: Text(strings.copyPgn),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(_copyReviewPgn(pgn));
                  },
                ),
                ListTile(
                  key: const Key('review_export_share'),
                  leading: const Icon(Icons.ios_share_rounded),
                  title: Text(strings.shareQrCode),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(_shareReviewPgn(pgn));
                  },
                ),
                if (showSystemCancel)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      key: const Key('review_export_cancel'),
                      onPressed: () => Navigator.pop(sheetContext),
                      child: Text(strings.cancel),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _copyReviewPgn(String pgn) async {
    final Future<void> Function(String pgn)? copyPgn = widget.onCopyPgn;
    if (copyPgn == null) {
      await Clipboard.setData(ClipboardData(text: pgn));
    } else {
      await copyPgn(pgn);
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(S.of(context).moveHistoryCopied)));
  }

  Future<void> _shareReviewPgn(String pgn) async {
    final Future<void> Function(String pgn)? sharePgn = widget.onSharePgn;
    if (sharePgn == null) {
      await SharePlus.instance.share(
        ShareParams(text: pgn, subject: S.of(context).reviewGame),
      );
    } else {
      await sharePgn(pgn);
    }
  }

  Future<void> _showNagChooser(ReviewReport report, int groupIndex) async {
    final int? selectedNag = report.effectiveQualityNagForTurn(groupIndex);
    await showQualityAnnotationSheet(
      context: context,
      selectedNag: selectedNag,
      keyPrefix: 'review_nag',
      onChanged: (int? nag) {
        unawaited(_setNagOverride(report, groupIndex, nag));
      },
    );
  }

  Future<void> _setNagOverride(
    ReviewReport report,
    int groupIndex,
    int? nag,
  ) async {
    final Map<int, int?> overrides = Map<int, int?>.from(
      report.userNagOverrides,
    )..[groupIndex] = nag;
    final DateTime now = DateTime.now().toUtc();
    final ReviewReport updated = report.copyWith(
      userNagOverrides: overrides,
      updatedAt: now,
      lastAccessedAt: now,
    );
    await widget.storage.saveReport(updated);
    if (mounted) {
      setState(() => _report = updated);
    }
  }

  Future<void> _setExportPreference(ReviewReport report, bool value) async {
    final DateTime now = DateTime.now().toUtc();
    final ReviewReport updated = report.copyWith(
      includeAnnotationsOnExport: value,
      updatedAt: now,
      lastAccessedAt: now,
    );
    await widget.storage.saveReport(updated);
    if (mounted) {
      setState(() => _report = updated);
    }
  }

  static String _formatPrincipalVariation(
    List<String> actions, {
    required ReviewSide startingSide,
    required int startingMoveNumber,
  }) {
    final List<String> turns = <String>[];
    for (final String action in actions) {
      if (action.startsWith('x') && turns.isNotEmpty) {
        turns[turns.length - 1] = '${turns.last}$action';
      } else {
        turns.add(action);
      }
    }

    ReviewSide side = startingSide;
    int moveNumber = startingMoveNumber;
    final List<String> numberedTurns = <String>[];
    for (final String turn in turns) {
      final String prefix = side == ReviewSide.white
          ? '$moveNumber.'
          : '$moveNumber...';
      numberedTurns.add('$prefix $turn');
      if (side == ReviewSide.black) {
        moveNumber++;
      }
      side = side == ReviewSide.white ? ReviewSide.black : ReviewSide.white;
    }
    return numberedTurns.join(' ');
  }

  static int _moveNumberForTurn(
    ReviewReport report,
    ReviewTurnBoundary selectedTurn,
  ) {
    int moveNumber = 1;
    for (final ReviewTurnBoundary turn in report.turns) {
      if (turn.groupIndex == selectedTurn.groupIndex) {
        break;
      }
      if (turn.side == ReviewSide.black) {
        moveNumber++;
      }
    }
    return moveNumber;
  }

  int _firstKeyGroup(ReviewReport report) {
    for (final ReviewActionEvaluation action in report.actions) {
      if (action.grade == ReviewGrade.dubious ||
          action.grade == ReviewGrade.mistake ||
          action.grade == ReviewGrade.blunder) {
        return action.groupIndex;
      }
    }
    return report.turns.isEmpty ? 0 : report.turns.last.groupIndex;
  }

  String _nagTextForTurn(ReviewReport? report, ReviewTurnBoundary turn) {
    if (report == null) {
      return turn.sourceNags.map(_nagSymbol).join(' ');
    }
    final List<int> nags = turn.sourceNags
        .where((int nag) => nag < 1 || nag > 6)
        .toList();
    final int? qualityNag = report.effectiveQualityNagForTurn(turn.groupIndex);
    if (qualityNag != null) {
      nags.insert(0, qualityNag);
    }
    return nags.map(_nagSymbol).join(' ');
  }

  static String _nagSymbol(int nag) => switch (nag) {
    1 => '!',
    2 => '?',
    3 => '!!',
    4 => '??',
    5 => '!?',
    6 => '?!',
    _ => '\$$nag',
  };

  String _gradeLabel(BuildContext context, ReviewGrade grade) {
    final S strings = S.of(context);
    return switch (grade) {
      ReviewGrade.best => strings.reviewGradeBest,
      ReviewGrade.good => strings.reviewGradeGood,
      ReviewGrade.dubious => strings.reviewGradeDubious,
      ReviewGrade.mistake => strings.reviewGradeMistake,
      ReviewGrade.blunder => strings.reviewGradeBlunder,
    };
  }

  static String _gradeSymbol(ReviewGrade grade) => switch (grade) {
    ReviewGrade.best => '★',
    ReviewGrade.good => '✓',
    ReviewGrade.dubious => '?!',
    ReviewGrade.mistake => '?',
    ReviewGrade.blunder => '??',
  };

  static Color _gradeColor(ReviewGrade grade) =>
      MiniBoardPainter.qualityBadgeBackgroundColor(_nagForGradeColor(grade));

  static Color _gradeForegroundColor(ReviewGrade grade) =>
      MiniBoardPainter.qualityBadgeForegroundColor(_nagForGradeColor(grade));

  static int _nagForGradeColor(ReviewGrade grade) => switch (grade) {
    ReviewGrade.best => 1,
    ReviewGrade.good => 3,
    ReviewGrade.dubious => 6,
    ReviewGrade.mistake => 2,
    ReviewGrade.blunder => 4,
  };

  static String _reviewPlayerName(S strings, String player) {
    return switch (player.trim().toLowerCase()) {
      'ai' || 'computer' => strings.ai,
      'human' => strings.human,
      _ => player,
    };
  }

  String _nagLabel(BuildContext context, int nag) {
    final S strings = S.of(context);
    return switch (nag) {
      1 => strings.reviewGradeGood,
      2 => strings.reviewGradeMistake,
      3 => strings.reviewGradeBrilliant,
      4 => strings.reviewGradeBlunder,
      5 => strings.reviewGradeInteresting,
      6 => strings.reviewGradeDubious,
      _ => '',
    };
  }

  static int _countVariations(PgnNode<PgnNodeData> root) {
    int count = root.children.length > 1 ? root.children.length - 1 : 0;
    for (final PgnNode<PgnNodeData> child in root.children) {
      count += _countVariations(child);
    }
    return count;
  }
}

class _ReviewPlayerHeader extends StatelessWidget {
  const _ReviewPlayerHeader({
    required this.seat,
    required this.player,
    required this.pieceColor,
    required this.semanticLabel,
  });

  final String seat;
  final String player;
  final Color pieceColor;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Column(
        children: <Widget>[
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: pieceColor,
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            seat,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          Text(
            player,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

class _ReviewGradeBadge extends StatelessWidget {
  const _ReviewGradeBadge({
    required this.symbol,
    required this.color,
    required this.foregroundColor,
  });

  final String symbol;
  final Color color;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        symbol,
        style: TextStyle(
          color: foregroundColor,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}
