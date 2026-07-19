// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../../game_page/services/import_export/pgn.dart';
import '../../game_platform/game_session.dart';
import '../../games/mill/mill_action_codec.dart';
import '../../games/mill/mill_session_tap_controller.dart';
import '../../games/mill/native_mill_game_session.dart';
import '../../games/mill/widgets/mill_session_board.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../models/review_models.dart';
import '../services/review_analysis_service.dart' show splitMillSan;

enum _CorrectionAttemptState { playing, accepted, rejected, answer }

class ReviewCorrectionPage extends StatefulWidget {
  const ReviewCorrectionPage({
    super.key,
    required this.record,
    required this.report,
  });

  final PrivateGameRecord record;
  final ReviewReport report;

  @override
  State<ReviewCorrectionPage> createState() => _ReviewCorrectionPageState();
}

class _ReviewCorrectionPageState extends State<ReviewCorrectionPage> {
  final MillSessionTapController _tapController = MillSessionTapController();
  late final PgnGame<PgnNodeData> _game;
  late final List<PgnNodeData> _groupedMoves;
  late final List<_ReviewCorrectionTask> _tasks;
  final List<String> _attemptActions = <String>[];

  NativeMillGameSession? _session;
  int _taskIndex = 0;
  _CorrectionAttemptState _attemptState = _CorrectionAttemptState.playing;

