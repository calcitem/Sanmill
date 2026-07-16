// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../shared/database/database.dart';
import '../../shared/services/diagnostic_config_snapshot.dart';
import '../../shared/services/diagnostic_game_context.dart';
import '../../shared/services/diagnostic_sanitizer.dart';
import '../../shared/services/logger.dart';
import '../models/recording_models.dart';
import '../models/user_action_event.dart';
import 'diagnostic_route_tracker.dart';

/// Always-local semantic operation trail used to diagnose crashes and feedback.
class DiagnosticActionTrailService with WidgetsBindingObserver {
  factory DiagnosticActionTrailService() => _instance;

  DiagnosticActionTrailService._();

  static final DiagnosticActionTrailService _instance =
      DiagnosticActionTrailService._();

  static const int maxEvents = 500;
  static const int maxEncodedBytes = 192 * 1024;
  static const Duration maxAge = Duration(minutes: 30);
  static const Duration cacheTtl = Duration(hours: 24);
  static const Duration flushInterval = Duration(seconds: 10);
  static const int flushEventInterval = 20;
  static const int checkpointEventInterval = 100;
  static const Duration checkpointInterval = Duration(minutes: 5);
  static const String _cacheFilename =
      'sanmill_diagnostic_action_trail_v1.json';

  final ListQueue<UserActionEventV1> _events = ListQueue<UserActionEventV1>();
  final ListQueue<ActionTrailCheckpoint> _checkpoints =
      ListQueue<ActionTrailCheckpoint>();
  final StreamController<UserActionEventV1> _eventController =
      StreamController<UserActionEventV1>.broadcast(sync: true);
  final Stopwatch _stopwatch = Stopwatch();

  String _runId = const Uuid().v4();
  int _nextSequence = 1;
  int _encodedEventBytes = 0;
  int _truncatedEventCount = 0;
  int _eventsSinceFlush = 0;
  int _stateChangesSinceCheckpoint = 0;
  int _lastCheckpointElapsedMs = 0;
  bool _initialized = false;
  bool _enabled = true;
  bool _dirty = false;
  bool recordingPaused = false;
  bool _cacheAvailable = true;
  bool _flushInProgress = false;
  int _mutationGeneration = 0;
  Timer? _flushTimer;
  DiagnosticActionTrailSnapshot? _recoveredSnapshot;
  String _cachedConfigDigest = '';

  bool get enabled => _enabled;
  int get eventCount => _events.length;
  int get retainedBytes => _encodedEventBytes;
  Stream<UserActionEventV1> get events => _eventController.stream;
  DiagnosticActionTrailSnapshot? get recoveredSnapshot => _recoveredSnapshot;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _enabled = DB().generalSettings.diagnosticActionTrailEnabled;
    _runId = const Uuid().v4();
    _stopwatch
      ..reset()
      ..start();
    WidgetsBinding.instance.addObserver(this);
    if (_enabled) {
      await _loadRecoveredCache();
      _captureCheckpoint();
      _scheduleFlush();
    } else {
      await _deleteCache();
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    _mutationGeneration++;
    if (!value) {
      _flushTimer?.cancel();
      _flushTimer = null;
      _events.clear();
      _checkpoints.clear();
      _recoveredSnapshot = null;
      _encodedEventBytes = 0;
      _truncatedEventCount = 0;
      _dirty = false;
      await _deleteCache();
      return;
    }
    _captureCheckpoint();
    _scheduleFlush();
  }

  /// Records an action already expressed through the reviewed schema.
  UserActionEventV1? record({
    required String actionId,
    required UserActionPhase phase,
    required Map<String, dynamic> payload,
    String? correlationId,
    String? routeId,
  }) {
    if (!_initialized || !_enabled || recordingPaused) {
      return null;
    }
    final UserActionDefinition definition = UserActionCatalog.require(actionId);
    if (!definition.allowedInReports) {
      return null;
    }
    final Map<String, Object?> safePayload = definition.sanitizeInternal(
      payload,
    );
    Object? validationError;
    try {
      definition.validateSemantics(phase, safePayload);
    } on Object catch (error) {
      validationError = error;
    }
    assert(
      validationError == null,
      'Invalid internal diagnostic event $actionId: $validationError',
    );
    if (validationError != null) {
      logger.w(
        '[DiagnosticActionTrail] Dropping invalid $actionId event: '
        '$validationError',
      );
      return null;
    }
    return _append(
      actionId: actionId,
      phase: phase,
      payload: safePayload,
      correlationId: correlationId ?? const Uuid().v4(),
      routeId: routeId ?? DiagnosticRouteTracker.currentRouteId,
    );
  }

