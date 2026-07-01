// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// analysis_mode.dart

import 'package:flutter/material.dart';

import '../../appearance_settings/models/display_settings.dart';
import '../../shared/database/database.dart';

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
  const MoveAnalysisResult({
    required this.move,
    required this.outcome,
    this.rank,
    this.depth,
    this.nodes,
    this.line = const <String>[],
  });

  final String move;
  final AnalysisOutcome outcome;

  /// 1-based engine line rank when the result comes from MultiPV.
  final int? rank;

  /// Search depth used for this engine line, when available.
  final int? depth;

  /// Searched node count for this engine line, when available.
  final int? nodes;

  /// Principal variation move tokens. Perfect-database entries usually carry
  /// only the root move; engine entries may carry a deeper PV.
  final List<String> line;

  List<String> get displayLine => line.isEmpty ? <String>[move] : line;
}

/// Kind of board overlay currently rendered by [AnalysisMode].
enum AnalysisOverlayMode {
  /// Full per-move analysis.
  analysis,

  /// Single best-move hint.
  hint,
}

/// Source that produced the current analysis overlay.
enum AnalysisSource {
  /// Endgame-perfect database verdicts.
  perfectDatabase,

  /// Local engine search output.
  engine,

  /// Perfect database board verdicts with local engine candidate lines.
  perfectDatabaseAndEngine,
}

/// Holds the analysis-overlay state for the board.
///
/// The overlay is populated by running the perfect database over every legal
/// move (see `AnalysisService`).  The renderer (`AnalysisRenderer`) reads the
/// results to draw per-move win/draw/loss marks on the board.
class AnalysisMode {
  static const int defaultEngineLineCount =
      DisplaySettings.defaultAnalysisEngineLineCount;
  static const int maxEngineLineCount = 3;
  static const List<int> engineSearchTimeOptionsMs = <int>[
    2000,
    4000,
    6000,
    8000,
    10000,
    12000,
    15000,
    20000,
    30000,
    maxEngineSearchTimeMs,
  ];
  static const int defaultEngineSearchTimeMs =
      DisplaySettings.defaultAnalysisEngineSearchTimeMs;
  static const int maxEngineSearchTimeMs = 60 * 60 * 1000;

  static bool _isEnabled = false;
  static bool _isAnalyzing = false;
  static bool _showEngineLines = true;
  static bool _smallBoard = false;
  static bool _isThreatMode = false;
  static int _engineLineCount = defaultEngineLineCount;
  static int _engineSearchTimeMs = defaultEngineSearchTimeMs;
  static AnalysisOverlayMode? _overlayMode;
  static AnalysisSource? _source;
  static List<MoveAnalysisResult> _analysisResults = <MoveAnalysisResult>[];
  static List<MoveAnalysisResult> _analysisLineResults = <MoveAnalysisResult>[];
  static List<MoveAnalysisResult> _normalEngineAnalysisResults =
      <MoveAnalysisResult>[];
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

  /// The source that produced the current overlay, or null when disabled.
  static AnalysisSource? get source => _source;

  /// Whether an analysis pass is currently running.
  static bool get isAnalyzing => _isAnalyzing;

  /// Whether the analysis screen shows the engine move lines.
  static bool get showEngineLines => _showEngineLines;

  /// Whether the analysis screen uses a reduced board size in portrait mode.
  static bool get smallBoard => _smallBoard;

  /// Whether the current engine analysis is showing the opponent's threat.
  static bool get isThreatMode => _isThreatMode;

  /// Number of engine candidate lines to show in analysis mode.
  static int get engineLineCount => _engineLineCount;

  /// Search time budget for normal analysis engine passes.
  static int get engineSearchTimeMs => _engineSearchTimeMs;

  /// Index of the current search-time option for the analysis settings slider.
  static int get engineSearchTimeOptionIndex =>
      engineSearchTimeOptionsMs.indexOf(_engineSearchTimeMs);

