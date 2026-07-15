// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../games/mill/mill_types.dart';

enum OfflineBoardClockStatus { disabled, paused, running, flagged }

@immutable
class OfflineBoardClockState {
  const OfflineBoardClockState({
    required this.status,
    required this.whiteTime,
    required this.blackTime,
    required this.increment,
    required this.activeSide,
    required this.hasStarted,
    this.flagSide,
  });

  const OfflineBoardClockState.disabled()
    : status = OfflineBoardClockStatus.disabled,
      whiteTime = Duration.zero,
      blackTime = Duration.zero,
      increment = Duration.zero,
      activeSide = PieceColor.white,
      hasStarted = false,
      flagSide = null;

  final OfflineBoardClockStatus status;
  final Duration whiteTime;
  final Duration blackTime;
  final Duration increment;
  final PieceColor activeSide;
  final bool hasStarted;
  final PieceColor? flagSide;

  bool get isEnabled => status != OfflineBoardClockStatus.disabled;
  bool get isRunning => status == OfflineBoardClockStatus.running;
  bool get isPaused => status == OfflineBoardClockStatus.paused;

  Duration timeFor(PieceColor side) {
    assert(
      side == PieceColor.white || side == PieceColor.black,
      'Offline-board clocks only support the two playable sides.',
    );
    return side == PieceColor.white ? whiteTime : blackTime;
  }
}

/// A two-sided Fischer clock for local play on one device.
///
/// The clock starts paused. A player may start it explicitly, or make the
/// first move while it is still paused; in the latter case the opponent's
/// clock starts without granting an increment for the untimed first move.
class OfflineBoardClock {
  factory OfflineBoardClock() => instance;

  OfflineBoardClock._();

  static final OfflineBoardClock instance = OfflineBoardClock._();

  static const Duration _tickInterval = Duration(milliseconds: 100);

  final ValueNotifier<OfflineBoardClockState> stateNotifier =
      ValueNotifier<OfflineBoardClockState>(
        const OfflineBoardClockState.disabled(),
      );

  Timer? _timer;
  Stopwatch? _turnStopwatch;
  Duration _whiteTime = Duration.zero;
  Duration _blackTime = Duration.zero;
  Duration _increment = Duration.zero;
  PieceColor _activeSide = PieceColor.white;
  bool _hasStarted = false;
  OfflineBoardClockStatus _status = OfflineBoardClockStatus.disabled;

  ValueChanged<PieceColor>? onFlag;

  OfflineBoardClockState get state => stateNotifier.value;

  void setup({
    required Duration initialTime,
    required Duration increment,
    PieceColor activeSide = PieceColor.white,
  }) {
    assert(!initialTime.isNegative, 'Initial time cannot be negative.');
    assert(!increment.isNegative, 'Clock increment cannot be negative.');
    assert(
      activeSide == PieceColor.white || activeSide == PieceColor.black,
      'The active clock must belong to a playable side.',
    );
    _cancelTicker();
    final bool isUnlimited =
        initialTime == Duration.zero && increment == Duration.zero;
    // Match Lichess's 0+N and short-time behavior: a finite clock starts with
    // at least one increment so it can actually receive the first move.
    final Duration effectiveInitialTime = isUnlimited
        ? Duration.zero
        : initialTime < increment
        ? increment
        : initialTime;
    _whiteTime = effectiveInitialTime;
    _blackTime = effectiveInitialTime;
    _increment = increment;
    _activeSide = activeSide;
    _hasStarted = false;
    _status = isUnlimited
        ? OfflineBoardClockStatus.disabled
        : OfflineBoardClockStatus.paused;
    _publish();
  }

  void reset() {
    _cancelTicker();
    _whiteTime = Duration.zero;
    _blackTime = Duration.zero;
    _increment = Duration.zero;
    _activeSide = PieceColor.white;
    _hasStarted = false;
    _status = OfflineBoardClockStatus.disabled;
    _publish();
  }

  void pause() {
    if (_status != OfflineBoardClockStatus.running) {
      return;
    }
    _flushElapsedTime();
    if (_status == OfflineBoardClockStatus.flagged) {
      return;
    }
    _cancelTicker();
    _status = OfflineBoardClockStatus.paused;
    _publish();
  }

  void resume() {
    if (_status != OfflineBoardClockStatus.paused) {
      return;
    }
    assert(
      _timeFor(_activeSide) > Duration.zero,
      'An expired offline-board clock cannot resume.',
    );
    _hasStarted = true;
    _status = OfflineBoardClockStatus.running;
    _startTicker();
    _publish();
  }