  /// Compatibility boundary for existing Experience Recording hooks.
  ///
  /// The dynamic map never reaches storage. It is reduced to registered scalar
  /// fields first, and raw imported content is represented only by a length
  /// bucket and source type.
  UserActionEventV1? recordLegacy(
    RecordingEventType type,
    Map<String, dynamic> payload, {
    UserActionPhase phase = UserActionPhase.success,
    String? correlationId,
  }) {
    if (!_initialized || !_enabled || recordingPaused) {
      return null;
    }
    final String actionId = legacyActionId(type);
    final Map<String, Object?> registeredOnly = reviewLegacyPayload(
      type,
      payload,
    );
    return record(
      actionId: actionId,
      phase: phase,
      correlationId: correlationId,
      payload: registeredOnly,
    );
  }

  /// Applies the same fixed action schema used by the short diagnostic trail
  /// to a legacy Experience Recording hook.
  Map<String, Object?> reviewLegacyPayload(
    RecordingEventType type,
    Map<String, dynamic> payload,
  ) {
    final String actionId = legacyActionId(type);
    final UserActionDefinition definition = UserActionCatalog.require(actionId);
    final Map<String, dynamic> sanitized =
        DiagnosticSanitizer.sanitizeLegacyPayload(payload);
    if (type == RecordingEventType.gameImport ||
        type == RecordingEventType.gameLoad) {
      sanitized['source'] = type == RecordingEventType.gameImport
          ? 'clipboard'
          : 'file';
      sanitized['format'] = 'moveText';
    }
    if (type == RecordingEventType.settingsChange) {
      sanitized.putIfAbsent('settingId', () => 'snapshotChanged');
      for (final String valueKey in const <String>{'oldValue', 'newValue'}) {
        if (payload.containsKey(valueKey) && payload[valueKey] == null) {
          sanitized[valueKey] = null;
        }
      }
    }
    final Map<String, dynamic> registeredOnly = <String, dynamic>{
      for (final MapEntry<String, dynamic> entry in sanitized.entries)
        if (definition.fields.containsKey(entry.key)) entry.key: entry.value,
    };
    return definition.sanitizeInternal(registeredOnly);
  }

  DiagnosticActionTrailSnapshot freeze() {
    _evictExpired();
    final ActionTrailCheckpoint? checkpoint = _selectCheckpoint();
    final int checkpointSequence = checkpoint?.sequence ?? -1;
    final List<UserActionEventV1> events = _events
        .where((UserActionEventV1 event) => event.sequence > checkpointSequence)
        .toList(growable: false);
    return DiagnosticActionTrailSnapshot(
      checkpoint: checkpoint,
      events: List<UserActionEventV1>.unmodifiable(events),
      truncatedEventCount: _truncatedEventCount,
      recordedAtUtc: DateTime.now().toUtc(),
    );
  }

  void refreshConfigDigest() {
    try {
      _cachedConfigDigest = _configDigest();
    } on Object {
      // The guard is also exercised by isolated tests and very-early error
      // paths where the settings database may not have opened yet.
      _cachedConfigDigest = '';
    }
  }

