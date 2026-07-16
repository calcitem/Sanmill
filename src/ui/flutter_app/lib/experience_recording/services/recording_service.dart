// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// recording_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../shared/services/diagnostic_config_snapshot.dart';
import '../../shared/services/diagnostic_sanitizer.dart';
import '../../shared/services/logger.dart';
import '../models/recording_models.dart';
import '../models/user_action_event.dart';
import 'diagnostic_action_trail_service.dart';
import 'diagnostic_route_tracker.dart';

/// Singleton service responsible for capturing user experience sessions.
///
/// When recording is active, every call to [recordEvent] appends a
/// timestamped [RecordingEvent] to the in-memory buffer. The buffer
/// is periodically flushed to disk and finalised when [stopRecording]
/// is called (or when the session reaches safety limits).
///
/// Usage:
/// ```dart
/// await RecordingService().startRecording();
/// RecordingService().recordEvent(RecordingEventType.boardTap, {'sq': 12});
/// await RecordingService().stopRecording();
/// ```
class RecordingService {
  factory RecordingService() => _instance;

  RecordingService._internal();

  static final RecordingService _instance = RecordingService._internal();

  static const String _logTag = '[RecordingService]';

  // -----------------------------------------------------------------------
  // Configuration constants
  // -----------------------------------------------------------------------

  /// Maximum number of events per session before auto-stop.
  static const int maxEventsPerSession = 10000;

  /// Maximum number of persisted session files.
  static const int maxSessionFiles = 20;

  /// Maximum total storage for all session files (50 MiB).
  static const int maxTotalStorageBytes = 50 * 1024 * 1024;

  /// Interval at which the in-memory buffer is flushed to a temp file.
  static const Duration flushInterval = Duration(seconds: 30);

  // -----------------------------------------------------------------------
  // State
  // -----------------------------------------------------------------------

  /// Notifier that external widgets can listen to for recording state changes.
  final ValueNotifier<bool> isRecordingNotifier = ValueNotifier<bool>(false);

  bool get isRecording => isRecordingNotifier.value;

  /// When `true`, recording hooks are suppressed.
  ///
  /// Set by [ReplayService] during session replay to prevent the replay's
  /// own actions (settings changes, board taps, resets) from being captured
  /// as new events and causing a feedback loop.
  bool isSuppressed = false;

  /// Notifier for the current event count (UI can show live counter).
  final ValueNotifier<int> eventCountNotifier = ValueNotifier<int>(0);

  String? _sessionId;
  DateTime? _startTime;
  Stopwatch? _stopwatch;
  Map<String, dynamic>? _initialSnapshot;
  final List<RecordingEvent> _events = <RecordingEvent>[];
  final List<UserActionEventV1> _actionEvents = <UserActionEventV1>[];
  ActionTrailCheckpoint? _actionCheckpoint;
  StreamSubscription<UserActionEventV1>? _actionSubscription;
  Timer? _flushTimer;
  String? _gameMode;
  bool _typedLimitStopRequested = false;

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /// Begins a new recording session.
  ///
  /// Captures a complete configuration snapshot and starts the event timer.
  /// If a session is already active it will be silently stopped first.
  Future<void> startRecording({String? gameMode}) async {
    if (isRecording) {
      await stopRecording();
    }

    _sessionId = const Uuid().v4();
    _startTime = DateTime.now();
    _stopwatch = Stopwatch()..start();
    _events.clear();
    _actionEvents.clear();
    _gameMode = gameMode;
    _typedLimitStopRequested = false;

    // Capture initial snapshot of all settings.
    _initialSnapshot = await _captureSnapshot();
    final DiagnosticActionTrailService trail = DiagnosticActionTrailService();
    _actionCheckpoint = trail.freeze().checkpoint;
    await _actionSubscription?.cancel();
    _actionSubscription = trail.events.listen(_recordTypedEvent);

    isRecordingNotifier.value = true;
    eventCountNotifier.value = 0;

    // Start periodic flushing.
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(flushInterval, (_) => _flushBuffer());

    logger.i('$_logTag Recording started: $_sessionId');
  }

