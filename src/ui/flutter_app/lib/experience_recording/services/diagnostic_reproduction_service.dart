// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../shared/models/diagnostic_bundle.dart';
import '../../shared/services/diagnostic_bundle_codec.dart';
import '../../shared/services/diagnostic_config_snapshot.dart';
import '../../shared/services/diagnostic_game_context.dart';
import '../models/recording_models.dart';
import '../models/user_action_event.dart';
import 'diagnostic_action_trail_service.dart';
import 'recording_service.dart';

class DiagnosticReproductionResult {
  const DiagnosticReproductionResult({
    required this.bundle,
    required this.backupId,
    required this.gameRestored,
    required this.configDifferences,
  });

  final DiagnosticBundleV1 bundle;
  final String backupId;
  final bool gameRestored;
  final Map<String, dynamic> configDifferences;
}

/// Applies validated bundles and maintains the last ten local pre-import states.
class DiagnosticReproductionService {
  factory DiagnosticReproductionService() => _instance;

  DiagnosticReproductionService._();

  static final DiagnosticReproductionService _instance =
      DiagnosticReproductionService._();
  static const int maxBackups = 10;

  Future<DiagnosticReproductionResult> importAndRestore(String text) async {
    final DiagnosticBundleV1 bundle = DiagnosticBundleCodec.decode(text);
    _verifyCheckpointConsistency(bundle);
    final String backupId = await _createBackup();
    final Map<String, dynamic> beforeConfig =
        DiagnosticConfigSnapshot.capture();
    final Map<String, dynamic> beforeGame = DiagnosticGameContext.capture();
    final Map<String, dynamic> configDifferences = _configDifferences(
      beforeConfig,
      bundle.config,
    );
    try {
      DiagnosticConfigSnapshot.apply(bundle.config);
      final bool restored = DiagnosticGameContext.restore(bundle.game);
      if (bundle.game['fen'] != null && !restored) {
        throw const FormatException(
          'The final game position could not be restored.',
        );
      }
      _verifyRestoredGame(bundle.game);
      return DiagnosticReproductionResult(
        bundle: bundle,
        backupId: backupId,
        gameRestored: restored,
        configDifferences: configDifferences,
      );
    } on Object {
      DiagnosticConfigSnapshot.apply(beforeConfig);
      DiagnosticGameContext.restore(beforeGame);
      rethrow;
    }
  }

