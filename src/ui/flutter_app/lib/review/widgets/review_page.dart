// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../game_page/services/import_export/pgn.dart';
import '../../game_page/widgets/mini_board.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/services/logger.dart';
import '../models/review_models.dart';
import '../services/review_analysis_service.dart';
import '../services/review_nag_merge.dart';
import '../services/review_storage.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({
    super.key,
    required this.record,
    this.initialReport,
    this.autoAnalyze = true,
    this.analysisService,
  });

  final PrivateGameRecord record;
  final ReviewReport? initialReport;
  final bool autoAnalyze;
  final ReviewAnalysisService? analysisService;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late final ReviewAnalysisService _analysisService;
  late final int _structuralTurnCount;
  late final int _structuralAtomicCount;
  late final int _structuralVariationCount;

  ReviewReport? _report;
  Object? _error;
  int _completedActions = 0;
  int _analysisRun = 0;
  int _selectedGroup = 0;
  bool _analyzing = true;
  bool _deepening = false;
  bool _analysisCancelled = false;
  int _correctionIndex = 0;
  String? _correctionChoice;
  bool _correctionPassed = false;
  bool _showCorrectionAnswer = false;

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
    _analyzing = widget.autoAnalyze;
    if (_report != null && _report!.turns.isNotEmpty) {
      _selectedGroup = _firstKeyGroup(_report!);
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
        if (report.turns.isNotEmpty) {
          _selectedGroup = _firstKeyGroup(report);
        }
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
      body: LayoutBuilder(
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
                  child: Column(
                    children: <Widget>[
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 620),
                            child: board,
                          ),
                        ),
                      ),
                      navigation,
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(flex: 4, child: panel),
              ],
            );
          }
          return ListView(
            key: const Key('review_phone_layout'),
            padding: const EdgeInsets.only(bottom: 24),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 560),
                  child: board,
                ),
              ),
              navigation,
              panel,
            ],
          );
        },
      ),
    );
  }

  Widget _buildTurnNavigation(BuildContext context) {
    final ReviewReport? report = _report;
    if (report == null || report.turns.isEmpty) {
      return const SizedBox.shrink();
    }
    final int selectedIndex = report.turns.indexWhere(
      (ReviewTurnBoundary turn) => turn.groupIndex == _selectedGroup,
    );
    final int currentIndex = selectedIndex < 0 ? 0 : selectedIndex;
    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );

    void selectIndex(int index) {
      assert(index >= 0 && index < report.turns.length);
      setState(() => _selectedGroup = report.turns[index].groupIndex);
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
              tooltip: localizations.firstPageTooltip,
              onPressed: currentIndex == 0 ? null : () => selectIndex(0),
              icon: const Icon(Icons.first_page_rounded),
            ),
            IconButton(
              key: const Key('review_previous_turn'),
              tooltip: localizations.previousPageTooltip,
              onPressed: currentIndex == 0
                  ? null
                  : () => selectIndex(currentIndex - 1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Semantics(
              label: S
                  .of(context)
                  .reviewProgress(currentIndex + 1, report.turns.length),
              child: Text(
                '${currentIndex + 1}/${report.turns.length}',
                key: const Key('review_turn_progress'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            IconButton(
              key: const Key('review_next_turn'),
              tooltip: localizations.nextPageTooltip,
              onPressed: currentIndex == report.turns.length - 1
                  ? null
                  : () => selectIndex(currentIndex + 1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
            IconButton(
              key: const Key('review_last_turn'),
              tooltip: localizations.lastPageTooltip,
              onPressed: currentIndex == report.turns.length - 1
                  ? null
                  : () => selectIndex(report.turns.length - 1),
              icon: const Icon(Icons.last_page_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoard(BuildContext context) {
    final ReviewReport? report = _report;
    ReviewTurnBoundary? selectedTurn;
    if (report != null && report.turns.isNotEmpty) {
      selectedTurn = report.turns.firstWhere(
        (ReviewTurnBoundary turn) => turn.groupIndex == _selectedGroup,
        orElse: () => report.turns.first,
      );
    }
    final String boardLayout =
        selectedTurn?.boardLayout ??
        widget.record.finalBoardLayout ??
        '********/********/********';
    final int? nag = selectedTurn == null
        ? null
        : report!.effectiveQualityNagForTurn(selectedTurn.groupIndex);
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
        ),
      ),
    );
  }

  Widget _buildPanel(
    BuildContext context, {
    required bool useCollapsibleMoveList,
  }) {
    return ListView(
      key: const Key('review_analysis_panel'),
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: <Widget>[
        _buildStructureSummary(context),
        const SizedBox(height: 12),
        if (_analyzing)
          _buildProgress(context)
        else if (_analysisCancelled)
          _buildCancelled(context)
        else if (_error != null)
          _buildError(context)
        else if (_report case final ReviewReport report) ...<Widget>[
          if (report.status == ReviewStatus.cancelled)
            _buildCancelled(context)
          else if (report.turns.isEmpty || report.actions.isEmpty)
            Card(child: ListTile(title: Text(S.of(context).noMove)))
          else ...<Widget>[
            if (!useCollapsibleMoveList) ...<Widget>[
              _buildMoveList(context, report),
              const SizedBox(height: 12),
            ],
            _buildSelectedTurnDetail(context, report),
            const SizedBox(height: 12),
            _buildCorrection(context, report),
            if (useCollapsibleMoveList) ...<Widget>[
              const SizedBox(height: 12),
              _buildCollapsibleMoveList(context, report),
            ],
          ],
        ],
      ],
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

  Widget _buildMoveList(BuildContext context, ReviewReport report) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _buildMoveChips(report),
      ),
    );
  }

  Widget _buildCollapsibleMoveList(BuildContext context, ReviewReport report) {
    final int selectedIndex = report.turns.indexWhere(
      (ReviewTurnBoundary turn) => turn.groupIndex == _selectedGroup,
    );
    return Card(
      key: const Key('review_collapsible_move_list'),
      child: ExpansionTile(
        title: Text(S.of(context).moves),
        subtitle: Text(
          '${selectedIndex + 1}/${report.turns.length}',
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

  Widget _buildMoveChips(ReviewReport report) {
    return Wrap(
      key: const Key('review_move_list'),
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final ReviewTurnBoundary turn in report.turns)
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
    final Iterable<ReviewActionEvaluation> actions = report.actions.where(
      (ReviewActionEvaluation action) => action.groupIndex == turn.groupIndex,
    );
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
            const SizedBox(height: 8),
            Text(
              strings.reviewBestLine(
                actions.first.candidates.first.line.join(' '),
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
    final List<ReviewActionEvaluation> corrections = _correctionActions(report);
    if (corrections.isEmpty) {
      return Card(
        key: const Key('review_correction_empty'),
        child: ListTile(
          leading: const Icon(Icons.check_circle_outline_rounded),
          title: Text(strings.noHumanMistakesToCorrect),
        ),
      );
    }
    if (_correctionIndex >= corrections.length) {
      return Card(
        key: const Key('review_correction_complete'),
        child: ListTile(
          leading: const Icon(Icons.task_alt_rounded),
          title: Text(strings.correctionComplete),
          trailing: TextButton(
            onPressed: () => setState(() => _correctionIndex = 0),
            child: Text(strings.retry),
          ),
        ),
      );
    }
    final ReviewActionEvaluation correction = corrections[_correctionIndex];
    final ReviewTurnBoundary turn = report.turns.firstWhere(
      (ReviewTurnBoundary value) => value.groupIndex == correction.groupIndex,
    );
    final List<ReviewCandidate> visibleCandidates = correction.candidates
        .take(6)
        .toList(growable: false);
    return Card(
      key: const Key('review_correction'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    strings.interactiveCorrection,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  strings.reviewProgress(
                    _correctionIndex + 1,
                    corrections.length,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(strings.correctionPrompt(turn.san)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final ReviewCandidate candidate in visibleCandidates)
                  ChoiceChip(
                    key: Key('review_correction_choice_${candidate.move}'),
                    label: Text(
                      _correctionCandidateNotation(correction, turn, candidate),
                    ),
                    selected: _correctionChoice == candidate.move,
                    onSelected: (_) => _chooseCorrection(correction, candidate),
                  ),
              ],
            ),
            if (_correctionChoice != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _correctionPassed
                    ? strings.correctionAccepted
                    : strings.correctionTryAgain,
              ),
            ],
            if (_showCorrectionAnswer) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                strings.correctionAnswer(
                  _correctionCandidateNotation(
                    correction,
                    turn,
                    correction.candidates.first,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: <Widget>[
                TextButton(
                  onPressed: _correctionChoice == null
                      ? null
                      : () => setState(() {
                          _correctionChoice = null;
                          _correctionPassed = false;
                          _showCorrectionAnswer = false;
                        }),
                  child: Text(strings.retry),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _showCorrectionAnswer = true;
                    _correctionChoice = correction.candidates.first.move;
                    _correctionPassed = true;
                  }),
                  child: Text(strings.showAnswer),
                ),
                TextButton(
                  onPressed: _nextCorrection,
                  child: Text(strings.skip),
                ),
                if (_correctionPassed)
                  FilledButton(
                    onPressed: _nextCorrection,
                    child: Text(strings.next),
                  ),
              ],
            ),
          ],
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
    final String pgn = ReviewNagMerge.forExport(
      widget.record.sourcePgn,
      report,
    );
    await Clipboard.setData(ClipboardData(text: pgn));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(S.of(context).moveHistoryCopied)));
    }
  }

  Future<void> _showNagChooser(ReviewReport report, int groupIndex) async {
    final S strings = S.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    unawaited(_setNagOverride(report, groupIndex, null));
                  },
                  child: Text(strings.clearAnnotation),
                ),
                for (int nag = 1; nag <= 6; nag++)
                  Semantics(
                    key: Key('review_nag_$nag'),
                    label: '${_nagSymbol(nag)} ${_nagLabel(context, nag)}',
                    button: true,
                    excludeSemantics: true,
                    child: FilledButton.tonal(
                      onPressed: () {
                        Navigator.pop(context);
                        unawaited(_setNagOverride(report, groupIndex, nag));
                      },
                      child: Text(_nagSymbol(nag)),
                    ),
                  ),
              ],
            ),
          ),
        );
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
    await ReviewStorage.instance.saveReport(updated);
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
    await ReviewStorage.instance.saveReport(updated);
    if (mounted) {
      setState(() => _report = updated);
    }
  }

  void _chooseCorrection(
    ReviewActionEvaluation correction,
    ReviewCandidate candidate,
  ) {
    final ReviewGrade grade = ReviewGrading.grade(
      bestScore: correction.candidates.first.score,
      playedScore: candidate.score,
    );
    setState(() {
      _correctionChoice = candidate.move;
      _correctionPassed =
          grade == ReviewGrade.best || grade == ReviewGrade.good;
      _showCorrectionAnswer = false;
    });
  }

  void _nextCorrection() {
    setState(() {
      _correctionIndex++;
      _correctionChoice = null;
      _correctionPassed = false;
      _showCorrectionAnswer = false;
    });
  }

  static List<ReviewActionEvaluation> _correctionActions(ReviewReport report) {
    final Map<int, ReviewActionEvaluation> worstByGroup =
        <int, ReviewActionEvaluation>{};
    for (final ReviewActionEvaluation action in report.humanMistakes) {
      final ReviewActionEvaluation? current = worstByGroup[action.groupIndex];
      if (current == null || action.grade.index > current.grade.index) {
        worstByGroup[action.groupIndex] = action;
      }
    }
    final List<ReviewActionEvaluation> result = worstByGroup.values.toList()
      ..sort(
        (ReviewActionEvaluation a, ReviewActionEvaluation b) =>
            a.groupIndex.compareTo(b.groupIndex),
      );
    return result;
  }

  static String _correctionCandidateNotation(
    ReviewActionEvaluation correction,
    ReviewTurnBoundary turn,
    ReviewCandidate candidate,
  ) {
    final List<String> originalSegments = splitMillSan(turn.san);
    final int relativeIndex = correction.atomicIndex - turn.startAtomicIndex;
    assert(relativeIndex >= 0 && relativeIndex < originalSegments.length);
    final StringBuffer notation = StringBuffer(
      originalSegments.take(relativeIndex).join(),
    )..write(candidate.move);
    for (final String continuation in candidate.line.skip(1)) {
      if (!continuation.startsWith('x')) {
        break;
      }
      notation.write(continuation);
    }
    return notation.toString();
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

  String _nagTextForTurn(ReviewReport report, ReviewTurnBoundary turn) {
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
