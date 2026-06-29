// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/material.dart';

import '../generated/intl/l10n.dart';
import '../shared/themes/app_styles.dart';

enum _ClockSide { top, bottom }

class ClockToolPage extends StatefulWidget {
  const ClockToolPage({super.key});

  @override
  State<ClockToolPage> createState() => _ClockToolPageState();
}

class _ClockToolPageState extends State<ClockToolPage> {
  static const List<_ClockPreset> _presets = <_ClockPreset>[
    _ClockPreset(minutes: 1, incrementSeconds: 0),
    _ClockPreset(minutes: 3, incrementSeconds: 0),
    _ClockPreset(minutes: 5, incrementSeconds: 0),
    _ClockPreset(minutes: 10, incrementSeconds: 0),
  ];

  _ClockPreset _preset = _presets[2];
  late Duration _topTime = _preset.initialTime;
  late Duration _bottomTime = _preset.initialTime;
  _ClockSide _activeSide = _ClockSide.bottom;
  bool _running = false;
  bool _started = false;
  Timer? _timer;
  DateTime? _lastTick;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _selectPreset(_ClockPreset preset) {
    if (preset == _preset) {
      return;
    }
    setState(() {
      _preset = preset;
      _resetState();
    });
  }

  void _reset() {
    setState(_resetState);
  }

  void _close() {
    Navigator.of(context).maybePop();
  }

  void _resetState() {
    _timer?.cancel();
    _timer = null;
    _topTime = _preset.initialTime;
    _bottomTime = _preset.initialTime;
    _activeSide = _ClockSide.bottom;
    _running = false;
    _started = false;
    _lastTick = null;
  }

  void _toggleRunning() {
    setState(() {
      if (_running) {
        _applyElapsed();
        _running = false;
        _timer?.cancel();
        _timer = null;
        _lastTick = null;
      } else if (!_isFlagged(_activeSide)) {
        _started = true;
        _running = true;
        _lastTick = DateTime.now();
        _timer = Timer.periodic(
          const Duration(milliseconds: 100),
          (_) => _tick(),
        );
      }
    });
  }

  void _handleClockTap(_ClockSide side) {
    if (!_started) {
      setState(() {
        _activeSide = side;
      });
      _toggleRunning();
      return;
    }
    if (!_running || side != _activeSide || _isFlagged(side)) {
      return;
    }
    setState(() {
      _applyElapsed();
      _addIncrement(side);
      _activeSide = _opposite(side);
      _lastTick = DateTime.now();
    });
  }

  void _tick() {
    if (!_running) {
      return;
    }
    setState(() {
      _applyElapsed();
      if (_isFlagged(_activeSide)) {
        _running = false;
        _timer?.cancel();
        _timer = null;
        _lastTick = null;
      }
    });
  }

  void _applyElapsed() {
    final DateTime now = DateTime.now();
    final DateTime? lastTick = _lastTick;
    if (lastTick == null) {
      _lastTick = now;
      return;
    }
    final Duration elapsed = now.difference(lastTick);
    assert(!elapsed.isNegative, 'Clock elapsed time must not be negative.');
    _setSideTime(_activeSide, _sideTime(_activeSide) - elapsed);
    _lastTick = now;
  }

  void _addIncrement(_ClockSide side) {
    if (_preset.increment == Duration.zero) {
      return;
    }
    _setSideTime(side, _sideTime(side) + _preset.increment);
  }

  Duration _sideTime(_ClockSide side) =>
      side == _ClockSide.top ? _topTime : _bottomTime;

  void _setSideTime(_ClockSide side, Duration value) {
    final Duration clamped = value.isNegative ? Duration.zero : value;
    if (side == _ClockSide.top) {
      _topTime = clamped;
    } else {
      _bottomTime = clamped;
    }
  }

  bool _isFlagged(_ClockSide side) => _sideTime(side) == Duration.zero;

  _ClockSide _opposite(_ClockSide side) =>
      side == _ClockSide.top ? _ClockSide.bottom : _ClockSide.top;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final bool controlsEnabled =
        !_running ||
        _isFlagged(_ClockSide.top) ||
        _isFlagged(_ClockSide.bottom);

