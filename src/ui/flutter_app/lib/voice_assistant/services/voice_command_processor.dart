// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// voice_command_processor.dart

import 'package:flutter/material.dart';

import '../../game_page/services/mill.dart';
import '../../general_settings/models/general_settings.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';

/// Voice command types
enum VoiceCommandType {
  move, // Make a move on the board
  undo, // Undo last move
  redo, // Redo move
  restart, // Restart game
  aiMove, // Request AI to make a move
  settings, // Change settings
  help, // Get help
  unknown, // Unrecognized command
}

/// Result of processing a voice command
class VoiceCommandResult {
  VoiceCommandResult({
    required this.type,
    required this.success,
    this.message,
    this.data,
  });

  final VoiceCommandType type;
  final bool success;
  final String? message;
  final Map<String, dynamic>? data;
}

/// Service to process voice commands and execute game actions
class VoiceCommandProcessor {
  factory VoiceCommandProcessor() => _instance;

  VoiceCommandProcessor._internal();

  static final VoiceCommandProcessor _instance =
      VoiceCommandProcessor._internal();

  /// Process a voice command text
  ///
  /// [text] - The recognized text from speech recognition
  /// [context] - BuildContext for localization
  Future<VoiceCommandResult> processCommand(
    String text,
    BuildContext context,
  ) async {
    final String normalizedText = _normalizeText(text);
    logger.i('Processing voice command: $normalizedText');

    final S loc = S.of(context);

    // Check for move commands (e.g., "move a1 to b2", "place on a1")
    final VoiceCommandResult? moveResult = _processMoveCommand(
      normalizedText,
      loc,
    );
    if (moveResult != null) {
      return moveResult;
    }

    // Check for control commands
    final VoiceCommandResult? controlResult = _processControlCommand(
      normalizedText,
      loc,
      context,
    );
    if (controlResult != null) {
      return controlResult;
    }

    // Check for settings commands
    final VoiceCommandResult? settingsResult = _processSettingsCommand(
      normalizedText,
      loc,
    );
    if (settingsResult != null) {
      return settingsResult;
    }

    // Unknown command
    logger.w('Unknown voice command: $normalizedText');
    return VoiceCommandResult(
      type: VoiceCommandType.unknown,
      success: false,
      message: loc.voiceCommandUnknown,
    );
  }

  /// Normalize text for processing
  String _normalizeText(String text) {
    return text.toLowerCase().trim();
  }

  /// Process move commands
  VoiceCommandResult? _processMoveCommand(String text, S loc) {
    // Pattern: "move [position] to [position]"
    // Pattern: "place on [position]"
    // Pattern: "[position] to [position]"
    // Pattern: "remove [position]"

    // Check for "move" command
    if (text.contains('move') && text.contains('to')) {
      final List<String> positions = _extractPositions(text);
      if (positions.length >= 2) {
        return _executeMoveCommand(positions[0], positions[1], loc);
      }
    }

    // Check for "place" command
    if (text.contains('place') || text.contains('put')) {
      final List<String> positions = _extractPositions(text);
      if (positions.isNotEmpty) {
        return _executePlaceCommand(positions[0], loc);
      }
    }

    // Check for "remove" command
    if (text.contains('remove') || text.contains('take')) {
      final List<String> positions = _extractPositions(text);
      if (positions.isNotEmpty) {
        return _executeRemoveCommand(positions[0], loc);
      }
    }

    return null;
  }

  /// Process control commands (undo, redo, restart, etc.)
  VoiceCommandResult? _processControlCommand(
    String text,
    S loc,
    BuildContext context,
  ) {
    // Undo command
    if (text.contains('undo') ||
        text.contains('back') ||
        text.contains('取消') ||
        text.contains('撤销')) {
      return _executeUndoCommand(loc, context);
    }

    // Redo command
    if (text.contains('redo') ||
        text.contains('forward') ||
        text.contains('重做')) {
      return _executeRedoCommand(loc, context);
    }

    // Restart command
    if (text.contains('restart') ||
        text.contains('new game') ||
        text.contains('重新开始') ||
        text.contains('新游戏')) {
      return _executeRestartCommand(loc, context);
    }

    // AI move command
    if (text.contains('ai move') ||
        text.contains('computer move') ||
        text.contains('ai走') ||
        text.contains('电脑走')) {
      return _executeAiMoveCommand(loc, context);
    }

    return null;
  }