  /// Stops the current recording session and persists the final JSON file.
  ///
  /// Returns the saved [RecordingSession], or `null` if no recording was
  /// active.
  Future<RecordingSession?> stopRecording({String? notes}) async {
    if (!isRecording) {
      return null;
    }

    _stopwatch?.stop();
    _flushTimer?.cancel();
    _flushTimer = null;
    await _actionSubscription?.cancel();
    _actionSubscription = null;

    final RecordingSession session = RecordingSession(
      id: _sessionId!,
      appVersion: await _getAppVersion(),
      deviceInfo: await _getDeviceInfo(),
      startTime: _startTime!,
      durationMs: _stopwatch?.elapsedMilliseconds ?? 0,
      initialSnapshot: _initialSnapshot ?? const <String, dynamic>{},
      events: List<RecordingEvent>.unmodifiable(_events),
      actionCheckpoint: _actionCheckpoint,
      actionEvents: List<UserActionEventV1>.unmodifiable(_actionEvents),
      gameMode: _gameMode,
      notes: notes,
    );

    await _saveSession(session);

    // Housekeeping: enforce storage limits.
    await _enforceStorageLimits();

    // Clean up in-memory state.
    _events.clear();
    _actionEvents.clear();
    _sessionId = null;
    _startTime = null;
    _stopwatch = null;
    _initialSnapshot = null;
    _actionCheckpoint = null;
    _gameMode = null;

    isRecordingNotifier.value = false;
    eventCountNotifier.value = 0;

    logger.i(
      '$_logTag Recording stopped: ${session.id} '
      '(${session.events.length} events, '
      '${session.duration.inSeconds}s)',
    );

    return session;
  }

  /// Appends a new event to the current session.
  ///
  /// No-op when recording is not active, suppressed (during replay), or
  /// when the feature is disabled.
  void recordEvent(
    RecordingEventType type,
    Map<String, dynamic> data, {
    UserActionPhase diagnosticPhase = UserActionPhase.success,
    String? correlationId,
  }) {
    if (isSuppressed) {
      return;
    }
    final DiagnosticActionTrailService actionTrail =
        DiagnosticActionTrailService();
    final Map<String, Object?> reviewedPayload =
        actionTrail
            .recordLegacy(
              type,
              data,
              phase: diagnosticPhase,
              correlationId: correlationId,
            )
            ?.payload ??
        actionTrail.reviewLegacyPayload(type, data);
    if (!isRecording || _stopwatch == null) {
      return;
    }

    // Safety valve: stop recording if we hit the event limit.
    if (_events.length >= maxEventsPerSession) {
      logger.w('$_logTag Max events reached, auto-stopping recording.');
      unawaited(stopRecording(notes: 'Auto-stopped: event limit reached'));
      return;
    }

    final RecordingEvent event = RecordingEvent(
      timestampMs: _stopwatch!.elapsedMilliseconds,
      type: type,
      data: Map<String, dynamic>.from(reviewedPayload),
      page: DiagnosticRouteTracker.currentRouteId,
    );

    _events.add(event);
    eventCountNotifier.value = _events.length;
  }

  void _recordTypedEvent(UserActionEventV1 event) {
    if (!isRecording || isSuppressed) {
      return;
    }
    if (_actionEvents.length >= maxEventsPerSession) {
      if (!_typedLimitStopRequested) {
        _typedLimitStopRequested = true;
        unawaited(
          stopRecording(notes: 'Auto-stopped: typed event limit reached'),
        );
      }
      return;
    }
    _actionEvents.add(event);
    eventCountNotifier.value = _actionEvents.length > _events.length
        ? _actionEvents.length
        : _events.length;
  }

