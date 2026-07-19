// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;

import '../game_page/services/transform/transform.dart';
import '../games/mill/mill_board_coordinate_maps.dart';
import '../games/mill/mill_board_geometry.dart';
import '../generated/intl/l10n.dart';
import '../rule_settings/models/rule_settings.dart';
import '../shared/database/database.dart';
import '../shared/widgets/lichess_bottom_bar.dart';
import '../shared/widgets/lichess_list_section.dart';
import 'coordinate_training_stats.dart';

const Duration _kGuessHighlightDuration = Duration(milliseconds: 220);
const Duration _kCoordinateTransitionDuration = Duration(milliseconds: 150);
const Offset _kNextCoordinateTranslation = Offset(0.72, 0.32);
const double _kNextCoordinateScale = 0.42;
const double _kCurrentCoordinateOpacity = 0.9;
const double _kNextCoordinateOpacity = 0.68;
const double _kTrainingPanelMinHeight = 96;
const Duration _kTimedTrainingDuration = Duration(seconds: 30);

enum _CoordinateTrainingOrientationChoice { standard, flipped, random }

enum _CoordinateTrainingDurationChoice { thirtySeconds, untimed }

class MillCoordinateTrainingPage extends StatefulWidget {
  const MillCoordinateTrainingPage({super.key});

  @override
  State<MillCoordinateTrainingPage> createState() =>
      _MillCoordinateTrainingPageState();
}