  /// The current full per-move analysis results used by the board overlay.
  static List<MoveAnalysisResult> get analysisResults => _analysisResults;

  /// Candidate lines used by the analysis line panel and summary.
  static List<MoveAnalysisResult> get analysisLineResults =>
      _analysisLineResults;

  /// The most recent non-threat engine results for the same analysis session.
  static List<MoveAnalysisResult> get normalEngineAnalysisResults =>
      _normalEngineAnalysisResults;

  /// Whether the current analysis includes local engine candidate lines.
  static bool get hasEngineLinesSource =>
      _source == AnalysisSource.engine ||
      _source == AnalysisSource.perfectDatabaseAndEngine;

  /// Moves flagged as traps (aggressive moves with a worse verdict than the
  /// available alternatives).  Empty unless trap detection is populated.
  static List<String> get trapMoves => _trapMoves;

  /// Whether [move] is flagged as a trap move.
  static bool isTrapMove(String move) => _trapMoves.contains(move);

  /// Enable the overlay with the given [results] (and optional [trapMoves]).
  static void enable(
    List<MoveAnalysisResult> results, {
    List<MoveAnalysisResult>? lineResults,
    List<String> trapMoves = const <String>[],
    AnalysisOverlayMode mode = AnalysisOverlayMode.analysis,
    AnalysisSource source = AnalysisSource.perfectDatabase,
    bool isThreatMode = false,
    bool isAnalyzing = false,
  }) {
    _analysisResults = results;
    _analysisLineResults = lineResults ?? results;
    if (!isThreatMode) {
      final bool sourceHasEngineLines =
          source == AnalysisSource.engine ||
          source == AnalysisSource.perfectDatabaseAndEngine;
      _normalEngineAnalysisResults =
          sourceHasEngineLines && mode == AnalysisOverlayMode.analysis
          ? _analysisLineResults
          : <MoveAnalysisResult>[];
    }
    _trapMoves = trapMoves;
    _overlayMode = mode;
    _source = source;
    _isThreatMode = isThreatMode;
    _isEnabled = true;
    _isAnalyzing = isAnalyzing;
    _publishState();
  }

  /// Disable the overlay and clear all results.  Idempotent.
  static void disable() {
    if (!_isEnabled &&
        !_isAnalyzing &&
        !_isThreatMode &&
        _analysisResults.isEmpty &&
        _analysisLineResults.isEmpty &&
        _trapMoves.isEmpty) {
      return;
    }
    _analysisResults = <MoveAnalysisResult>[];
    _analysisLineResults = <MoveAnalysisResult>[];
    _normalEngineAnalysisResults = <MoveAnalysisResult>[];
    _trapMoves = <String>[];
    _overlayMode = null;
    _source = null;
    _isThreatMode = false;
    _isEnabled = false;
    _isAnalyzing = false;
    _publishState();
  }

  /// Mark whether an analysis pass is in progress.
  static void setAnalyzing(bool analyzing) {
    if (_isAnalyzing == analyzing) {
      return;
    }
    _isAnalyzing = analyzing;
    _publishState();
  }

  /// Toggle visibility of the engine line panel.
  static void toggleEngineLines({bool persist = false}) {
    setShowEngineLines(!_showEngineLines, persist: persist);
  }

  /// Set visibility of the engine line panel.
  static void setShowEngineLines(bool value, {bool persist = false}) {
    if (_showEngineLines == value) {
      if (persist) {
        _saveDisplayPreferences(showEngineLines: value);
      }
      return;
    }
    _showEngineLines = value;
    if (persist) {
      _saveDisplayPreferences(showEngineLines: value);
    }
    _publishState();
  }

  /// Toggle the reduced portrait analysis board layout.
  static void toggleSmallBoard({bool persist = false}) {
    setSmallBoard(!_smallBoard, persist: persist);
  }

