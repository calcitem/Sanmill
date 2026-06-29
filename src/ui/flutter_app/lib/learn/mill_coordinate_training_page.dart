// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;

import '../games/mill/mill_board_coordinate_maps.dart';
import '../games/mill/mill_board_geometry.dart';
import '../generated/intl/l10n.dart';
import '../rule_settings/models/rule_settings.dart';
import '../shared/database/database.dart';
import '../shared/themes/app_styles.dart';
import '../shared/widgets/lichess_bottom_bar.dart';
import '../shared/widgets/lichess_list_section.dart';

const Duration _kTrainingDuration = Duration(seconds: 30);
const Duration _kTickInterval = Duration(milliseconds: 100);
const Duration _kGuessHighlightDuration = Duration(milliseconds: 220);
const Duration _kCoordinateTransitionDuration = Duration(milliseconds: 150);
const Offset _kNextCoordinateTranslation = Offset(0.72, 0.32);
const double _kNextCoordinateScale = 0.42;
const double _kCurrentCoordinateOpacity = 0.9;
const double _kNextCoordinateOpacity = 0.68;
const List<Duration> _kTrainingDurationChoices = <Duration>[
  Duration(seconds: 30),
  Duration(seconds: 60),
  Duration(seconds: 120),
];

String _formatTrainingDuration(Duration duration) {
  assert(!duration.isNegative, 'Training duration must not be negative.');
  assert(duration.inSeconds > 0, 'Training duration must be positive.');
  if (duration.inSeconds % 60 == 0) {
    return '${duration.inMinutes}min';
  }
  return '${duration.inSeconds}s';
}

class MillCoordinateTrainingPage extends StatefulWidget {
  const MillCoordinateTrainingPage({super.key});

  @override
  State<MillCoordinateTrainingPage> createState() =>
      _MillCoordinateTrainingPageState();
}