  @override
  void initState() {
    super.initState();
    assert(widget.report.recordId == widget.record.id);
    _game = PgnGame.parsePgn(widget.record.sourcePgn);
    _groupedMoves = _game.moves.mainline().toList(growable: false);
    _tasks = widget.report.correctionActions
        .map(
          (ReviewActionEvaluation action) => _ReviewCorrectionTask.fromReport(
            action: action,
            turn: widget.report.turns.firstWhere(
              (ReviewTurnBoundary turn) => turn.groupIndex == action.groupIndex,
            ),
          ),
        )
        .toList(growable: false);
    if (_tasks.isNotEmpty) {
      _restoreCurrentTask();
    }
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  void _restoreCurrentTask() {
    assert(_taskIndex >= 0 && _taskIndex < _tasks.length);
    _session?.dispose();
    final NativeMillGameSession session = NativeMillGameSession(
      rules: widget.record.rules,
      generalSettings: DB().generalSettings,
    );
    final String setupFen =
        _game.headers['FEN']?.trim() ?? widget.record.initialFen;
    if (setupFen.isNotEmpty && !session.loadFen(setupFen)) {
      session.dispose();
      throw StateError('Correction record carries an invalid initial FEN.');
    }

    final int targetGroup = _tasks[_taskIndex].turn.groupIndex;
    assert(targetGroup >= 0 && targetGroup < _groupedMoves.length);
    for (int groupIndex = 0; groupIndex < targetGroup; groupIndex++) {
      for (final String action in splitMillSan(_groupedMoves[groupIndex].san)) {
        if (!session.applyMoveString(action)) {
          session.dispose();
          throw StateError(
            'Correction record contains an illegal action: $action',
          );
        }
      }
    }

    final ReviewSide expectedSide = _tasks[_taskIndex].turn.side;
    final ReviewSide actualSide = _reviewSide(session.state.value.activeSeat);
    assert(
      expectedSide == actualSide,
      'Correction must start before the reviewed grouped turn.',
    );
    _session = session;
    _tapController.clearSelection();
    _attemptActions.clear();
    _attemptState = _CorrectionAttemptState.playing;
  }

  void _handlePositionChanged({
    required String previousFen,
    required String currentFen,
    required GameAction action,
  }) {
    final NativeMillGameSession session = _session!;
    final String? notation = MillActionCodec.moveStringFrom(action);
    assert(
      notation != null && notation.isNotEmpty,
      'Correction actions must provide Mill notation.',
    );
    if (notation == null || notation.isEmpty) {
      throw StateError('Correction action has no Mill notation.');
    }
    _attemptActions.add(notation);

    final bool turnComplete =
        session.outcome.isTerminal ||
        !session.legalActions.any(
          (GameAction next) => next.type == MillActionTypes.remove,
        );
    setState(() {
      if (turnComplete) {
        _attemptState = _tasks[_taskIndex].accepts(_attemptActions)
            ? _CorrectionAttemptState.accepted
            : _CorrectionAttemptState.rejected;
      }
    });
  }

  void _retry() {
    setState(_restoreCurrentTask);
  }

  void _showAnswer() {
    _restoreCurrentTask();
    final NativeMillGameSession session = _session!;
    final List<String> answer = _tasks[_taskIndex].acceptedTurns.first;
    for (final String action in answer) {
      if (!session.applyMoveString(action)) {
        throw StateError(
          'Correction answer contains an illegal action: $action',
        );
      }
    }
    final bool answerComplete =
        session.outcome.isTerminal ||
        !session.legalActions.any(
          (GameAction next) => next.type == MillActionTypes.remove,
        );
    assert(answerComplete, 'Correction answer must complete the Mill turn.');
    if (!answerComplete) {
      throw StateError('Correction answer does not complete the Mill turn.');
    }
    _attemptActions.addAll(answer);
    setState(() => _attemptState = _CorrectionAttemptState.answer);
  }

  void _nextTask() {
    if (_taskIndex == _tasks.length - 1) {
      _session?.dispose();
      _session = null;
      setState(() => _taskIndex = _tasks.length);
      return;
    }
    setState(() {
      _taskIndex++;
      _restoreCurrentTask();
    });
  }

  void _restart() {
    setState(() {
      _taskIndex = 0;
      _restoreCurrentTask();
    });
  }

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.interactiveCorrection)),
      body: _tasks.isEmpty
          ? Center(
              child: Text(
                strings.noHumanMistakesToCorrect,
                key: const Key('review_correction_empty'),
              ),
            )
          : _taskIndex >= _tasks.length
          ? _buildCompletion(context)
          : _buildTask(context),
    );
  }

  Widget _buildCompletion(BuildContext context) {
    final S strings = S.of(context);
    return Center(
      child: Card(
        key: const Key('review_correction_complete'),
        margin: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.task_alt_rounded, size: 48),
              const SizedBox(height: 12),
              Text(
                strings.correctionComplete,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('review_correction_restart'),
                onPressed: _restart,
                icon: const Icon(Icons.replay_rounded),
                label: Text(strings.retry),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTask(BuildContext context) {
    final NativeMillGameSession session = _session!;
    final _ReviewCorrectionTask task = _tasks[_taskIndex];
    final S strings = S.of(context);
    final String sideLabel = task.turn.side == ReviewSide.white
        ? strings.whiteSMove
        : strings.blackSMove;
    final Widget board = MillSessionBoard(
      session: session,
      tapController: _tapController,
      rules: widget.record.rules,
      heightFactor: 0.82,
      onPositionChanged: _handlePositionChanged,
      boardKey: const Key('review_correction_board'),
      semanticLabel: '${strings.board}, $sideLabel',
      enabled: _attemptState == _CorrectionAttemptState.playing,
      highlightActions: List<String>.unmodifiable(_attemptActions),
    );
    final Widget panel = _buildTaskPanel(context, task, sideLabel);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 720;
        if (wide) {
          return Row(
            key: const Key('review_correction_wide_layout'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                flex: 3,
                child: Padding(padding: const EdgeInsets.all(16), child: board),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                flex: 2,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: panel,
                ),
              ),
            ],
          );
        }
        return ListView(
          key: const Key('review_correction_phone_layout'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: <Widget>[board, const SizedBox(height: 16), panel],
        );
      },
    );
  }

  Widget _buildTaskPanel(
    BuildContext context,
    _ReviewCorrectionTask task,
    String sideLabel,
  ) {
    final S strings = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                sideLabel,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Semantics(
              label: strings.reviewMoveProgress(_taskIndex + 1, _tasks.length),
              child: Text(
                strings.reviewProgress(_taskIndex + 1, _tasks.length),
                key: const Key('review_correction_progress'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(strings.correctionPrompt(task.turn.san)),
        if (_attemptState == _CorrectionAttemptState.accepted) ...<Widget>[
          const SizedBox(height: 16),
          _CorrectionFeedback(
            key: const Key('review_correction_accepted'),
            icon: Icons.check_circle_rounded,
            color: Theme.of(context).colorScheme.primary,
            text: strings.correctionAccepted,
          ),
        ],
        if (_attemptState == _CorrectionAttemptState.rejected) ...<Widget>[
          const SizedBox(height: 16),
          _CorrectionFeedback(
            key: const Key('review_correction_rejected'),
            icon: Icons.error_outline_rounded,
            color: Theme.of(context).colorScheme.error,
            text: strings.correctionTryAgain,
          ),
        ],
        if (_attemptState == _CorrectionAttemptState.answer) ...<Widget>[
          const SizedBox(height: 16),
          _CorrectionFeedback(
            key: const Key('review_correction_answer'),
            icon: Icons.lightbulb_outline_rounded,
            color: Theme.of(context).colorScheme.tertiary,
            text: strings.correctionAnswer(task.bestNotation),
          ),
        ],
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            if (_attemptState == _CorrectionAttemptState.rejected)
              OutlinedButton.icon(
                key: const Key('review_correction_retry'),
                onPressed: _retry,
                icon: const Icon(Icons.replay_rounded),
                label: Text(strings.retry),
              ),
            if (_attemptState == _CorrectionAttemptState.playing ||
                _attemptState == _CorrectionAttemptState.rejected)
              TextButton(
                key: const Key('review_correction_show_answer'),
                onPressed: _showAnswer,
                child: Text(strings.showAnswer),
              ),
            if (_attemptState == _CorrectionAttemptState.playing ||
                _attemptState == _CorrectionAttemptState.rejected)
              TextButton(
                key: const Key('review_correction_skip'),
                onPressed: _nextTask,
                child: Text(strings.skip),
              ),
            if (_attemptState == _CorrectionAttemptState.accepted ||
                _attemptState == _CorrectionAttemptState.answer)
              FilledButton(
                key: const Key('review_correction_next'),
                onPressed: _nextTask,
                child: Text(
                  _taskIndex == _tasks.length - 1 ? strings.done : strings.next,
                ),
              ),
          ],
        ),
      ],
    );
  }

  static ReviewSide _reviewSide(PlayerSeat seat) => switch (seat) {
    PlayerSeat.first => ReviewSide.white,
    PlayerSeat.second => ReviewSide.black,
    PlayerSeat.none => throw StateError(
      'Correction position has no active side.',
    ),
  };
}