  Future<void> clear() async {
    _mutationGeneration++;
    _events.clear();
    _checkpoints.clear();
    _recoveredSnapshot = null;
    _encodedEventBytes = 0;
    _truncatedEventCount = 0;
    _eventsSinceFlush = 0;
    _stateChangesSinceCheckpoint = 0;
    _dirty = false;
    if (_enabled) {
      _captureCheckpoint();
    }
    await _deleteCache();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    record(
      actionId: 'app.lifecycle',
      phase: UserActionPhase.success,
      payload: <String, dynamic>{'state': state.name},
    );
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(flush());
    }
  }

  Future<void> flush() async {
    if (!_enabled ||
        !_dirty ||
        kIsWeb ||
        !_cacheAvailable ||
        _flushInProgress) {
      return;
    }
    _flushInProgress = true;
    _eventsSinceFlush = 0;
    try {
      final File file = await _cacheFile();
      final File temporary = File('${file.path}.tmp');
      final String encoded = jsonEncode(freeze().toJson());
      final int generation = _mutationGeneration;
      await temporary.writeAsString(encoded, flush: true);
      if (!_enabled) {
        if (temporary.existsSync()) {
          await temporary.delete();
        }
        await _deleteCache();
        return;
      }
      await _replaceCacheFile(temporary, file);
      if (!_enabled) {
        await _deleteCache();
        return;
      }
      _dirty = _mutationGeneration != generation;
    } on Object catch (error) {
      if (error is MissingPluginException) {
        _cacheAvailable = false;
      }
      logger.w('[DiagnosticActionTrail] Cache flush failed: $error');
    } finally {
      _flushInProgress = false;
      if (_dirty) {
        _scheduleFlush();
      }
    }
  }

  UserActionEventV1 _append({
    required String actionId,
    required UserActionPhase phase,
    required Map<String, Object?> payload,
    required String correlationId,
    required String routeId,
  }) {
    final int elapsedMs = _stopwatch.elapsedMilliseconds;
    if (actionId == 'settings.changed') {
      _cachedConfigDigest = _configDigest();
    }
    final UserActionEventV1 event = UserActionEventV1(
      sequence: _nextSequence++,
      elapsedMs: elapsedMs,
      runId: _runId,
      routeId: _stableRouteId(routeId),
      actionId: actionId,
      phase: phase,
      correlationId: correlationId,
      payload: Map<String, Object?>.unmodifiable(payload),
      stateDigest: _captureStateDigest(),
    );
    _events.addLast(event);
    _mutationGeneration++;
    _encodedEventBytes += event.encodedBytes;
    _eventsSinceFlush++;
    _dirty = true;
    if (phase == UserActionPhase.success && _isStateChanging(actionId)) {
      _stateChangesSinceCheckpoint++;
    }
    _evictExpired();
    _enforceCapacity();
    _maybeCheckpoint(elapsedMs);
    _eventController.add(event);
    if (_eventsSinceFlush >= flushEventInterval) {
      unawaited(flush());
    } else {
      _scheduleFlush();
    }
    return event;
  }

  Map<String, String> _captureStateDigest() {
    final Map<String, dynamic> game = DiagnosticGameContext.capture();
    final Map<String, String> digest = <String, String>{
      'route': _stableRouteId(DiagnosticRouteTracker.currentRouteId),
      'config': _cachedConfigDigest.isEmpty
          ? (_cachedConfigDigest = _configDigest())
          : _cachedConfigDigest,
    };
    final Object? fen = game['fen'];
    final Object? zobrist = game['zobrist'];
    if (fen is String && fen.length <= 256) {
      digest['fen'] = fen;
    }
    if (zobrist != null) {
      digest['zobrist'] = zobrist.toString();
    }
    return digest;
  }

  void _maybeCheckpoint(int elapsedMs) {
    if (_stateChangesSinceCheckpoint >= checkpointEventInterval ||
        elapsedMs - _lastCheckpointElapsedMs >=
            checkpointInterval.inMilliseconds) {
      _captureCheckpoint();
    }
  }

  void _captureCheckpoint() {
    if (!_enabled) {
      return;
    }
    final ActionTrailCheckpoint checkpoint = ActionTrailCheckpoint(
      sequence: _nextSequence - 1,
      elapsedMs: _stopwatch.elapsedMilliseconds,
      safeConfig: DiagnosticConfigSnapshot.capture(),
      routeStack: DiagnosticRouteTracker.routeStack,
      game: DiagnosticGameContext.capture(),
    );
    _checkpoints.addLast(checkpoint);
    _mutationGeneration++;
    while (_checkpoints.length > 10) {
      _checkpoints.removeFirst();
    }
    _stateChangesSinceCheckpoint = 0;
    _lastCheckpointElapsedMs = checkpoint.elapsedMs;
    _dirty = true;
  }

  ActionTrailCheckpoint? _selectCheckpoint() {
    if (_checkpoints.isEmpty) {
      return null;
    }
    final int firstEventSequence = _events.isEmpty
        ? _nextSequence
        : _events.first.sequence;
    ActionTrailCheckpoint? selected;
    for (final ActionTrailCheckpoint checkpoint in _checkpoints) {
      if (checkpoint.sequence <= firstEventSequence) {
        selected = checkpoint;
      }
    }
    return selected ?? _checkpoints.first;
  }

  void _evictExpired() {
    final int oldestAllowed =
        _stopwatch.elapsedMilliseconds - maxAge.inMilliseconds;
    while (_events.isNotEmpty && _events.first.elapsedMs < oldestAllowed) {
      _dropOldestEvent();
    }
  }

  void _enforceCapacity() {
    while (_events.length > maxEvents ||
        _encodedEventBytes + _checkpointBytes() > maxEncodedBytes) {
      if (_events.isEmpty) {
        break;
      }
      _dropOldestEvent();
    }
  }

  void _dropOldestEvent() {
    final UserActionEventV1 removed = _events.removeFirst();
    _mutationGeneration++;
    _dirty = true;
    _encodedEventBytes -= removed.encodedBytes;
    _truncatedEventCount++;
    while (_checkpoints.length > 1 &&
        (_events.isEmpty ||
            _checkpoints.elementAt(1).sequence <= _events.first.sequence)) {
      _checkpoints.removeFirst();
    }
  }

  int _checkpointBytes() {
    final ActionTrailCheckpoint? checkpoint = _selectCheckpoint();
    return checkpoint == null
        ? 0
        : utf8.encode(jsonEncode(checkpoint.toJson())).length;
  }

  Future<void> _loadRecoveredCache() async {
    if (kIsWeb || !_cacheAvailable) {
      return;
    }
    try {
      final File file = await _cacheFile();
      if (!file.existsSync()) {
        return;
      }
      final FileStat stat = file.statSync();
      if (DateTime.now().difference(stat.modified) > cacheTtl) {
        await file.delete();
        return;
      }
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Action cache root must be an object.');
      }
      _recoveredSnapshot = DiagnosticActionTrailSnapshot.fromJson(decoded);
    } on Object catch (error) {
      if (error is MissingPluginException) {
        _cacheAvailable = false;
      }
      logger.w('[DiagnosticActionTrail] Ignoring invalid cache: $error');
      await _deleteCache();
    }
  }

  Future<File> _cacheFile() async {
    final Directory directory = await getApplicationCacheDirectory();
    await directory.create(recursive: true);
    return File('${directory.path}/$_cacheFilename');
  }

  Future<void> _replaceCacheFile(File temporary, File target) async {
    try {
      await temporary.rename(target.path);
    } on FileSystemException {
      // POSIX rename replaces atomically. Windows may reject replacement of
      // an existing file, so retain a best-effort fallback there.
      if (target.existsSync()) {
        await target.delete();
      }
      await temporary.rename(target.path);
    }
  }

  Future<void> _deleteCache() async {
    if (kIsWeb || !_cacheAvailable) {
      return;
    }
    try {
      final File file = await _cacheFile();
      if (file.existsSync()) {
        await file.delete();
      }
      final File temporary = File('${file.path}.tmp');
      if (temporary.existsSync()) {
        await temporary.delete();
      }
    } on Object catch (error) {
      if (error is MissingPluginException) {
        _cacheAvailable = false;
      }
      logger.w('[DiagnosticActionTrail] Cache delete failed: $error');
    }
  }

  void _scheduleFlush() {
    if (!_enabled || !_dirty || !_cacheAvailable) {
      return;
    }
    _flushTimer ??= Timer(flushInterval, () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  String _configDigest() {
    return configDigest(DiagnosticConfigSnapshot.capture());
  }

  /// Stable digest of only settings that reproduction is allowed to apply.
  static String configDigest(Map<String, dynamic> snapshot) {
    final Map<String, dynamic> applicable = Map<String, dynamic>.from(snapshot)
      ..remove('informationalOnly');
    final Object canonical = _canonicalize(applicable);
    return sha256
        .convert(utf8.encode(jsonEncode(canonical)))
        .toString()
        .substring(0, 16);
  }

  static Object _canonicalize(Object? value) {
    if (value is Map<dynamic, dynamic>) {
      final List<String> keys = value.keys.map((dynamic key) => '$key').toList()
        ..sort();
      return <String, Object?>{
        for (final String key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List<dynamic>) {
      return value.map<Object>(_canonicalize).toList(growable: false);
    }
    return value ?? '';
  }

  static bool _isStateChanging(String actionId) {
    return actionId.startsWith('game.') ||
        actionId == 'settings.changed' ||
        actionId == 'setup.position.action';
  }

  static String _stableRouteId(String value) {
    if (value.isEmpty || value == '/unknown') {
      return 'route.unidentified';
    }
    return value.length <= 160 ? value : value.substring(0, 160);
  }

  static String legacyActionId(RecordingEventType type) {
    return switch (type) {
      RecordingEventType.boardTap => 'game.board.tap',
      RecordingEventType.aiMove => 'game.ai.move',
      RecordingEventType.settingsChange => 'settings.changed',
      RecordingEventType.gameReset => 'game.reset',
      RecordingEventType.gameModeChange => 'game.mode.changed',
      RecordingEventType.gameImport ||
      RecordingEventType.gameLoad => 'game.import',
      RecordingEventType.historyNavigation => 'game.history.navigate',
      RecordingEventType.gameOver => 'game.over',
      RecordingEventType.undoMove => 'game.undo',
      RecordingEventType.toolbarAction => 'ui.toolbar.action',
      RecordingEventType.dialogAction => 'ui.dialog.action',
      RecordingEventType.navigationAction => 'navigation.changed',
      RecordingEventType.annotationAction => 'annotation.action',
      RecordingEventType.setupPositionAction => 'setup.position.action',
      RecordingEventType.custom => 'external.operation',
    };
  }
}