class _MillCoordinateTrainingPageState
    extends State<MillCoordinateTrainingPage> {
  final math.Random _random = math.Random();
  final Stopwatch _stopwatch = Stopwatch();

  Timer? _tickTimer;
  Timer? _highlightTimer;

  int? _currentNode;
  int? _nextNode;
  int? _lastGuessNode;
  bool? _lastGuessCorrect;
  int _score = 0;
  int? _lastScore;
  Duration? _elapsed;
  Duration _trainingDuration = _kTrainingDuration;
  bool _showCoordinates = true;

  bool get _trainingActive => _elapsed != null;

  double get _timeFractionElapsed {
    final Duration? elapsed = _elapsed;
    if (elapsed == null) {
      return 0;
    }
    return (elapsed.inMilliseconds / _trainingDuration.inMilliseconds).clamp(
      0,
      1,
    );
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _highlightTimer?.cancel();
    _stopwatch.stop();
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
            icon: const Icon(Icons.settings_outlined),
            onPressed: _showSettingsSheet,
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
                        trainingActive: _trainingActive,
                        score: _score,
                        lastScore: _lastScore,
                        currentNode: _currentNode,
                        nextNode: _nextNode,
                        lastGuessNode: _lastGuessNode,
                        lastGuessCorrect: _lastGuessCorrect,
                        timeFractionElapsed: _timeFractionElapsed,
                        onGuess: _guessNode,
                        onStart: _startTraining,
                        onAbort: _abortTraining,
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
                    label: strings.menu,
                    showLabel: true,
                    onTap: _showSettingsSheet,
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
      _currentNode = currentNode;
      _nextNode = _randomNode(previous: currentNode);
      _lastGuessNode = null;
      _lastGuessCorrect = null;
      _score = 0;
      _elapsed = Duration.zero;
    });

    _tickTimer?.cancel();
    _stopwatch
      ..reset()
      ..start();
    _tickTimer = Timer.periodic(_kTickInterval, (_) {
      if (!mounted) {
        return;
      }
      if (_stopwatch.elapsed >= _trainingDuration) {
        _finishTraining();
        return;
      }
      setState(() {
        _elapsed = _stopwatch.elapsed;
      });
    });
  }

  void _finishTraining() {
    _tickTimer?.cancel();
    _stopwatch.stop();
    setState(() {
      _lastScore = _score;
      _currentNode = null;
      _nextNode = null;
      _elapsed = null;
    });
  }

  void _abortTraining() {
    _tickTimer?.cancel();
    _stopwatch.stop();
    setState(() {
      _currentNode = null;
      _nextNode = null;
      _lastGuessNode = null;
      _lastGuessCorrect = null;
      _elapsed = null;
    });
  }

  int _randomNode({int? previous}) {
    int node = _random.nextInt(MillBoardGeometry.nodeCount);
    while (node == previous) {
      node = _random.nextInt(MillBoardGeometry.nodeCount);
    }
    return node;
  }

  void _guessNode(int node) {
    if (!_trainingActive) {
      return;
    }
    final int? current = _currentNode;
    assert(current != null, 'Active coordinate training needs a target node.');
    final bool correct = node == current;

    setState(() {
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

  void _showSettingsSheet() {
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
              LichessListSection(
                header: Text(strings.duration),
                children: <Widget>[
                  for (final Duration duration in _kTrainingDurationChoices)
                    ListTile(
                      key: Key(
                        'mill_coordinate_training_duration_${duration.inSeconds}',
                      ),
                      title: Text(_formatTrainingDuration(duration)),
                      trailing: duration == _trainingDuration
                          ? Icon(
                              Icons.check_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                      onTap: () {
                        setState(() {
                          _trainingDuration = duration;
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
          content: Text(
            '${strings.coordinateTrainingDescription}\n\n'
            '${strings.duration}: ${_formatTrainingDuration(_trainingDuration)}',
          ),
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
    required this.trainingActive,
    required this.score,
    required this.lastScore,
    required this.currentNode,
    required this.nextNode,
    required this.lastGuessNode,
    required this.lastGuessCorrect,
    required this.timeFractionElapsed,
    required this.onGuess,
    required this.onStart,
    required this.onAbort,
  });

  final bool hasDiagonalLines;
  final bool showCoordinates;
  final bool trainingActive;
  final int score;
  final int? lastScore;
  final int? currentNode;
  final int? nextNode;
  final int? lastGuessNode;
  final bool? lastGuessCorrect;
  final double timeFractionElapsed;
  final ValueChanged<int> onGuess;
  final VoidCallback onStart;
  final VoidCallback onAbort;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool landscape = constraints.maxWidth > constraints.maxHeight;
        final Axis direction = landscape ? Axis.horizontal : Axis.vertical;
        final double boardSize = landscape
            ? math.min(constraints.maxHeight - 24, constraints.maxWidth * 0.62)
            : math.min(constraints.maxWidth, constraints.maxHeight * 0.72);

        final Widget board = SizedBox(
          width: boardSize,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _TimeBar(
                width: boardSize,
                fraction: timeFractionElapsed,
                correct: lastGuessCorrect,
              ),
              SizedBox.square(
                dimension: boardSize,
                child: _MillTrainingBoard(
                  hasDiagonalLines: hasDiagonalLines,
                  showCoordinates: showCoordinates,
                  trainingActive: trainingActive,
                  currentNode: currentNode,
                  nextNode: nextNode,
                  lastGuessNode: lastGuessNode,
                  lastGuessCorrect: lastGuessCorrect,
                  onGuess: onGuess,
                ),
              ),
            ],
          ),
        );

        final Widget panel = _TrainingPanel(
          score: score,
          lastScore: lastScore,
          trainingActive: trainingActive,
          onStart: onStart,
          onAbort: onAbort,
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

class _TimeBar extends StatelessWidget {
  const _TimeBar({
    required this.width,
    required this.fraction,
    required this.correct,
  });

  final double width;
  final double fraction;
  final bool? correct;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color color = correct == false
        ? colorScheme.error
        : colorScheme.primary;

    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: width * fraction,
        height: 12,
        child: ColoredBox(color: color),
      ),
    );
  }
}

class _TrainingPanel extends StatelessWidget {
  const _TrainingPanel({
    required this.score,
    required this.lastScore,
    required this.trainingActive,
    required this.onStart,
    required this.onAbort,
  });

  final int score;
  final int? lastScore;
  final bool trainingActive;
  final VoidCallback onStart;
  final VoidCallback onAbort;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);

    if (trainingActive) {
      return _ScoreAndButton(
        score: score,
        buttonLabel: strings.coordinateTrainingAbort,
        onPressed: onAbort,
      );
    }

    final int? last = lastScore;
    if (last != null) {
      return _ScoreAndButton(
        score: last,
        buttonLabel: strings.coordinateTrainingStart,
        onPressed: onStart,
      );
    }

    return Center(
      child: FilledButton(
        key: const Key('mill_coordinate_training_start_button'),
        onPressed: onStart,
        child: Text(
          strings.coordinateTrainingStart,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _ScoreAndButton extends StatelessWidget {
  const _ScoreAndButton({
    required this.score,
    required this.buttonLabel,
    required this.onPressed,
  });

  final int score;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        Container(
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
        FilledButton(
          key: const Key('mill_coordinate_training_action_button'),
          onPressed: onPressed,
          child: Text(buttonLabel),
        ),
      ],
    );
  }
}

class _MillTrainingBoard extends StatelessWidget {
  const _MillTrainingBoard({
    required this.hasDiagonalLines,
    required this.showCoordinates,
    required this.trainingActive,
    required this.currentNode,
    required this.nextNode,
    required this.lastGuessNode,
    required this.lastGuessCorrect,
    required this.onGuess,
  });

  final bool hasDiagonalLines;
  final bool showCoordinates;
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
                    onGuess(node);
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
                  showCoordinates: showCoordinates,
                  lastGuessNode: lastGuessNode,
                  lastGuessCorrect: lastGuessCorrect,
                ),
              ),
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
                child: Text(
                  current,
                  key: const Key('mill_coordinate_training_current_coordinate'),
                  style: currentStyle,
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
                  child: Text(
                    next,
                    key: const Key('mill_coordinate_training_next_coordinate'),
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
    required this.showCoordinates,
    required this.lastGuessNode,
    required this.lastGuessCorrect,
  });

  final ColorScheme colorScheme;
  final bool hasDiagonalLines;
  final bool showCoordinates;
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
    _drawGuessHighlight(canvas, size);
    _drawPoints(canvas, size);
    if (showCoordinates) {
      _drawCoordinateLabels(canvas, size);
    }
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
        final Offset p = MillBoardGeometry.nodeOffset(line[i], size);
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
    final Offset center = MillBoardGeometry.nodeOffset(node, size);
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
      final Offset center = MillBoardGeometry.nodeOffset(node, size);
      canvas.drawCircle(center, radius, fill);
      canvas.drawCircle(center, radius, stroke);
    }
  }

  void _drawCoordinateLabels(Canvas canvas, Size size) {
    final Offset boardCenter = Offset(size.width / 2, size.height / 2);
    final double side = size.shortestSide;
    final double fontSize = math.max(9, side * 0.032);

    for (int node = 0; node < MillBoardGeometry.nodeCount; node++) {
      final String notation = MillBoardCoordinateMaps.nodeToNotation(node);
      assert(notation.isNotEmpty, 'Mill node $node must have notation.');
      final Offset nodeCenter = MillBoardGeometry.nodeOffset(node, size);
      final Offset labelCenter = _labelCenterFor(
        nodeCenter: nodeCenter,
        boardCenter: boardCenter,
        side: side,
      );
      _drawLabel(canvas, labelCenter, notation, fontSize);
    }
  }

  Offset _labelCenterFor({
    required Offset nodeCenter,
    required Offset boardCenter,
    required double side,
  }) {
    final Offset vector = nodeCenter - boardCenter;
    final double distance = vector.distance;
    assert(distance > 0, 'Mill coordinate label cannot be at board center.');
    final Offset direction = vector / distance;
    return nodeCenter + direction * (side * 0.044);
  }

  void _drawLabel(
    Canvas canvas,
    Offset center,
    String notation,
    double fontSize,
  ) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: notation,
        style: AppStyles.tileSubtitle.copyWith(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final Rect textRect = Rect.fromCenter(
      center: center,
      width: painter.width + 8,
      height: painter.height + 3,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(textRect, const Radius.circular(4)),
      Paint()..color = colorScheme.surface.withValues(alpha: 0.84),
    );
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _MillCoordinateTrainingPainter oldDelegate) {
    return oldDelegate.colorScheme != colorScheme ||
        oldDelegate.hasDiagonalLines != hasDiagonalLines ||
        oldDelegate.showCoordinates != showCoordinates ||
        oldDelegate.lastGuessNode != lastGuessNode ||
        oldDelegate.lastGuessCorrect != lastGuessCorrect;
  }
}
