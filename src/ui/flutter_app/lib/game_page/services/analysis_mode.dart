// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// analysis_mode.dart

// ignore_for_file: avoid_classes_with_only_static_members

import 'package:flutter/material.dart';

import '../services/mill.dart';

/// Mode for displaying analysis results on the board
class AnalysisMode {
  static bool _isEnabled = false;
  static List<MoveAnalysisResult> _analysisResults = <MoveAnalysisResult>[];

  // Add a flag to track when analysis is in progress
  static bool _isAnalyzing = false;

  // Add a ValueNotifier to track analysis mode state changes
  static final ValueNotifier<bool> stateNotifier = ValueNotifier<bool>(false);

  /// Check if analysis mode is enabled
  static bool get isEnabled => _isEnabled;

  /// Check if analysis is currently running
  static bool get isAnalyzing => _isAnalyzing;

  /// Get current analysis results
  static List<MoveAnalysisResult> get analysisResults => _analysisResults;

  /// Enable analysis mode with the given results
  static void enable(List<MoveAnalysisResult> results) {
    _analysisResults = results;
    _isEnabled = true;
    _isAnalyzing = false;
    // Notify listeners when analysis mode is enabled
    stateNotifier.value = true;
  }

  /// Disable analysis mode
  static void disable() {
    _analysisResults = <MoveAnalysisResult>[];
    _isEnabled = false;
    _isAnalyzing = false;
    // Notify listeners when analysis mode is disabled
    stateNotifier.value = false;
  }

  /// Set analyzing state
  static void setAnalyzing(bool analyzing) {
    _isAnalyzing = analyzing;
    stateNotifier.value = _isEnabled;
  }

  /// Toggle analysis mode
  static void toggle(List<MoveAnalysisResult>? results) {
    if (_isEnabled) {
      disable();
    } else if (results != null && results.isNotEmpty) {
      enable(results);
    }
  }

  /// Get color for a specific outcome - Using colorblind friendly palette
  static Color getColorForOutcome(GameOutcome outcome) {
    switch (outcome) {
      case GameOutcome.win:
        return Colors.blue.shade600;
      case GameOutcome.draw:
        return Colors.grey.shade600;
      case GameOutcome.loss:
        return Colors.red.shade600;
      case GameOutcome.advantage:
        return Colors.blue.shade600;
      case GameOutcome.disadvantage:
        return Colors.red.shade600;
      case GameOutcome.unknown:
      default:
        return Colors.yellow.shade600; // Kept yellow for unknown outcomes
    }
  }

  /// Get opacity for a specific outcome
  static double getOpacityForOutcome(GameOutcome outcome) {
    switch (outcome) {
      case GameOutcome.win:
        return 0.8;
      case GameOutcome.draw:
        return 0.7;
      case GameOutcome.loss:
        return 0.6;
      case GameOutcome.advantage:
        return 0.75; // Slightly less than win
      case GameOutcome.disadvantage:
        return 0.65; // Slightly more than loss
      case GameOutcome.unknown:
      default:
        return 0.5;
    }
  }
}