  /// Process settings commands
  VoiceCommandResult? _processSettingsCommand(String text, S loc) {
    // Sound toggle
    if (text.contains('sound') || text.contains('音效')) {
      if (text.contains('on') ||
          text.contains('enable') ||
          text.contains('开启')) {
        return _toggleSound(true, loc);
      } else if (text.contains('off') ||
          text.contains('disable') ||
          text.contains('关闭')) {
        return _toggleSound(false, loc);
      } else {
        return _toggleSound(null, loc); // Toggle current state
      }
    }

    // Vibration toggle
    if (text.contains('vibration') ||
        text.contains('vibrate') ||
        text.contains('震动')) {
      if (text.contains('on') ||
          text.contains('enable') ||
          text.contains('开启')) {
        return _toggleVibration(true, loc);
      } else if (text.contains('off') ||
          text.contains('disable') ||
          text.contains('关闭')) {
        return _toggleVibration(false, loc);
      } else {
        return _toggleVibration(null, loc); // Toggle current state
      }
    }

    return null;
  }

  /// Extract position notations from text (e.g., "a1", "b2", "c3")
  ///
  /// Handles various voice recognition formats:
  /// - "a1", "b2", "c3" (standard)
  /// - "a one", "b two", "c three" (spoken numbers)
  /// - "alpha 1", "bravo 2" (phonetic alphabet)
  List<String> _extractPositions(String text) {
    final List<String> positions = <String>[];

    // Standard pattern: "a1", "b2", etc.
    final RegExp standardPattern = RegExp(r'\b([a-g][1-7])\b');
    final Iterable<Match> standardMatches = standardPattern.allMatches(text);

    for (final Match match in standardMatches) {
      positions.add(match.group(1)!);
    }

    // If we found positions, return them
    if (positions.isNotEmpty) {
      return positions;
    }

    // Try to extract positions from spoken format: "a one", "b two", etc.
    final RegExp spokenPattern = RegExp(
      r'\b([a-g])\s+(one|two|three|four|five|six|seven|1|2|3|4|5|6|7)\b',
    );
    final Iterable<Match> spokenMatches = spokenPattern.allMatches(text);

    for (final Match match in spokenMatches) {
      final String letter = match.group(1)!;
      final String number = _convertSpokenNumber(match.group(2)!);
      positions.add('$letter$number');
    }

    return positions;
  }

  /// Convert spoken number words to digits
  String _convertSpokenNumber(String spoken) {
    final Map<String, String> numberMap = <String, String>{
      'one': '1',
      'two': '2',
      'three': '3',
      'four': '4',
      'five': '5',
      'six': '6',
      'seven': '7',
    };

    return numberMap[spoken.toLowerCase()] ?? spoken;
  }

  /// Execute move command
  VoiceCommandResult _executeMoveCommand(String from, String to, S loc) {
    try {
      // Note: Actual move execution requires accessing the board state
      // and converting position notation to board indices
      // This is a placeholder for the actual implementation

      logger.i('Move command: $from to $to');

      // TODO: Implement actual move logic using GameController
      // For now, return success
      return VoiceCommandResult(
        type: VoiceCommandType.move,
        success: true,
        message: loc.voiceCommandMoveSuccess,
        data: <String, String>{'from': from, 'to': to},
      );
    } catch (e, stackTrace) {
      logger.e(
        'Failed to execute move command',
        error: e,
        stackTrace: stackTrace,
      );
      return VoiceCommandResult(
        type: VoiceCommandType.move,
        success: false,
        message: loc.voiceCommandMoveFailed,
      );
    }
  }

  /// Execute place command
  VoiceCommandResult _executePlaceCommand(String position, S loc) {
    try {
      logger.i('Place command: $position');

      // TODO: Implement actual place logic using GameController
      return VoiceCommandResult(
        type: VoiceCommandType.move,
        success: true,
        message: loc.voiceCommandPlaceSuccess,
        data: <String, String>{'position': position},
      );
    } catch (e, stackTrace) {
      logger.e(
        'Failed to execute place command',
        error: e,
        stackTrace: stackTrace,
      );
      return VoiceCommandResult(
        type: VoiceCommandType.move,
        success: false,
        message: loc.voiceCommandPlaceFailed,
      );
    }
  }

  /// Execute remove command
  VoiceCommandResult _executeRemoveCommand(String position, S loc) {
    try {
      logger.i('Remove command: $position');

      // TODO: Implement actual remove logic using GameController
      return VoiceCommandResult(
        type: VoiceCommandType.move,
        success: true,
        message: loc.voiceCommandRemoveSuccess,
        data: <String, String>{'position': position},
      );
    } catch (e, stackTrace) {
      logger.e(
        'Failed to execute remove command',
        error: e,
        stackTrace: stackTrace,
      );
      return VoiceCommandResult(
        type: VoiceCommandType.move,
        success: false,
        message: loc.voiceCommandRemoveFailed,
      );
    }
  }