class _CorrectionFeedback extends StatelessWidget {
  const _CorrectionFeedback({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Row(
        children: <Widget>[
          Icon(icon, color: color, semanticLabel: text),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ReviewCorrectionTask {
  const _ReviewCorrectionTask({
    required this.turn,
    required this.acceptedTurns,
  });

  factory _ReviewCorrectionTask.fromReport({
    required ReviewActionEvaluation action,
    required ReviewTurnBoundary turn,
  }) {
    assert(action.groupIndex == turn.groupIndex);
    assert(action.candidates.isNotEmpty);
    final List<String> segments = splitMillSan(turn.san);
    final int relativeIndex = action.atomicIndex - turn.startAtomicIndex;
    assert(relativeIndex >= 0 && relativeIndex < segments.length);
    final List<String> prefix = segments.take(relativeIndex).toList();
    final List<List<String>> accepted = <List<String>>[];
    for (final ReviewCandidate candidate in action.candidates) {
      final ReviewGrade grade = ReviewGrading.grade(
        bestScore: action.candidates.first.score,
        playedScore: candidate.score,
      );
      if (grade != ReviewGrade.best && grade != ReviewGrade.good) {
        continue;
      }
      final List<String> completeTurn = <String>[
        ...prefix,
        candidate.move,
        ...candidate.line
            .skip(1)
            .takeWhile((String continuation) => continuation.startsWith('x')),
      ];
      if (!accepted.any(
        (List<String> existing) => _sameActions(existing, completeTurn),
      )) {
        accepted.add(List<String>.unmodifiable(completeTurn));
      }
    }
    assert(accepted.isNotEmpty);
    return _ReviewCorrectionTask(
      turn: turn,
      acceptedTurns: List<List<String>>.unmodifiable(accepted),
    );
  }

  final ReviewTurnBoundary turn;
  final List<List<String>> acceptedTurns;

  bool accepts(List<String> actions) => acceptedTurns.any(
    (List<String> accepted) => _sameActions(accepted, actions),
  );

  String get bestNotation => acceptedTurns.first.join();

  static bool _sameActions(List<String> first, List<String> second) {
    if (first.length != second.length) {
      return false;
    }
    for (int index = 0; index < first.length; index++) {
      if (first[index] != second[index]) {
        return false;
      }
    }
    return true;
  }
}