class _MillCoordinateTrainingPageState extends State<MillCoordinateTrainingPage>
    with SingleTickerProviderStateMixin {
  final math.Random _random = math.Random();

  Timer? _highlightTimer;
  late final AnimationController _trainingTimerController = AnimationController(
    vsync: this,
    duration: _kTimedTrainingDuration,
  )..addStatusListener(_handleTrainingTimerStatus);
  late CoordinateTrainingStats _statistics;

  int? _currentNode;
  int? _nextNode;
  int? _lastGuessNode;
  bool? _lastGuessCorrect;
  int _score = 0;
  int _attempts = 0;
  int? _lastScore;
  int? _lastAttempts;
  bool _trainingActive = false;
  _CoordinateTrainingOrientationChoice _orientationChoice =
      _CoordinateTrainingOrientationChoice.random;
  _CoordinateTrainingDurationChoice _durationChoice =
      _CoordinateTrainingDurationChoice.thirtySeconds;
  late TransformationType _currentTransform = _newTransformForChoice(
    _orientationChoice,
  );
  bool _showCoordinates = false;

  @override
  void initState() {
    super.initState();
    _statistics = CoordinateTrainingStatsStore.load();
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _trainingTimerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);

    return Scaffold(
      key: const Key('mill_coordinate_training_page_scaffold'),
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(strings.coordinateTraining),
        actions: <Widget>[
          IconButton(
            key: const Key('mill_coordinate_training_settings_button'),
            tooltip: strings.settings,
            icon: Icon(
              Icons.settings_outlined,
              semanticLabel: strings.settings,
            ),
            onPressed: _showDisplaySettingsSheet,
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: ValueListenableBuilder<Box<RuleSettings>>(
                valueListenable: DB().listenRuleSettings,
                builder:
                    (
                      BuildContext context,
                      Box<RuleSettings> box,
                      Widget? child,
                    ) {
                      final bool hasDiagonalLines =
                          DB().ruleSettings.hasDiagonalLines;
                      return _TrainingLayout(
                        hasDiagonalLines: hasDiagonalLines,
                        showCoordinates: _showCoordinates,
                        transform: _currentTransform,
                        trainingActive: _trainingActive,
                        isTimed:
                            _durationChoice ==
                            _CoordinateTrainingDurationChoice.thirtySeconds,
                        trainingTimer: _trainingTimerController,
                        score: _score,
                        attempts: _attempts,
                        lastScore: _lastScore,
                        lastAttempts: _lastAttempts,
                        statistics: _statistics,
                        currentNode: _currentNode,
                        nextNode: _nextNode,
                        lastGuessNode: _lastGuessNode,
                        lastGuessCorrect: _lastGuessCorrect,
                        onGuess: _guessNode,
                        onStart: _startTraining,
                        onFinish: _finishTraining,
                      );
                    },
              ),
            ),
            if (!_trainingActive)
              LichessBottomBar(
                key: const Key('mill_coordinate_training_bottom_bar'),
                children: <Widget>[
                  LichessBottomBarButton(
                    key: const Key('mill_coordinate_training_menu_button'),
                    icon: Icons.tune_rounded,
                    label: strings.boardOrientation,
                    showLabel: true,
                    onTap: _showTrainingMenuSheet,
                  ),
                  LichessBottomBarButton(
                    key: const Key('mill_coordinate_training_info_button'),
                    icon: Icons.info_outline_rounded,
                    label: strings.about,
                    showLabel: true,
                    onTap: _showInfoDialog,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _startTraining() {
    final int currentNode = _randomNode();
    setState(() {
      _currentTransform = _newTransformForChoice(_orientationChoice);
      _currentNode = currentNode;
      _nextNode = _randomNode(previous: currentNode);
      _lastGuessNode = null;
      _lastGuessCorrect = null;
      _score = 0;
      _attempts = 0;
      _trainingActive = true;
    });
    if (_durationChoice == _CoordinateTrainingDurationChoice.thirtySeconds) {
      _trainingTimerController.forward(from: 0);
    } else {
      _trainingTimerController.reset();
    }
  }

  void _finishTraining() {
    if (!_trainingActive) {
      return;
    }
    _trainingTimerController.stop();
    final CoordinateTrainingStats statistics = _statistics.recordSession(
      isThirtySeconds:
          _durationChoice == _CoordinateTrainingDurationChoice.thirtySeconds,
      correct: _score,
      attempts: _attempts,
    );
    unawaited(CoordinateTrainingStatsStore.save(statistics));
    setState(() {
      _statistics = statistics;
      _lastScore = _score;
      _lastAttempts = _attempts;
      _currentNode = null;
      _nextNode = null;
      _lastGuessNode = null;
      _lastGuessCorrect = null;
      _trainingActive = false;
    });
  }

  void _handleTrainingTimerStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _trainingActive) {
      _finishTraining();
    }
  }

  int _randomNode({int? previous}) {
    int node = _random.nextInt(MillBoardGeometry.nodeCount);
    while (node == previous) {
      node = _random.nextInt(MillBoardGeometry.nodeCount);
    }
    return node;
  }

  TransformationType _newTransformForChoice(
    _CoordinateTrainingOrientationChoice choice,
  ) {
    return switch (choice) {
      _CoordinateTrainingOrientationChoice.standard =>
        TransformationType.identity,
      _CoordinateTrainingOrientationChoice.flipped =>
        TransformationType.rotate180,
      _CoordinateTrainingOrientationChoice.random =>
        _random.nextBool()
            ? TransformationType.identity
            : TransformationType.rotate180,
    };
  }

  String _orientationChoiceLabel(
    S strings,
    _CoordinateTrainingOrientationChoice choice,
  ) {
    return switch (choice) {
      _CoordinateTrainingOrientationChoice.standard =>
        strings.coordinateTrainingStandardOrientation,
      _CoordinateTrainingOrientationChoice.flipped =>
        strings.coordinateTrainingFlippedOrientation,
      _CoordinateTrainingOrientationChoice.random => strings.randomColor,
    };
  }

  String _durationChoiceLabel(
    S strings,
    _CoordinateTrainingDurationChoice choice,
  ) {
    return switch (choice) {
      _CoordinateTrainingDurationChoice.thirtySeconds =>
        strings.coordinateTrainingThirtySeconds,
      _CoordinateTrainingDurationChoice.untimed =>
        strings.coordinateTrainingUntimed,
    };
  }

  void _guessNode(int node) {
    if (!_trainingActive) {
      return;
    }
    final int? current = _currentNode;
    assert(current != null, 'Active coordinate training needs a target node.');
    final bool correct = node == current;

    setState(() {
      _attempts += 1;
      _lastGuessNode = node;
      _lastGuessCorrect = correct;
      if (correct) {
        _score += 1;
        _currentNode = _nextNode;
        _nextNode = _randomNode(previous: _nextNode);
      }
    });

    _highlightTimer?.cancel();
    _highlightTimer = Timer(_kGuessHighlightDuration, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastGuessNode = null;
        _lastGuessCorrect = null;
      });
    });
  }

  void _showDisplaySettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        final S strings = S.of(context);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            children: <Widget>[
              LichessListSection(
                header: Text(strings.settings),
                children: <Widget>[
                  SwitchListTile(
                    key: const Key('mill_coordinate_training_show_coordinates'),
                    title: Text(strings.coordinateTrainingShowCoordinates),
                    value: _showCoordinates,
                    onChanged: (bool value) {
                      setState(() {
                        _showCoordinates = value;
                      });
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTrainingMenuSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        final S strings = S.of(context);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            children: <Widget>[
              LichessListSection(
                header: Text(strings.boardOrientation),
                children: <Widget>[
                  for (final _CoordinateTrainingOrientationChoice choice
                      in _CoordinateTrainingOrientationChoice.values)
                    ListTile(
                      key: Key(
                        'mill_coordinate_training_orientation_${choice.name}',
                      ),
                      title: Text(_orientationChoiceLabel(strings, choice)),
                      trailing: choice == _orientationChoice
                          ? Icon(
                              Icons.check_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                      onTap: () {
                        setState(() {
                          _orientationChoice = choice;
                          _currentTransform = _newTransformForChoice(choice);
                          _lastGuessNode = null;
                          _lastGuessCorrect = null;
                        });
                        Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
              LichessListSection(
                header: Text(strings.timeControl),
                children: <Widget>[
                  for (final _CoordinateTrainingDurationChoice choice
                      in _CoordinateTrainingDurationChoice.values)
                    ListTile(
                      key: Key(
                        'mill_coordinate_training_duration_${choice == _CoordinateTrainingDurationChoice.thirtySeconds ? '30' : 'untimed'}',
                      ),
                      title: Text(_durationChoiceLabel(strings, choice)),
                      trailing: choice == _durationChoice
                          ? Icon(
                              Icons.check_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                      onTap: () {
                        setState(() {
                          _durationChoice = choice;
                        });
                        Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showInfoDialog() {
    final S strings = S.of(context);
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(strings.coordinateTraining),
          content: Text(strings.coordinateTrainingDescription),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.ok),
            ),
          ],
        );
      },
    );
  }
}

class _TrainingLayout extends StatelessWidget {
  const _TrainingLayout({
    required this.hasDiagonalLines,
    required this.showCoordinates,
    required this.transform,
    required this.trainingActive,
    required this.isTimed,
    required this.trainingTimer,
    required this.score,
    required this.attempts,
    required this.lastScore,
    required this.lastAttempts,
    required this.statistics,
    required this.currentNode,
    required this.nextNode,
    required this.lastGuessNode,
    required this.lastGuessCorrect,
    required this.onGuess,
    required this.onStart,
    required this.onFinish,
  });

  final bool hasDiagonalLines;
  final bool showCoordinates;
  final TransformationType transform;
  final bool trainingActive;
  final bool isTimed;
  final Animation<double> trainingTimer;
  final int score;
  final int attempts;
  final int? lastScore;
  final int? lastAttempts;
  final CoordinateTrainingStats statistics;
  final int? currentNode;
  final int? nextNode;
  final int? lastGuessNode;
  final bool? lastGuessCorrect;
  final ValueChanged<int> onGuess;
  final VoidCallback onStart;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool landscape = constraints.maxWidth > constraints.maxHeight;
        final Axis direction = landscape ? Axis.horizontal : Axis.vertical;
        final double maxBoardHeight = landscape
            ? constraints.maxHeight - 24
            : constraints.maxHeight - _kTrainingPanelMinHeight;
        final double boardSize = math.max(
          0,
          landscape
              ? math.min(maxBoardHeight, constraints.maxWidth * 0.62)
              : math.min(constraints.maxWidth, maxBoardHeight),
        );

        final Widget board = SizedBox.square(
          dimension: boardSize,
          child: _MillTrainingBoard(
            hasDiagonalLines: hasDiagonalLines,
            showCoordinates: showCoordinates,
            transform: transform,
            trainingActive: trainingActive,
            currentNode: currentNode,
            nextNode: nextNode,
            lastGuessNode: lastGuessNode,
            lastGuessCorrect: lastGuessCorrect,
            onGuess: onGuess,
          ),
        );

        final Widget panel = _TrainingPanel(
          score: score,
          attempts: attempts,
          lastScore: lastScore,
          lastAttempts: lastAttempts,
          trainingActive: trainingActive,
          isTimed: isTimed,
          trainingTimer: trainingTimer,
          statistics: statistics,
          onStart: onStart,
          onFinish: onFinish,
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Flex(
            direction: direction,
            children: <Widget>[
              Align(alignment: Alignment.topCenter, child: board),
              Expanded(child: panel),
            ],
          ),
        );
      },
    );
  }
}

class _TrainingPanel extends StatelessWidget {
  const _TrainingPanel({
    required this.score,
    required this.attempts,
    required this.lastScore,
    required this.lastAttempts,
    required this.trainingActive,
    required this.isTimed,
    required this.trainingTimer,
    required this.statistics,
    required this.onStart,
    required this.onFinish,
  });

  final int score;
  final int attempts;
  final int? lastScore;
  final int? lastAttempts;
  final bool trainingActive;
  final bool isTimed;
  final Animation<double> trainingTimer;
  final CoordinateTrainingStats statistics;
  final VoidCallback onStart;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);

    if (trainingActive) {
      return _ActiveTrainingPanel(
        score: score,
        attempts: attempts,
        isTimed: isTimed,
        trainingTimer: trainingTimer,
        onFinish: onFinish,
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (lastScore != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                strings.coordinateTrainingResultWithAccuracy(
                  lastScore!,
                  lastAttempts ?? 0,
                  _accuracyPercent(lastScore!, lastAttempts ?? 0),
                ),
                key: const Key('mill_coordinate_training_last_result'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('mill_coordinate_training_start_button'),
              onPressed: onStart,
              child: Text(
                strings.coordinateTrainingStart,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 12),
            _CoordinateTrainingStatistics(statistics: statistics),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ActiveTrainingPanel extends StatelessWidget {
  const _ActiveTrainingPanel({
    required this.score,
    required this.attempts,
    required this.isTimed,
    required this.trainingTimer,
    required this.onFinish,
  });

  final int score;
  final int attempts;
  final bool isTimed;
  final Animation<double> trainingTimer;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        if (isTimed)
          AnimatedBuilder(
            animation: trainingTimer,
            builder: (BuildContext context, Widget? child) {
              final double remaining = 1 - trainingTimer.value;
              final int seconds = math.max(
                0,
                (_kTimedTrainingDuration.inSeconds * remaining).ceil(),
              );
              return Padding(
                key: const Key('mill_coordinate_training_time_bar'),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: <Widget>[
                    Text(
                      strings.coordinateTrainingTimeRemaining(seconds),
                      key: const Key('mill_coordinate_training_time_remaining'),
                      style: const TextStyle(
                        fontFeatures: <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: remaining),
                  ],
                ),
              );
            },
          ),
        _ScoreAndButton(
          score: score,
          attempts: attempts,
          buttonLabel: strings.coordinateTrainingFinish,
          onPressed: onFinish,
        ),
      ],
    );
  }
}

class _ScoreAndButton extends StatelessWidget {
  const _ScoreAndButton({
    required this.score,
    required this.attempts,
    required this.buttonLabel,
    required this.onPressed,
  });

  final int score;
  final int attempts;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        ExcludeSemantics(
          child: Container(
            key: const Key('mill_coordinate_training_score'),
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              score.toString(),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        Text(S.of(context).coordinateTrainingResult(score, attempts)),
        FilledButton(
          key: const Key('mill_coordinate_training_action_button'),
          onPressed: onPressed,
          child: Text(buttonLabel),
        ),
      ],
    );
  }
}

class _CoordinateTrainingStatistics extends StatelessWidget {
  const _CoordinateTrainingStatistics({required this.statistics});

  final CoordinateTrainingStats statistics;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final List<(String, String)> items = <(String, String)>[
      (
        strings.coordinateTrainingSessions,
        statistics.trainingSessions.toString(),
      ),
      (
        strings.coordinateTrainingThirtySecondBest,
        statistics.thirtySecondBestCorrect.toString(),
      ),
      (
        strings.coordinateTrainingThirtySecondAverage,
        statistics.thirtySecondAverageCorrect.toStringAsFixed(1),
      ),
      (
        strings.coordinateTrainingTotalCorrect,
        statistics.totalCorrect.toString(),
      ),
      (
        strings.coordinateTrainingOverallAccuracy,
        '${(statistics.overallAccuracy * 100).toStringAsFixed(0)}%',
      ),
    ];

    return Column(
      key: const Key('mill_coordinate_training_statistics'),
      children: <Widget>[
        Text(
          strings.coordinateTrainingStatistics,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double itemWidth = math.max(
              112,
              (constraints.maxWidth - 8) / 2,
            );
            return Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: <Widget>[
                for (int index = 0; index < items.length; index++)
                  SizedBox(
                    key: Key('mill_coordinate_training_stat_$index'),
                    width: itemWidth,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            items[index].$1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          items[index].$2,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

int _accuracyPercent(int correct, int attempts) {
  if (attempts == 0) {
    return 0;
  }
  return (correct * 100 / attempts).round();
}

class _MillTrainingBoard extends StatelessWidget {
  const _MillTrainingBoard({
    required this.hasDiagonalLines,
    required this.showCoordinates,
    required this.transform,
    required this.trainingActive,
    required this.currentNode,
    required this.nextNode,
    required this.lastGuessNode,
    required this.lastGuessCorrect,
    required this.onGuess,
  });

  final bool hasDiagonalLines;
  final bool showCoordinates;
  final TransformationType transform;
  final bool trainingActive;
  final int? currentNode;
  final int? nextNode;
  final int? lastGuessNode;
  final bool? lastGuessCorrect;
  final ValueChanged<int> onGuess;

  @override
  Widget build(BuildContext context) {
    final int? current = currentNode;
    final int? next = nextNode;
    final List<int> transformMap = getTransformMap(transform);
    final List<int> inverseTransform = inverseTransformMap(transformMap);
    final bool isFlipped = transform == TransformationType.rotate180;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = Size(constraints.maxWidth, constraints.maxHeight);

        return GestureDetector(
          key: const Key('mill_coordinate_training_board'),
          behavior: HitTestBehavior.opaque,
          onTapUp: trainingActive
              ? (TapUpDetails details) {
                  final int node = MillBoardGeometry.nodeFromPosition(
                    details.localPosition,
                    size,
                  );
                  if (node >= 0) {
                    onGuess(inverseTransform[node]);
                  }
                }
              : null,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              CustomPaint(
                size: size,
                painter: _MillCoordinateTrainingPainter(
                  colorScheme: Theme.of(context).colorScheme,
                  hasDiagonalLines: hasDiagonalLines,
                  transformMap: transformMap,
                  lastGuessNode: lastGuessNode,
                  lastGuessCorrect: lastGuessCorrect,
                ),
              ),
              if (showCoordinates)
                ..._buildCoordinateAxisLabels(context, size, isFlipped),
              if (trainingActive && current != null && next != null)
                IgnorePointer(
                  child: _CoordinateDisplay(
                    currentNode: current,
                    nextNode: next,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildCoordinateAxisLabels(
    BuildContext context,
    Size size,
    bool isFlipped,
  ) {
    final double side = size.shortestSide;
    final double originX = (size.width - side) / 2;
    final double originY = (size.height - side) / 2;
    final double padding = side * MillBoardGeometry.defaultPaddingFraction;
    final double cell = (side - padding * 2) / 6;
    final TextStyle style = Theme.of(context).textTheme.labelSmall!.copyWith(
      color: Theme.of(context).colorScheme.onSurface,
      fontWeight: FontWeight.w700,
    );
    final List<Widget> labels = <Widget>[];

    for (int index = 0; index < 7; index++) {
      final String file = String.fromCharCode(
        'a'.codeUnitAt(0) + (isFlipped ? 6 - index : index),
      );
      labels.add(
        _CoordinateAxisLabel(
          key: Key('mill_coordinate_training_file_$index'),
          center: Offset(
            originX + padding + index * cell,
            originY + side - padding * 0.34,
          ),
          label: file,
          style: style,
        ),
      );

      final int rank = isFlipped ? index + 1 : 7 - index;
      labels.add(
        _CoordinateAxisLabel(
          key: Key('mill_coordinate_training_rank_$index'),
          center: Offset(
            originX + padding * 0.34,
            originY + padding + index * cell,
          ),
          label: rank.toString(),
          style: style,
        ),
      );
    }
    return labels;
  }
}

class _CoordinateAxisLabel extends StatelessWidget {
  const _CoordinateAxisLabel({
    super.key,
    required this.center,
    required this.label,
    required this.style,
  });

  final Offset center;
  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: center.dx - 10,
      top: center.dy - 10,
      width: 20,
      height: 20,
      child: Center(child: Text(label, style: style)),
    );
  }
}

class _CoordinateDisplay extends StatefulWidget {
  const _CoordinateDisplay({required this.currentNode, required this.nextNode});

  final int currentNode;
  final int nextNode;

  @override
  State<_CoordinateDisplay> createState() => _CoordinateDisplayState();
}

class _CoordinateDisplayState extends State<_CoordinateDisplay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _kCoordinateTransitionDuration,
  )..value = 1.0;

  late final Animation<double> _currentScale = Tween<double>(
    begin: _kNextCoordinateScale,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.linear));

  late final Animation<Offset> _currentSlide = Tween<Offset>(
    begin: _kNextCoordinateTranslation,
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.linear));

  late final Animation<Offset> _nextSlide = Tween<Offset>(
    begin: const Offset(0.5, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.linear));

  late final Animation<double> _currentOpacity = Tween<double>(
    begin: _kNextCoordinateOpacity,
    end: _kCurrentCoordinateOpacity,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.linear));

  late final Animation<double> _nextOpacity = Tween<double>(
    begin: 0,
    end: _kNextCoordinateOpacity,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final String current = MillBoardCoordinateMaps.nodeToNotation(
      widget.currentNode,
    );
    final String next = MillBoardCoordinateMaps.nodeToNotation(widget.nextNode);
    assert(current.isNotEmpty, 'Coordinate training target needs notation.');
    assert(next.isNotEmpty, 'Coordinate training next target needs notation.');

    final TextStyle currentStyle = TextStyle(
      fontFamily: 'monospace',
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      fontSize: 92,
      fontWeight: FontWeight.w800,
      color: Colors.white.withValues(alpha: 0.9),
      shadows: const <Shadow>[
        Shadow(color: Colors.black54, offset: Offset(0, 5), blurRadius: 28),
      ],
    );

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.0,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          FadeTransition(
            opacity: _currentOpacity,
            child: SlideTransition(
              position: _currentSlide,
              child: ScaleTransition(
                scale: _currentScale,
                child: Semantics(
                  label: strings.coordinateTrainingCurrentTarget(current),
                  child: ExcludeSemantics(
                    child: Text(
                      current,
                      key: const Key(
                        'mill_coordinate_training_current_coordinate',
                      ),
                      style: currentStyle,
                    ),
                  ),
                ),
              ),
            ),
          ),
          FadeTransition(
            opacity: _nextOpacity,
            child: SlideTransition(
              position: _nextSlide,
              child: FractionalTranslation(
                translation: _kNextCoordinateTranslation,
                child: Transform.scale(
                  scale: _kNextCoordinateScale,
                  child: Semantics(
                    label: strings.coordinateTrainingNextTarget(next),
                    child: ExcludeSemantics(
                      child: Text(
                        next,
                        key: const Key(
                          'mill_coordinate_training_next_coordinate',
                        ),
                        style: currentStyle.copyWith(
                          color: Colors.white.withValues(
                            alpha: _kNextCoordinateOpacity,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _CoordinateDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nextNode != widget.nextNode) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _MillCoordinateTrainingPainter extends CustomPainter {
  _MillCoordinateTrainingPainter({
    required this.colorScheme,
    required this.hasDiagonalLines,
    required this.transformMap,
    required this.lastGuessNode,
    required this.lastGuessCorrect,
  });

  final ColorScheme colorScheme;
  final bool hasDiagonalLines;
  final List<int> transformMap;
  final int? lastGuessNode;
  final bool? lastGuessCorrect;

  @override
  void paint(Canvas canvas, Size size) {
    final double side = size.shortestSide;
    final RRect background = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(side * 0.035),
    );
    canvas.drawRRect(
      background,
      Paint()..color = colorScheme.surfaceContainerHigh,
    );

    _drawLines(canvas, size);
    _drawPoints(canvas, size);
    _drawGuessHighlight(canvas, size);
  }

  void _drawLines(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = colorScheme.onSurfaceVariant
      ..strokeWidth = math.max(2, size.shortestSide * 0.007)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final List<List<int>> lines = hasDiagonalLines
        ? MillBoardCoordinateMaps.diagonalMillNodeLines
        : MillBoardCoordinateMaps.standardMillNodeLines;

    for (final List<int> line in lines) {
      final Path path = Path();
      for (int i = 0; i < line.length; i++) {
        final Offset p = _transformedNodeOffset(line[i], size);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  void _drawGuessHighlight(Canvas canvas, Size size) {
    final int? node = lastGuessNode;
    final bool? correct = lastGuessCorrect;
    if (node == null || correct == null) {
      return;
    }

    final Color color = correct ? colorScheme.primary : colorScheme.error;
    final Offset center = _transformedNodeOffset(node, size);
    final double radius = size.shortestSide * 0.062;
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = color.withValues(alpha: 0.32),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color
        ..strokeWidth = math.max(2, size.shortestSide * 0.008)
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawPoints(Canvas canvas, Size size) {
    final double side = size.shortestSide;
    final double radius = side * 0.017;
    final Paint fill = Paint()..color = colorScheme.surface;
    final Paint stroke = Paint()
      ..color = colorScheme.onSurfaceVariant
      ..strokeWidth = math.max(1.2, side * 0.004)
      ..style = PaintingStyle.stroke;

    for (int node = 0; node < MillBoardGeometry.nodeCount; node++) {
      final Offset center = _transformedNodeOffset(node, size);
      canvas.drawCircle(center, radius, fill);
      canvas.drawCircle(center, radius, stroke);
    }
  }

  Offset _transformedNodeOffset(int logicalNode, Size size) {
    assert(
      transformMap.length == MillBoardGeometry.nodeCount,
      'Mill coordinate training needs a complete transform map.',
    );
    assert(
      logicalNode >= 0 && logicalNode < MillBoardGeometry.nodeCount,
      'Mill coordinate training node is out of range.',
    );
    return MillBoardGeometry.nodeOffset(transformMap[logicalNode], size);
  }

  @override
  bool shouldRepaint(covariant _MillCoordinateTrainingPainter oldDelegate) {
    return oldDelegate.colorScheme != colorScheme ||
        oldDelegate.hasDiagonalLines != hasDiagonalLines ||
        !listEquals(oldDelegate.transformMap, transformMap) ||
        oldDelegate.lastGuessNode != lastGuessNode ||
        oldDelegate.lastGuessCorrect != lastGuessCorrect;
  }
}