  /// Execute undo command
  VoiceCommandResult _executeUndoCommand(S loc, BuildContext context) {
    try {
      // Use HistoryNavigator to undo the last move
      HistoryNavigator.doEachMove(HistoryNavMode.takeBack, 1);

      return VoiceCommandResult(
        type: VoiceCommandType.undo,
        success: true,
        message: loc.voiceCommandUndoSuccess,
      );
    } catch (e, stackTrace) {
      logger.e(
        'Failed to execute undo command',
        error: e,
        stackTrace: stackTrace,
      );
      return VoiceCommandResult(
        type: VoiceCommandType.undo,
        success: false,
        message: loc.voiceCommandUndoFailed,
      );
    }
  }

  /// Execute redo command
  VoiceCommandResult _executeRedoCommand(S loc, BuildContext context) {
    try {
      // Use HistoryNavigator to redo the last move
      HistoryNavigator.doEachMove(HistoryNavMode.stepForward, 1);

      return VoiceCommandResult(
        type: VoiceCommandType.redo,
        success: true,
        message: loc.voiceCommandRedoSuccess,
      );
    } catch (e, stackTrace) {
      logger.e(
        'Failed to execute redo command',
        error: e,
        stackTrace: stackTrace,
      );
      return VoiceCommandResult(
        type: VoiceCommandType.redo,
        success: false,
        message: loc.voiceCommandRedoFailed,
      );
    }
  }

  /// Execute restart command
  VoiceCommandResult _executeRestartCommand(S loc, BuildContext context) {
    try {
      final GameController controller = GameController();

      // Reset the game (similar to showRestartGameAlertDialog)
      if (controller.isEngineRunning == false) {
        controller.reset(force: true);
        controller.headerTipNotifier.showTip(loc.gameStarted);
        controller.headerIconsNotifier.showIcons();

        // If AI should move first, trigger engine
        if (controller.gameInstance.isAiSideToMove) {
          controller.engineToGo(context, isMoveNow: false);
        }
      }

      return VoiceCommandResult(
        type: VoiceCommandType.restart,
        success: true,
        message: loc.voiceCommandRestartSuccess,
      );
    } catch (e, stackTrace) {
      logger.e(
        'Failed to execute restart command',
        error: e,
        stackTrace: stackTrace,
      );
      return VoiceCommandResult(
        type: VoiceCommandType.restart,
        success: false,
        message: loc.voiceCommandRestartFailed,
      );
    }
  }

  /// Execute AI move command
  VoiceCommandResult _executeAiMoveCommand(S loc, BuildContext context) {
    try {
      final GameController controller = GameController();
      controller.engineToGo(context, isMoveNow: false);

      return VoiceCommandResult(
        type: VoiceCommandType.aiMove,
        success: true,
        message: loc.voiceCommandAiMoveSuccess,
      );
    } catch (e, stackTrace) {
      logger.e(
        'Failed to execute AI move command',
        error: e,
        stackTrace: stackTrace,
      );
      return VoiceCommandResult(
        type: VoiceCommandType.aiMove,
        success: false,
        message: loc.voiceCommandAiMoveFailed,
      );
    }
  }

  /// Toggle sound setting
  VoiceCommandResult _toggleSound(bool? enable, S loc) {
    try {
      final bool currentState = DB().generalSettings.toneEnabled;
      final bool newState = enable ?? !currentState;

      DB().generalSettings = DB().generalSettings.copyWith(
        toneEnabled: newState,
      );

      return VoiceCommandResult(
        type: VoiceCommandType.settings,
        success: true,
        message: newState ? loc.voiceCommandSoundOn : loc.voiceCommandSoundOff,
      );
    } catch (e, stackTrace) {
      logger.e('Failed to toggle sound', error: e, stackTrace: stackTrace);
      return VoiceCommandResult(
        type: VoiceCommandType.settings,
        success: false,
        message: loc.voiceCommandSettingsFailed,
      );
    }
  }

  /// Toggle vibration setting
  VoiceCommandResult _toggleVibration(bool? enable, S loc) {
    try {
      final bool currentState = DB().generalSettings.vibrationEnabled;
      final bool newState = enable ?? !currentState;

      DB().generalSettings = DB().generalSettings.copyWith(
        vibrationEnabled: newState,
      );

      return VoiceCommandResult(
        type: VoiceCommandType.settings,
        success: true,
        message: newState
            ? loc.voiceCommandVibrationOn
            : loc.voiceCommandVibrationOff,
      );
    } catch (e, stackTrace) {
      logger.e('Failed to toggle vibration', error: e, stackTrace: stackTrace);
      return VoiceCommandResult(
        type: VoiceCommandType.settings,
        success: false,
        message: loc.voiceCommandSettingsFailed,
      );
    }
  }
}