  /// Set whether the analysis screen uses a reduced board in portrait mode.
  static void setSmallBoard(bool value, {bool persist = false}) {
    if (_smallBoard == value) {
      if (persist) {
        _saveDisplayPreferences(smallBoard: value);
      }
      return;
    }
    _smallBoard = value;
    if (persist) {
      _saveDisplayPreferences(smallBoard: value);
    }
    _publishState();
  }

  /// Set the number of visible engine candidate lines in analysis mode.
  static void setEngineLineCount(int value, {bool persist = false}) {
    final int next = value.clamp(0, maxEngineLineCount);
    if (_engineLineCount == next) {
      if (persist) {
        _saveDisplayPreferences(engineLineCount: next);
      }
      return;
    }
    _engineLineCount = next;
    if (persist) {
      _saveDisplayPreferences(engineLineCount: next);
    }
    _publishState();
  }

  /// Set the search time budget used by normal analysis engine passes.
  static void setEngineSearchTimeMs(int value, {bool persist = false}) {
    final int next = _normalizeEngineSearchTimeMs(value);
    if (_engineSearchTimeMs == next) {
      if (persist) {
        _saveDisplayPreferences(engineSearchTimeMs: next);
      }
      return;
    }
    _engineSearchTimeMs = next;
    if (persist) {
      _saveDisplayPreferences(engineSearchTimeMs: next);
    }
    _publishState();
  }

  /// Search time option at [index].
  static int engineSearchTimeOptionAt(int index) {
    assert(
      index >= 0 && index < engineSearchTimeOptionsMs.length,
      'Analysis engine search time option index is out of range.',
    );
    return engineSearchTimeOptionsMs[index];
  }

  /// Load persisted analysis display preferences.
  static void configurePreferences({
    required bool smallBoard,
    required bool showEngineLines,
    required int engineLineCount,
    required int engineSearchTimeMs,
    bool notify = true,
  }) {
    final int nextLineCount = engineLineCount.clamp(0, maxEngineLineCount);
    final int nextSearchTimeMs = _normalizeEngineSearchTimeMs(
      engineSearchTimeMs,
    );
    if (_smallBoard == smallBoard &&
        _showEngineLines == showEngineLines &&
        _engineLineCount == nextLineCount &&
        _engineSearchTimeMs == nextSearchTimeMs) {
      return;
    }
    _smallBoard = smallBoard;
    _showEngineLines = showEngineLines;
    _engineLineCount = nextLineCount;
    _engineSearchTimeMs = nextSearchTimeMs;
    if (notify) {
      _publishState();
    }
  }

  /// Notify analysis widgets after external display preferences changed.
  static void refresh() {
    _publishState();
  }

  static void _publishState() {
    if (stateNotifier.value == _isEnabled) {
      stateNotifier.value = !_isEnabled;
    }
    stateNotifier.value = _isEnabled;
  }

  static void _saveDisplayPreferences({
    bool? smallBoard,
    bool? showEngineLines,
    int? engineLineCount,
    int? engineSearchTimeMs,
  }) {
    final DisplaySettings settings = DB().displaySettings;
    DB().displaySettings = settings.copyWithAnalysisPreferences(
      analysisSmallBoard: smallBoard ?? settings.analysisSmallBoard,
      analysisShowEngineLines:
          showEngineLines ?? settings.analysisShowEngineLines,
      analysisEngineLineCount:
          engineLineCount ?? settings.analysisEngineLineCount,
      analysisEngineSearchTimeMs:
          engineSearchTimeMs ?? settings.analysisEngineSearchTimeMs,
    );
  }

  static int _normalizeEngineSearchTimeMs(int value) {
    assert(
      engineSearchTimeOptionsMs.contains(value),
      'Analysis engine search time must be one of the supported options.',
    );
    if (engineSearchTimeOptionsMs.contains(value)) {
      return value;
    }
    return defaultEngineSearchTimeMs;
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