  /// Lists all saved session files, ordered by modification time (newest first).
  Future<List<RecordingSession>> listSessions() async {
    final Directory dir = await _getRecordingsDirectory();
    if (!dir.existsSync()) {
      return const <RecordingSession>[];
    }

    final List<FileSystemEntity> files =
        dir
            .listSync()
            .where(
              (FileSystemEntity f) => f is File && f.path.endsWith('.json'),
            )
            .toList()
          ..sort(
            (FileSystemEntity a, FileSystemEntity b) =>
                b.statSync().modified.compareTo(a.statSync().modified),
          );

    final List<RecordingSession> sessions = <RecordingSession>[];
    for (final FileSystemEntity entity in files) {
      try {
        final String content = await (entity as File).readAsString();
        final RecordingSession decoded = RecordingSession.fromJson(
          jsonDecode(content) as Map<String, dynamic>,
        );
        final RecordingSession session = _migrateAndSanitize(decoded);
        sessions.add(session);
        if (decoded.schemaVersion < 2) {
          await _saveSession(session);
        }
      } catch (e) {
        logger.w('$_logTag Failed to parse session file: ${entity.path}: $e');
        final File file = entity as File;
        final String filename = file.uri.pathSegments.last;
        final String id = filename.endsWith('.json')
            ? filename.substring(0, filename.length - 5)
            : filename;
        if (_isSafeSessionId(id)) {
          sessions.add(
            RecordingSession(
              schemaVersion: 0,
              id: id,
              appVersion: '',
              deviceInfo: '',
              startTime: file.statSync().modified,
              durationMs: 0,
              initialSnapshot: const <String, dynamic>{},
              events: const <RecordingEvent>[],
            ),
          );
        }
      }
    }
    return sessions;
  }

  /// Loads a specific session by its [id].
  Future<RecordingSession?> loadSession(String id) async {
    final File file = await _sessionFile(id);
    if (!file.existsSync()) {
      return null;
    }
    try {
      final String content = await file.readAsString();
      final RecordingSession decoded = RecordingSession.fromJson(
        jsonDecode(content) as Map<String, dynamic>,
      );
      final RecordingSession session = _migrateAndSanitize(decoded);
      if (decoded.schemaVersion < 2) {
        await _saveSession(session);
      }
      return session;
    } catch (e) {
      logger.e('$_logTag Failed to load session $id: $e');
      return null;
    }
  }

  /// Deletes a specific session file.
  Future<void> deleteSession(String id) async {
    final File file = await _sessionFile(id);
    if (file.existsSync()) {
      await file.delete();
      logger.i('$_logTag Deleted session: $id');
    }
  }