  Future<bool> restoreBackup(String id) async {
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(id)) {
      throw const FormatException('Invalid diagnostic backup ID.');
    }
    if (kIsWeb) {
      return false;
    }
    final Directory directory = await _backupDirectory();
    final File file = File('${directory.path}/$id.json');
    if (!file.existsSync()) {
      return false;
    }
    final Object? decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['config'] is! Map<String, dynamic> ||
        decoded['game'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid diagnostic backup.');
    }
    DiagnosticConfigSnapshot.apply(decoded['config'] as Map<String, dynamic>);
    return DiagnosticGameContext.restore(
      decoded['game'] as Map<String, dynamic>,
    );
  }

  RecordingSession buildReplaySession(DiagnosticBundleV1 bundle) {
    final ActionTrailCheckpoint? checkpoint = bundle.actionTrail.checkpoint;
    if (checkpoint == null) {
      throw StateError('This bundle has no replay checkpoint.');
    }
    final Map<String, UserActionEventV1> outcomes =
        <String, UserActionEventV1>{};
    for (final UserActionEventV1 event in bundle.actionTrail.events) {
      if (event.phase != UserActionPhase.attempt) {
        outcomes[event.correlationId] = event;
      }
    }
    final List<RecordingEvent> events = <RecordingEvent>[];
    for (final UserActionEventV1 event in bundle.actionTrail.events) {
      if (event.actionId == 'game.board.tap' &&
          event.phase == UserActionPhase.attempt &&
          outcomes[event.correlationId]?.phase != UserActionPhase.success) {
        continue;
      }
      final Map<String, String> expectedState =
          event.actionId == 'game.board.tap' &&
              event.phase == UserActionPhase.attempt
          ? outcomes[event.correlationId]?.stateDigest ??
                const <String, String>{}
          : event.stateDigest;
      final RecordingEvent? converted = _convertEvent(
        event,
        expectedState: expectedState,
      );
      if (converted != null) {
        events.add(converted);
      }
    }
    return RecordingSession(
      id: 'diagnostic-${bundle.bundleId}',
      appVersion: bundle.application['version'] as String,
      deviceInfo: bundle.application['platform'] as String,
      startTime: bundle.createdAtUtc,
      durationMs: events.isEmpty ? 0 : events.last.timestampMs,
      initialSnapshot: <String, dynamic>{
        ...checkpoint.safeConfig,
        'diagnosticGame': checkpoint.game,
        'diagnosticFinalGame': bundle.game,
      },
      events: events,
      gameMode: checkpoint.game['mode'] as String?,
      notes: 'Validated SanmillDiagnosticBundle v1 replay',
    );
  }

  Future<String> _createBackup() async {
    final String id = const Uuid().v4();
    if (kIsWeb) {
      return id;
    }
    final Directory directory = await _backupDirectory();
    final File file = File('${directory.path}/$id.json');
    final File temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(<String, dynamic>{
        'id': id,
        'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
        'config': DiagnosticConfigSnapshot.capture(),
        'game': DiagnosticGameContext.capture(),
      }),
      flush: true,
    );
    await temporary.rename(file.path);
    final List<File> files = await _backupFiles();
    for (final File excess in files.skip(maxBackups)) {
      await excess.delete();
    }
    return id;
  }

  Future<List<File>> _backupFiles() async {
    if (kIsWeb) {
      return <File>[];
    }
    final Directory directory = await _backupDirectory();
    final List<File> files =
        directory
            .listSync()
            .whereType<File>()
            .where((File file) => file.path.endsWith('.json'))
            .toList()
          ..sort(
            (File a, File b) =>
                b.statSync().modified.compareTo(a.statSync().modified),
          );
    return files;
  }

  Future<Directory> _backupDirectory() async {
    final Directory support = await getApplicationSupportDirectory();
    final Directory directory = Directory(
      '${support.path}/diagnostic_import_backups',
    );
    await directory.create(recursive: true);
    return directory;
  }

  static void _verifyCheckpointConsistency(DiagnosticBundleV1 bundle) {
    final ActionTrailCheckpoint? checkpoint = bundle.actionTrail.checkpoint;
    if (checkpoint == null) {
      return;
    }
    DiagnosticConfigSnapshot.validate(checkpoint.safeConfig);
    final Object? checkpointFen = checkpoint.game['fen'];
    final Object? finalFen = bundle.game['fen'];
    if (checkpointFen != null && checkpointFen is! String) {
      throw const FormatException('Checkpoint FEN must be a string.');
    }
    if (finalFen != null && finalFen is! String) {
      throw const FormatException('Final FEN must be a string.');
    }
    for (final UserActionEventV1 event in bundle.actionTrail.events) {
      final String? digestFen = event.stateDigest['fen'];
      if (digestFen != null && digestFen.length > 512) {
        throw const FormatException('Action state FEN exceeds its limit.');
      }
    }
  }

  static void _verifyRestoredGame(Map<String, dynamic> expected) {
    final Map<String, dynamic> actual = DiagnosticGameContext.capture();
    for (final String key in const <String>{'fen', 'zobrist'}) {
      if (expected[key] != null &&
          actual[key]?.toString() != expected[key].toString()) {
        throw FormatException(
          'Restored $key differs: expected ${expected[key]}, got ${actual[key]}',
        );
      }
    }
  }

  static Map<String, dynamic> _configDifferences(
    Map<String, dynamic> before,
    Map<String, dynamic> reported,
  ) {
    final Map<String, dynamic> differences = <String, dynamic>{};
    for (final String category in const <String>[
      'generalSettings',
      'ruleSettings',
      'displaySettings',
      'colorSettings',
    ]) {
      final Map<String, dynamic> oldValues =
          before[category] as Map<String, dynamic>? ?? <String, dynamic>{};
      final Map<String, dynamic> newValues =
          reported[category] as Map<String, dynamic>? ?? <String, dynamic>{};
      final Map<String, dynamic> categoryDifferences = <String, dynamic>{};
      for (final MapEntry<String, dynamic> entry in newValues.entries) {
        if (jsonEncode(oldValues[entry.key]) == jsonEncode(entry.value)) {
          continue;
        }
        categoryDifferences[entry.key] = <String, dynamic>{
          'before': oldValues[entry.key],
          'reported': entry.value,
        };
      }
      if (categoryDifferences.isNotEmpty) {
        differences[category] = categoryDifferences;
      }
    }
    return differences;
  }

  static RecordingEvent? _convertEvent(
    UserActionEventV1 event, {
    required Map<String, String> expectedState,
  }) {
    if (event.actionId == 'game.board.tap') {
      if (event.phase != UserActionPhase.attempt) {
        return null;
      }
    } else if (event.phase != UserActionPhase.success) {
      return null;
    }
    final Map<String, dynamic> data = <String, dynamic>{
      ...event.payload,
      if (expectedState['fen'] case final String fen) 'expectedFen': fen,
      if (expectedState['zobrist'] case final String zobrist)
        'expectedZobrist': zobrist,
      if (expectedState['config'] case final String config)
        'expectedConfig': config,
      if (expectedState['route'] case final String route)
        'expectedRoute': route,
      'diagnosticSequence': event.sequence,
    };
    final RecordingEventType? type = switch (event.actionId) {
      'game.board.tap' => RecordingEventType.boardTap,
      'game.ai.move' => RecordingEventType.aiMove,
      'game.reset' => RecordingEventType.gameReset,
      'game.mode.changed' => RecordingEventType.gameModeChange,
      'game.history.navigate' => RecordingEventType.historyNavigation,
      'game.undo' => RecordingEventType.undoMove,
      'settings.changed' => RecordingEventType.settingsChange,
      'setup.position.action' => RecordingEventType.setupPositionAction,
      _ => null,
    };
    if (type == null ||
        UserActionCatalog.require(event.actionId).replayPolicy !=
            UserActionReplayPolicy.replayable) {
      return null;
    }
    return RecordingEvent(
      timestampMs: event.elapsedMs,
      type: type,
      data: data,
      page: event.routeId,
    );
  }
}

/// Guard consulted by diagnostic replay and other side-effecting features.
class DiagnosticReplayGuard {
  const DiagnosticReplayGuard._();

  static bool _active = false;
  static bool get active => _active;

  static void enter() {
    assert(!_active, 'Diagnostic replay guard is already active.');
    _active = true;
    DiagnosticActionTrailService().recordingPaused = true;
    RecordingService().isSuppressed = true;
  }

  static void exit() {
    _active = false;
    final DiagnosticActionTrailService trail = DiagnosticActionTrailService();
    trail
      ..refreshConfigDigest()
      ..recordingPaused = false;
    RecordingService().isSuppressed = false;
  }

  static void requireAllowed(String operation) {
    if (_active) {
      throw StateError('$operation is blocked during diagnostic replay.');
    }
  }
}
