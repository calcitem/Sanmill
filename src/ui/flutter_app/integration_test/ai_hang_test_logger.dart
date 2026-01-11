// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// ai_hang_test_logger.dart

// Logger utility for AI hang detection tests
// Provides detailed logging and state capture capabilities

// ignore_for_file: avoid_print, always_specify_types

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sanmill/game_page/services/mill.dart';

/// Detailed state information captured at the time of a hang
class HangStateSnapshot {
  HangStateSnapshot({
    required this.gameNumber,
    required this.moveNumber,
    required this.fen,
    required this.moveHistory,
    required this.isEngineRunning,
    required this.isEngineInDelay,
    required this.currentSide,
    required this.currentPhase,
    required this.currentAction,
    required this.timestamp,
    this.additionalInfo,
  });

  final int gameNumber;
  final int moveNumber;
  final String? fen;
  final String moveHistory;
  final bool isEngineRunning;
  final bool isEngineInDelay;
  final PieceColor currentSide;
  final Phase currentPhase;
  final Act currentAction;
  final DateTime timestamp;
  final Map<String, dynamic>? additionalInfo;

  @override
  String toString() {
    final StringBuffer buffer = StringBuffer();

    buffer.writeln('=== AI HANG DETECTED ===');
    buffer.writeln('Timestamp: ${timestamp.toIso8601String()}');
    buffer.writeln('Game Number: $gameNumber');
    buffer.writeln('Move Number: $moveNumber');
    buffer.writeln();
    buffer.writeln('=== Position State ===');
    buffer.writeln('FEN: ${fen ?? "null"}');
    buffer.writeln('Current Side: $currentSide');
    buffer.writeln('Current Phase: $currentPhase');
    buffer.writeln('Current Action: $currentAction');
    buffer.writeln();
    buffer.writeln('=== Engine State ===');
    buffer.writeln('Engine Running: $isEngineRunning');
    buffer.writeln('Engine In Delay: $isEngineInDelay');
    buffer.writeln();
    buffer.writeln('=== Move History ===');
    buffer.writeln(moveHistory.isEmpty ? '(empty)' : moveHistory);

    if (additionalInfo != null && additionalInfo!.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('=== Additional Info ===');
      additionalInfo!.forEach((String key, dynamic value) {
        buffer.writeln('$key: $value');
      });
    }

    buffer.writeln();
    buffer.writeln('=== Reproduction Steps ===');
    buffer.writeln('1. Import the move list above');
    buffer.writeln('2. Set up Human vs AI mode');
    buffer.writeln('3. Let AI make the next move');
    buffer.writeln('4. Observe if AI hangs');

    return buffer.toString();
  }

  /// Convert to JSON-serializable map
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'gameNumber': gameNumber,
      'moveNumber': moveNumber,
      'fen': fen,
      'moveHistory': moveHistory,
      'isEngineRunning': isEngineRunning,
      'isEngineInDelay': isEngineInDelay,
      'currentSide': currentSide.toString(),
      'currentPhase': currentPhase.toString(),
      'currentAction': currentAction.toString(),
      'timestamp': timestamp.toIso8601String(),
      'additionalInfo': additionalInfo,
    };
  }
}

/// Logger for AI hang detection tests
class AiHangTestLogger {
  AiHangTestLogger({required this.testName});

  final String testName;
  final List<String> _logs = <String>[];
  final List<HangStateSnapshot> _hangSnapshots = <HangStateSnapshot>[];

  /// Log a message
  void log(String message, {String prefix = 'INFO'}) {
    final String timestamp = DateTime.now().toIso8601String();
    final String logMessage = '[$timestamp] [$prefix] $message';
    _logs.add(logMessage);
    print(logMessage);
  }

  /// Log an error
  void error(String message) {
    log(message, prefix: 'ERROR');
  }

  /// Log a warning
  void warning(String message) {
    log(message, prefix: 'WARN');
  }

  /// Capture current game state when a hang is detected
  HangStateSnapshot captureHangState({
    required int gameNumber,
    required int moveNumber,
    Map<String, dynamic>? additionalInfo,
  }) {
    final GameController controller = GameController();

    final HangStateSnapshot snapshot = HangStateSnapshot(
      gameNumber: gameNumber,
      moveNumber: moveNumber,
      fen: controller.position.fen,
      moveHistory: controller.gameRecorder.moveHistoryText,
      isEngineRunning: controller.isEngineRunning,
      isEngineInDelay: controller.isEngineInDelay,
      currentSide: controller.position.sideToMove,
      currentPhase: controller.position.phase,
      currentAction: controller.position.action,
      timestamp: DateTime.now(),
      additionalInfo: additionalInfo,
    );

    _hangSnapshots.add(snapshot);
    log('Hang state captured: Game $gameNumber, Move $moveNumber');

    return snapshot;
  }

  /// Get all hang snapshots
  List<HangStateSnapshot> get hangSnapshots =>
      List<HangStateSnapshot>.unmodifiable(_hangSnapshots);

  /// Save logs and hang snapshots to file
  Future<File?> saveToFile() async {
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final File file = File('${tempDir.path}/ai_hang_test_$timestamp.log');

      final StringBuffer buffer = StringBuffer();

      buffer.writeln('AI Hang Detection Test Log');
      buffer.writeln('Test Name: $testName');
      buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
      buffer.writeln('=' * 80);
      buffer.writeln();

      // Write summary
      buffer.writeln('SUMMARY');
      buffer.writeln('Total Logs: ${_logs.length}');
      buffer.writeln('Hangs Detected: ${_hangSnapshots.length}');
      buffer.writeln();
      buffer.writeln('=' * 80);
      buffer.writeln();

      // Write hang snapshots
      if (_hangSnapshots.isNotEmpty) {
        buffer.writeln('HANG SNAPSHOTS');
        buffer.writeln();

        for (int i = 0; i < _hangSnapshots.length; i++) {
          buffer.writeln('Snapshot ${i + 1}:');
          buffer.writeln(_hangSnapshots[i].toString());
          buffer.writeln();
          buffer.writeln('-' * 80);
          buffer.writeln();
        }

        buffer.writeln('=' * 80);
        buffer.writeln();
      }

      // Write full logs
      buffer.writeln('FULL LOG');
      buffer.writeln();
      _logs.forEach(buffer.writeln);

      await file.writeAsString(buffer.toString());

      print('[AiHangTestLogger] Log saved to: ${file.path}');
      return file;
    } catch (e) {
      error('Failed to save log file: $e');
      return null;
    }
  }

  /// Print summary
  void printSummary() {
    print('');
    print('=' * 80);
    print('TEST SUMMARY: $testName');
    print('=' * 80);
    print('Total Logs: ${_logs.length}');
    print('Hangs Detected: ${_hangSnapshots.length}');

    if (_hangSnapshots.isNotEmpty) {
      print('');
      print('HANG DETAILS:');
      for (int i = 0; i < _hangSnapshots.length; i++) {
        final HangStateSnapshot snapshot = _hangSnapshots[i];
        print(
          '  ${i + 1}. Game ${snapshot.gameNumber}, Move ${snapshot.moveNumber} - ${snapshot.timestamp}',
        );
      }
    }

    print('=' * 80);
  }
}