  /// Deletes all saved session files.
  Future<void> deleteAllSessions() async {
    final Directory dir = await _getRecordingsDirectory();
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
      await dir.create(recursive: true);
      logger.i('$_logTag All sessions deleted.');
    }
  }

  /// Returns the file path for a given session (for sharing).
  Future<String> getSessionFilePath(String id) async {
    final File file = await _sessionFile(id);
    return file.path;
  }

  /// Imports a recording session from a JSON file at [filePath].
  ///
  /// The file is parsed, validated, and copied into the recordings directory.
  /// Returns the imported [RecordingSession] on success, `null` on failure.
  Future<RecordingSession?> importSessionFromFile(String filePath) async {
    try {
      final File source = File(filePath);
      if (!source.existsSync()) {
        logger.e('$_logTag Import failed: file not found: $filePath');
        return null;
      }
      if (source.lengthSync() > maxTotalStorageBytes) {
        logger.e('$_logTag Import failed: recording file is too large');
        return null;
      }
      final String content = await source.readAsString();
      return importSessionFromJsonString(content);
    } catch (e) {
      logger.e('$_logTag Import from file failed: $e');
      return null;
    }
  }

  /// Imports a recording session from a raw JSON string.
  ///
  /// The JSON is parsed, validated, and saved into the recordings directory.
  /// Returns the imported [RecordingSession] on success, `null` on failure.
  Future<RecordingSession?> importSessionFromJsonString(String jsonStr) async {
    try {
      if (utf8.encode(jsonStr).length > maxTotalStorageBytes) {
        throw const FormatException('Recording import exceeds 50 MiB.');
      }
      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, dynamic>) {
        logger.e('$_logTag Import failed: JSON root is not an object');
        return null;
      }

      _validateImportedJson(decoded);

      final RecordingSession decodedSession = RecordingSession.fromJson(
        decoded,
      );

      // Basic validation: session must have an id and at least one event.
      if (decodedSession.id.isEmpty) {
        logger.e('$_logTag Import failed: session has no id');
        return null;
      }

      final RecordingSession session = _migrateAndSanitize(decodedSession);

      // Save to recordings directory (overwrites if same id exists).
      await _saveSession(session);

      // Enforce storage limits after import.
      await _enforceStorageLimits();

      logger.i(
        '$_logTag Imported session: ${session.id} '
        '(${session.events.length} events)',
      );
      return session;
    } catch (e) {
      logger.e('$_logTag Import from JSON failed: $e');
      return null;
    }
  }

  // -----------------------------------------------------------------------
  // Private helpers
  // -----------------------------------------------------------------------

  /// Captures a complete snapshot of all current settings.
  Future<Map<String, dynamic>> _captureSnapshot() async {
    return DiagnosticConfigSnapshot.capture();
  }

  /// Flushes the in-memory buffer to a temporary file as a safety net.
  Future<void> _flushBuffer() async {
    if (!isRecording || (_events.isEmpty && _actionEvents.isEmpty)) {
      return;
    }

    try {
      final RecordingSession partial = RecordingSession(
        id: _sessionId!,
        appVersion: await _getAppVersion(),
        deviceInfo: await _getDeviceInfo(),
        startTime: _startTime!,
        durationMs: _stopwatch?.elapsedMilliseconds ?? 0,
        initialSnapshot: _initialSnapshot ?? const <String, dynamic>{},
        events: List<RecordingEvent>.from(_events),
        actionCheckpoint: _actionCheckpoint,
        actionEvents: List<UserActionEventV1>.from(_actionEvents),
        gameMode: _gameMode,
        notes: '(partial – recording in progress)',
      );
      await _saveSession(partial);
    } catch (e) {
      logger.w('$_logTag Flush failed: $e');
    }
  }

  /// Persists a [RecordingSession] as a JSON file.
  Future<void> _saveSession(RecordingSession session) async {
    final File file = await _sessionFile(session.id);
    final File temporary = File('${file.path}.tmp');
    final String json = const JsonEncoder.withIndent(
      '  ',
    ).convert(session.toJson());
    await temporary.writeAsString(json, flush: true);
    try {
      await temporary.rename(file.path);
    } on FileSystemException {
      if (file.existsSync()) {
        await file.delete();
      }
      await temporary.rename(file.path);
    }
  }

  RecordingSession _migrateAndSanitize(RecordingSession session) {
    final List<RecordingEvent> safeEvents = <RecordingEvent>[];
    final DiagnosticActionTrailService actionTrail =
        DiagnosticActionTrailService();
    int previousTimestamp = -1;
    for (final RecordingEvent event in session.events) {
      if (event.timestampMs < previousTimestamp || event.timestampMs < 0) {
        throw const FormatException(
          'Recording event timestamps must be ordered and non-negative.',
        );
      }
      previousTimestamp = event.timestampMs;
      safeEvents.add(
        RecordingEvent(
          timestampMs: event.timestampMs,
          type: event.type,
          data: Map<String, dynamic>.from(
            actionTrail.reviewLegacyPayload(event.type, event.data),
          ),
          page: event.page == null
              ? null
              : DiagnosticSanitizer.sanitizeLegacyPayload(<String, dynamic>{
                      'page': event.page,
                    })['page']
                    as String?,
        ),
      );
    }

    final Map<String, dynamic> safeSnapshot;
    if (session.schemaVersion >= 2) {
      // Validation is deliberately applied against a temporary overlay. The
      // imported snapshot is never written to DB during validation.
      safeSnapshot = _sanitizeSnapshot(session.initialSnapshot);
    } else {
      safeSnapshot = _sanitizeLegacySnapshot(session.initialSnapshot);
    }
    final List<UserActionEventV1> safeActionEvents =
        session.actionEvents.isEmpty
        ? _migrateLegacyActionEvents(session.id, safeEvents)
        : session.actionEvents
              .map(
                (UserActionEventV1 event) => UserActionEventV1.fromJson(
                  jsonDecode(jsonEncode(event.toJson()))
                      as Map<String, dynamic>,
                ),
              )
              .toList(growable: false);
    final ActionTrailCheckpoint? safeCheckpoint =
        session.actionCheckpoint == null
        ? null
        : ActionTrailCheckpoint(
            sequence: session.actionCheckpoint!.sequence,
            elapsedMs: session.actionCheckpoint!.elapsedMs,
            safeConfig: DiagnosticConfigSnapshot.validate(
              session.actionCheckpoint!.safeConfig,
            ),
            routeStack: session.actionCheckpoint!.routeStack,
            game: session.actionCheckpoint!.game,
          );
    return session.copyWith(
      schemaVersion: 2,
      initialSnapshot: safeSnapshot,
      events: safeEvents,
      actionCheckpoint: safeCheckpoint,
      actionEvents: safeActionEvents,
    );
  }

  List<UserActionEventV1> _migrateLegacyActionEvents(
    String sessionId,
    List<RecordingEvent> events,
  ) {
    final String runId = 'legacy-${sessionId.isEmpty ? 'unknown' : sessionId}';
    final String boundedRunId = runId.length <= 64
        ? runId
        : runId.substring(0, 64);
    final List<UserActionEventV1> migrated = <UserActionEventV1>[];
    int sequence = 0;
    for (final RecordingEvent event in events) {
      final String actionId = DiagnosticActionTrailService.legacyActionId(
        event.type,
      );
      final Map<String, Object?> payload = Map<String, Object?>.from(
        event.data,
      );
      UserActionPhase phase = UserActionPhase.success;
      if (actionId == 'game.board.tap' && payload['sq'] is! int) {
        continue;
      }
      if (actionId == 'game.ai.move') {
        payload.putIfAbsent('side', () => 'unknown');
        if (payload['move'] is! String) {
          phase = UserActionPhase.failure;
        }
      }
      if (actionId == 'settings.changed' && !payload.containsKey('newValue')) {
        phase = UserActionPhase.cancel;
      }
      sequence++;
      migrated.add(
        UserActionEventV1(
          sequence: sequence,
          elapsedMs: event.timestampMs,
          runId: boundedRunId,
          routeId: event.page == null || event.page!.isEmpty
              ? '/gamePage'
              : event.page!,
          actionId: actionId,
          phase: phase,
          correlationId: 'legacy-$sequence',
          payload: Map<String, Object?>.unmodifiable(payload),
          stateDigest: const <String, String>{},
        ),
      );
    }
    return migrated;
  }

  Map<String, dynamic> _sanitizeSnapshot(Map<String, dynamic> snapshot) {
    final Map<String, dynamic> current = DiagnosticConfigSnapshot.capture();
    final Map<String, dynamic> selected = <String, dynamic>{
      for (final String category in current.keys)
        if (snapshot[category] is Map<String, dynamic>)
          category: <String, dynamic>{
            for (final String key
                in (current[category]! as Map<String, dynamic>).keys)
              if ((snapshot[category]! as Map<String, dynamic>).containsKey(
                key,
              ))
                key: (snapshot[category]! as Map<String, dynamic>)[key],
          },
    };
    return DiagnosticConfigSnapshot.validate(selected);
  }

  Map<String, dynamic> _sanitizeLegacySnapshot(Map<String, dynamic> snapshot) {
    return _sanitizeSnapshot(snapshot);
  }

  void _validateImportedJson(Map<String, dynamic> json) {
    const Set<String> rootKeys = <String>{
      'schemaVersion',
      'id',
      'appVersion',
      'deviceInfo',
      'startTime',
      'durationMs',
      'initialSnapshot',
      'events',
      'actionCheckpoint',
      'actionEvents',
      'gameMode',
      'notes',
    };
    final Set<String> unknownRoot = json.keys.toSet().difference(rootKeys);
    if (unknownRoot.isNotEmpty) {
      throw FormatException(
        'Unknown recording keys: ${unknownRoot.toList()..sort()}',
      );
    }
    final int version = json['schemaVersion'] as int? ?? 1;
    if (version < 1 || version > 2) {
      throw FormatException('Unsupported recording schema version: $version');
    }
    if (version >= 2 && json['actionEvents'] is! List<dynamic>) {
      throw const FormatException('Recording V2 requires actionEvents.');
    }
    if (json['id'] is! String || !_isSafeSessionId(json['id'] as String)) {
      throw const FormatException('Invalid recording id.');
    }
    for (final (String, int) field in const <(String, int)>[
      ('appVersion', 128),
      ('deviceInfo', 256),
      ('startTime', 64),
      ('gameMode', 96),
      ('notes', 8 * 1024),
    ]) {
      final Object? value = json[field.$1];
      if (value != null && (value is! String || value.length > field.$2)) {
        throw FormatException('Invalid recording ${field.$1}.');
      }
    }
    if (DateTime.tryParse(json['startTime'] as String? ?? '') == null ||
        json['durationMs'] is! int ||
        (json['durationMs'] as int) < 0 ||
        json['initialSnapshot'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid recording session metadata.');
    }
    final Object? rawEvents = json['events'];
    if (rawEvents is! List<dynamic> || rawEvents.length > maxEventsPerSession) {
      throw const FormatException('Invalid recording event list.');
    }
    int previousTimestamp = -1;
    for (final Object? rawEvent in rawEvents) {
      if (rawEvent is! Map<String, dynamic>) {
        throw const FormatException('Recording event must be an object.');
      }
      final Set<String> unknown = rawEvent.keys.toSet().difference(
        const <String>{'timestampMs', 'type', 'data', 'page'},
      );
      if (unknown.isNotEmpty) {
        throw FormatException(
          'Unknown recording event keys: ${unknown.toList()..sort()}',
        );
      }
      final Object? timestamp = rawEvent['timestampMs'];
      if (timestamp is! int || timestamp < previousTimestamp) {
        throw const FormatException('Recording timestamps are not ordered.');
      }
      previousTimestamp = timestamp;
      final Object? type = rawEvent['type'];
      final bool knownType =
          type is String &&
          RecordingEventType.values.any(
            (RecordingEventType value) => value.name == type,
          );
      if (!knownType && version >= 2) {
        throw FormatException('Unknown recording event type: $type');
      }
      if (rawEvent['data'] is! Map<String, dynamic>) {
        throw const FormatException('Recording event data must be an object.');
      }
      if (utf8.encode(jsonEncode(rawEvent['data'])).length > 64 * 1024) {
        throw const FormatException('Recording event data exceeds 64 KiB.');
      }
      if (rawEvent['page'] != null &&
          (rawEvent['page'] is! String ||
              (rawEvent['page'] as String).length > 160)) {
        throw const FormatException('Recording page must be a string.');
      }
    }
    final Object? rawActionEvents = json['actionEvents'];
    if (rawActionEvents is List<dynamic>) {
      if (rawActionEvents.length > maxEventsPerSession) {
        throw const FormatException('Too many typed recording events.');
      }
      int previousSequence = -1;
      int previousElapsed = -1;
      for (final Object? rawEvent in rawActionEvents) {
        if (rawEvent is! Map<String, dynamic>) {
          throw const FormatException(
            'Typed recording event must be an object.',
          );
        }
        final UserActionEventV1 event = UserActionEventV1.fromJson(rawEvent);
        if (event.sequence <= previousSequence ||
            event.elapsedMs < previousElapsed) {
          throw const FormatException(
            'Typed recording events are not ordered.',
          );
        }
        previousSequence = event.sequence;
        previousElapsed = event.elapsedMs;
      }
    }
    if (json['actionCheckpoint'] != null) {
      if (json['actionCheckpoint'] is! Map<String, dynamic>) {
        throw const FormatException('Invalid recording action checkpoint.');
      }
      final ActionTrailCheckpoint checkpoint = ActionTrailCheckpoint.fromJson(
        json['actionCheckpoint'] as Map<String, dynamic>,
      );
      DiagnosticConfigSnapshot.validate(checkpoint.safeConfig);
      if (rawActionEvents is List<dynamic> && rawActionEvents.isNotEmpty) {
        final UserActionEventV1 first = UserActionEventV1.fromJson(
          rawActionEvents.first as Map<String, dynamic>,
        );
        if (checkpoint.sequence >= first.sequence ||
            checkpoint.elapsedMs > first.elapsedMs) {
          throw const FormatException(
            'Recording checkpoint must precede typed events.',
          );
        }
      }
    }
  }

  /// Returns the [File] for a given session id.
  Future<File> _sessionFile(String id) async {
    if (!_isSafeSessionId(id)) {
      throw const FormatException('Invalid recording session id.');
    }
    final Directory dir = await _getRecordingsDirectory();
    return File('${dir.path}/$id.json');
  }

  static bool _isSafeSessionId(String id) {
    return id.isNotEmpty &&
        id.length <= 128 &&
        !id.startsWith('.') &&
        !id.contains('..') &&
        RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id);
  }

  /// Returns (and creates if necessary) the recordings storage directory.
  Future<Directory> _getRecordingsDirectory() async {
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${appDocDir.path}/recordings');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Enforces storage limits by removing the oldest sessions.
  Future<void> _enforceStorageLimits() async {
    final Directory dir = await _getRecordingsDirectory();
    if (!dir.existsSync()) {
      return;
    }

    final List<File> files =
        dir
            .listSync()
            .whereType<File>()
            .where((File f) => f.path.endsWith('.json'))
            .toList()
          ..sort(
            (File a, File b) =>
                a.statSync().modified.compareTo(b.statSync().modified),
          );

    // Remove excess files beyond the session count limit.
    while (files.length > maxSessionFiles) {
      final File oldest = files.removeAt(0);
      await oldest.delete();
      logger.i('$_logTag Removed old session: ${oldest.path}');
    }

    // Remove oldest files until total size is under the cap.
    int totalBytes = files.fold<int>(
      0,
      (int sum, File f) => sum + f.lengthSync(),
    );
    while (totalBytes > maxTotalStorageBytes && files.isNotEmpty) {
      final File oldest = files.removeAt(0);
      totalBytes -= oldest.lengthSync();
      await oldest.delete();
      logger.i('$_logTag Removed session for storage cap: ${oldest.path}');
    }
  }

  // -----------------------------------------------------------------------
  // Device / app info helpers
  // -----------------------------------------------------------------------

  String? _cachedAppVersion;

  Future<String> _getAppVersion() async {
    if (_cachedAppVersion != null) {
      return _cachedAppVersion!;
    }
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      _cachedAppVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _cachedAppVersion = 'unknown';
    }
    return _cachedAppVersion!;
  }

  String? _cachedDeviceInfo;

  Future<String> _getDeviceInfo() async {
    if (_cachedDeviceInfo != null) {
      return _cachedDeviceInfo!;
    }
    try {
      final DeviceInfoPlugin plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final AndroidDeviceInfo info = await plugin.androidInfo;
        _cachedDeviceInfo = 'Android ${info.version.release}';
      } else if (Platform.isIOS) {
        final IosDeviceInfo info = await plugin.iosInfo;
        _cachedDeviceInfo = 'iOS ${info.systemVersion}';
      } else if (Platform.isLinux) {
        final LinuxDeviceInfo info = await plugin.linuxInfo;
        _cachedDeviceInfo = info.prettyName;
      } else if (Platform.isWindows) {
        final WindowsDeviceInfo info = await plugin.windowsInfo;
        _cachedDeviceInfo = info.productName;
      } else if (Platform.isMacOS) {
        final MacOsDeviceInfo info = await plugin.macOsInfo;
        _cachedDeviceInfo = 'macOS ${info.osRelease}';
      } else {
        _cachedDeviceInfo = Platform.operatingSystem;
      }
    } catch (_) {
      _cachedDeviceInfo = Platform.operatingSystem;
    }
    return _cachedDeviceInfo!;
  }
}
