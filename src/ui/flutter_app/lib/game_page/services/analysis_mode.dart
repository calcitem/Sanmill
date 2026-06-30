// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// analysis_mode.dart

// ignore_for_file: avoid_classes_with_only_static_members

import 'package:flutter/material.dart';

/// Verdict for a single analysed move.
///
/// The standard win/draw/loss verdicts come from the perfect database;
/// advantage/disadvantage/unknown are produced by the heuristic search
/// fallback.  [valueStr] carries the numeric evaluation (used for sorting
/// and, in dev mode, for on-board labels); [stepCount] is the perfect
/// database distance-to-conversion when available.
@immutable
class AnalysisOutcome {
  const AnalysisOutcome(this.name, {this.valueStr, this.stepCount});

  /// One of `win`, `draw`, `loss`, `advantage`, `disadvantage`, `unknown`.
  final String name;

  /// Numeric evaluation as a string, or null when unavailable.
  final String? valueStr;

  /// Perfect-database step count, or null when unavailable.
  final int? stepCount;

  static const AnalysisOutcome win = AnalysisOutcome('win');
  static const AnalysisOutcome draw = AnalysisOutcome('draw');
  static const AnalysisOutcome loss = AnalysisOutcome('loss');
  static const AnalysisOutcome advantage = AnalysisOutcome('advantage');
  static const AnalysisOutcome disadvantage = AnalysisOutcome('disadvantage');
  static const AnalysisOutcome unknown = AnalysisOutcome('unknown');

  /// Build a copy of [base] carrying a numeric value string.
  static AnalysisOutcome withValue(AnalysisOutcome base, String value) {
    return AnalysisOutcome(base.name, valueStr: value);
  }

  /// Build a copy of [base] carrying a value string and a step count.
  static AnalysisOutcome withValueAndSteps(
    AnalysisOutcome base,
    String value,
    int? steps,
  ) {
    return AnalysisOutcome(base.name, valueStr: value, stepCount: steps);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AnalysisOutcome && other.name == name;
  }

  @override
  int get hashCode => name.hashCode;

  /// Human-readable description including value and step information.
  String get displayString {
    final StringBuffer buffer = StringBuffer(name);
    if (valueStr != null && valueStr!.isNotEmpty) {
      buffer.write(' ($valueStr');
      if (stepCount != null && stepCount! > 0) {
        buffer.write(' in $stepCount steps');
      }
      buffer.write(')');
    } else if (stepCount != null && stepCount! > 0) {
      buffer.write(' (in $stepCount steps)');
    }
    return buffer.toString();
  }
}

/// Analysis verdict for a single candidate move, keyed by its Mill UCI
/// notation token (`a4`, `a1-a4`, `xg7`).
@immutable
class MoveAnalysisResult {
  const MoveAnalysisResult({required this.move, required this.outcome});

  final String move;
  final AnalysisOutcome outcome;
}

/// Kind of board overlay currently rendered by [AnalysisMode].
enum AnalysisOverlayMode {
  /// Full per-move analysis.
  analysis,

  /// Single best-move hint.
  hint,
}

/// Holds the analysis-overlay state for the board.
///
/// The overlay is populated by running the perfect database over every legal
/// move (see `AnalysisService`).  The renderer (`AnalysisRenderer`) reads the
/// results to draw per-move win/draw/loss marks on the board.
class AnalysisMode {
  static bool _isEnabled = false;
  static bool _isAnalyzing = false;
  static AnalysisOverlayMode? _overlayMode;
  static List<MoveAnalysisResult> _analysisResults = <MoveAnalysisResult>[];
  static List<String> _trapMoves = <String>[];

  /// Notifies listeners whenever the enabled / analyzing flags change so the
  /// toolbar button icon and the board overlay can rebuild.
  static final ValueNotifier<bool> stateNotifier = ValueNotifier<bool>(false);

  /// Whether the analysis overlay is currently shown.
  static bool get isEnabled => _isEnabled;

  /// Whether the current overlay is the full analysis view.
  static bool get isFullAnalysis =>
      _isEnabled && _overlayMode == AnalysisOverlayMode.analysis;

  /// Whether the current overlay is a one-move hint.
  static bool get isHint =>
      _isEnabled && _overlayMode == AnalysisOverlayMode.hint;

  /// Whether an analysis pass is currently running.
  static bool get isAnalyzing => _isAnalyzing;

  /// The current per-move analysis results.
  static List<MoveAnalysisResult> get analysisResults => _analysisResults;

  /// Moves flagged as traps (aggressive moves with a worse verdict than the
  /// available alternatives).  Empty unless trap detection is populated.
  static List<String> get trapMoves => _trapMoves;

  /// Whether [move] is flagged as a trap move.
  static bool isTrapMove(String move) => _trapMoves.contains(move);

  /// Enable the overlay with the given [results] (and optional [trapMoves]).
  static void enable(
    List<MoveAnalysisResult> results, {
    List<String> trapMoves = const <String>[],
    AnalysisOverlayMode mode = AnalysisOverlayMode.analysis,
  }) {
    _analysisResults = results;
    _trapMoves = trapMoves;
    _overlayMode = mode;
    _isEnabled = true;
    _isAnalyzing = false;
    _publishState();
  }

  /// Disable the overlay and clear all results.  Idempotent.
  static void disable() {
    if (!_isEnabled &&
        !_isAnalyzing &&
        _analysisResults.isEmpty &&
        _trapMoves.isEmpty) {
      return;
    }
    _analysisResults = <MoveAnalysisResult>[];
    _trapMoves = <String>[];
    _overlayMode = null;
    _isEnabled = false;
    _isAnalyzing = false;
    _publishState();
  }

  /// Mark whether an analysis pass is in progress.
  static void setAnalyzing(bool analyzing) {
    _isAnalyzing = analyzing;
    _publishState();
  }

  static void _publishState() {
    if (stateNotifier.value == _isEnabled) {
      stateNotifier.value = !_isEnabled;
    }
    stateNotifier.value = _isEnabled;
  }

  /// Colorblind-friendly color for an outcome.
  static Color getColorForOutcome(AnalysisOutcome outcome) {
    switch (outcome.name) {
      case 'win':
      case 'advantage':
        return Colors.blue.shade600;
      case 'loss':
      case 'disadvantage':
        return Colors.red.shade600;
      case 'draw':
        return Colors.grey.shade600;
      case 'unknown':
      default:
        return Colors.yellow.shade600;
    }
  }

  /// Overlay opacity for an outcome.
  static double getOpacityForOutcome(AnalysisOutcome outcome) {
    switch (outcome.name) {
      case 'win':
        return 0.8;
      case 'draw':
        return 0.7;
      case 'loss':
        return 0.6;
      case 'advantage':
        return 0.75;
      case 'disadvantage':
        return 0.65;
      case 'unknown':
      default:
        return 0.5;
    }
  }
}