  /// Completes one full turn and transfers the running clock.
  ///
  /// Capture chains may contain several atomic actions; callers must invoke
  /// this only when the side to move actually changes.
  void completeTurn({
    required PieceColor sideMoved,
    required PieceColor nextSide,
  }) {
    assert(
      sideMoved == PieceColor.white || sideMoved == PieceColor.black,
      'The completed turn must belong to a playable side.',
    );
    assert(
      nextSide == PieceColor.white || nextSide == PieceColor.black,
      'The next clock must belong to a playable side.',
    );
    if (sideMoved == nextSide) {
      return;
    }
    if (_status == OfflineBoardClockStatus.disabled ||
        _status == OfflineBoardClockStatus.flagged) {
      return;
    }
    assert(
      _activeSide == sideMoved,
      'Only the active side can complete an Offline Board turn.',
    );

    final bool wasRunning = _status == OfflineBoardClockStatus.running;
    if (wasRunning) {
      _flushElapsedTime();
      if (_status == OfflineBoardClockStatus.flagged) {
        return;
      }
      _cancelTicker();
      _setTime(sideMoved, _timeFor(sideMoved) + _increment);
    }

    _activeSide = nextSide;
    _hasStarted = true;
    _status = OfflineBoardClockStatus.running;
    _startTicker();

    // An untimed first move, or a move made while paused, never receives an
    // increment. Once the clock is running, completed turns use Fischer
    // increment.
    _publish();
  }

  /// Synchronises the active side after history navigation without adding
  /// time. Elapsed time is charged before switching when the clock is live.
  void syncActiveSide(PieceColor side) {
    assert(
      side == PieceColor.white || side == PieceColor.black,
      'History navigation must select a playable clock.',
    );
    if (_status == OfflineBoardClockStatus.disabled ||
        _status == OfflineBoardClockStatus.flagged ||
        side == _activeSide) {
      return;
    }
    final bool wasRunning = _status == OfflineBoardClockStatus.running;
    if (wasRunning) {
      _flushElapsedTime();
      if (_status == OfflineBoardClockStatus.flagged) {
        return;
      }
      _cancelTicker();
    }
    _activeSide = side;
    if (wasRunning) {
      _startTicker();
    }
    _publish();
  }

  void _startTicker() {
    _turnStopwatch = Stopwatch()..start();
    _timer = Timer.periodic(_tickInterval, (_) => _tick());
  }

  void _tick() {
    _flushElapsedTime(restartSegment: true);
    if (_status != OfflineBoardClockStatus.flagged) {
      _publish();
    }
  }

  void _flushElapsedTime({bool restartSegment = false}) {
    final Stopwatch? stopwatch = _turnStopwatch;
    if (stopwatch == null) {
      return;
    }
    stopwatch.stop();
    final Duration elapsed = stopwatch.elapsed;
    final Duration remaining = _timeFor(_activeSide) - elapsed;
    if (remaining <= Duration.zero) {
      _setTime(_activeSide, Duration.zero);
      _flag(_activeSide);
      return;
    }
    _setTime(_activeSide, remaining);
    if (restartSegment && _status == OfflineBoardClockStatus.running) {
      _turnStopwatch = Stopwatch()..start();
    } else {
      _turnStopwatch = null;
    }
  }

  void _flag(PieceColor side) {
    _cancelTicker();
    _status = OfflineBoardClockStatus.flagged;
    _publish(flagSide: side);
    onFlag?.call(side);
  }

  void _cancelTicker() {
    _timer?.cancel();
    _timer = null;
    _turnStopwatch?.stop();
    _turnStopwatch = null;
  }

  Duration _timeFor(PieceColor side) {
    return side == PieceColor.white ? _whiteTime : _blackTime;
  }

  void _setTime(PieceColor side, Duration value) {
    if (side == PieceColor.white) {
      _whiteTime = value;
    } else {
      _blackTime = value;
    }
  }

  void _publish({PieceColor? flagSide}) {
    stateNotifier.value = OfflineBoardClockState(
      status: _status,
      whiteTime: _whiteTime,
      blackTime: _blackTime,
      increment: _increment,
      activeSide: _activeSide,
      hasStarted: _hasStarted,
      flagSide: flagSide,
    );
  }
}