    return Scaffold(
      key: const Key('clock_tool_page_scaffold'),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: _ClockTile(
                key: const Key('clock_tool_top_tile'),
                label: strings.player2,
                time: _topTime,
                active: _running && _activeSide == _ClockSide.top,
                flagged: _isFlagged(_ClockSide.top),
                rotated: true,
                onTap: () => _handleClockTap(_ClockSide.top),
              ),
            ),
            _ClockControls(
              presets: _presets,
              selectedPreset: _preset,
              running: _running,
              started: _started,
              onPresetSelected: _selectPreset,
              onReset: _reset,
              onStartPause: _toggleRunning,
              onClose: _close,
              controlsEnabled: controlsEnabled,
            ),
            Expanded(
              child: _ClockTile(
                key: const Key('clock_tool_bottom_tile'),
                label: strings.player1,
                time: _bottomTime,
                active: _running && _activeSide == _ClockSide.bottom,
                flagged: _isFlagged(_ClockSide.bottom),
                rotated: false,
                onTap: () => _handleClockTap(_ClockSide.bottom),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClockControls extends StatelessWidget {
  const _ClockControls({
    required this.presets,
    required this.selectedPreset,
    required this.running,
    required this.started,
    required this.onPresetSelected,
    required this.onReset,
    required this.onStartPause,
    required this.onClose,
    required this.controlsEnabled,
  });

  final List<_ClockPreset> presets;
  final _ClockPreset selectedPreset;
  final bool running;
  final bool started;
  final ValueChanged<_ClockPreset> onPresetSelected;
  final VoidCallback onReset;
  final VoidCallback onStartPause;
  final VoidCallback onClose;
  final bool controlsEnabled;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_ClockPreset>(
                segments: <ButtonSegment<_ClockPreset>>[
                  for (final _ClockPreset preset in presets)
                    ButtonSegment<_ClockPreset>(
                      value: preset,
                      label: Text(preset.label),
                    ),
                ],
                selected: <_ClockPreset>{selectedPreset},
                onSelectionChanged: running || started
                    ? null
                    : (Set<_ClockPreset> selected) {
                        assert(
                          selected.length == 1,
                          'Clock preset selection must contain one preset.',
                        );
                        onPresetSelected(selected.single);
                      },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IconButton.filledTonal(
                  key: const Key('clock_tool_close_button'),
                  tooltip: strings.close,
                  onPressed: controlsEnabled ? onClose : null,
                  icon: const Icon(Icons.home_rounded),
                ),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                  key: const Key('clock_tool_reset_button'),
                  tooltip: strings.reset,
                  onPressed: controlsEnabled ? onReset : null,
                  icon: const Icon(Icons.restart_alt_rounded),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  key: const Key('clock_tool_start_pause_button'),
                  onPressed: onStartPause,
                  icon: Icon(
                    running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(
                    running
                        ? strings.pause
                        : started
                        ? strings.resume
                        : strings.start,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ClockTile extends StatelessWidget {
  const _ClockTile({
    super.key,
    required this.label,
    required this.time,
    required this.active,
    required this.flagged,
    required this.rotated,
    required this.onTap,
  });

  final String label;
  final Duration time;
  final bool active;
  final bool flagged;
  final bool rotated;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color background = flagged
        ? colorScheme.error
        : active
        ? colorScheme.primary
        : colorScheme.surfaceContainerHighest;
    final Color foreground = active || flagged
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;
    final Widget content = Material(
      color: background,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: AppStyles.sectionTitle.copyWith(color: foreground),
                ),
                const SizedBox(height: 12),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _formatClock(time),
                    style: TextStyle(
                      color: foreground,
                      fontSize: 72,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return RotatedBox(quarterTurns: rotated ? 2 : 0, child: content);
  }
}

class _ClockPreset {
  const _ClockPreset({required this.minutes, required this.incrementSeconds});

  final int minutes;
  final int incrementSeconds;

  Duration get initialTime => Duration(minutes: minutes);
  Duration get increment => Duration(seconds: incrementSeconds);
  String get label => '$minutes+$incrementSeconds';
}

String _formatClock(Duration duration) {
  assert(!duration.isNegative, 'Clock duration must not be negative.');
  final int totalSeconds = duration.inSeconds;
  final int minutes = totalSeconds ~/ 60;
  final int seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
