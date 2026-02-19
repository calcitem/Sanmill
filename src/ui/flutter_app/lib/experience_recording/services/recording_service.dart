// SPDX-License-Identifier: GPL-3.0-or-later
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

import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';
import '../models/recording_models.dart';
import 'recording_navigator_observer.dart';

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
  Timer? _flushTimer;
  String? _gameMode;

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
    _gameMode = gameMode;

    // Capture initial snapshot of all settings.
    _initialSnapshot = await _captureSnapshot();

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

    final RecordingSession session = RecordingSession(
      id: _sessionId!,
      appVersion: await _getAppVersion(),
      deviceInfo: await _getDeviceInfo(),
      startTime: _startTime!,
      durationMs: _stopwatch?.elapsedMilliseconds ?? 0,
      initialSnapshot: _initialSnapshot ?? const <String, dynamic>{},
      events: List<RecordingEvent>.unmodifiable(_events),
      gameMode: _gameMode,
      notes: notes,
    );

    await _saveSession(session);

    // Housekeeping: enforce storage limits.
    await _enforceStorageLimits();

    // Clean up in-memory state.
    _events.clear();
    _sessionId = null;
    _startTime = null;
    _stopwatch = null;
    _initialSnapshot = null;
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
  void recordEvent(RecordingEventType type, Map<String, dynamic> data) {
    if (!isRecording || isSuppressed || _stopwatch == null) {
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
      data: data,
      page: RecordingNavigatorObserver().currentRouteName,
    );

    _events.add(event);
    eventCountNotifier.value = _events.length;
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
        sessions.add(
          RecordingSession.fromJson(
            jsonDecode(content) as Map<String, dynamic>,
          ),
        );
      } catch (e) {
        logger.w('$_logTag Failed to parse session file: ${entity.path}: $e');
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
      return RecordingSession.fromJson(
        jsonDecode(content) as Map<String, dynamic>,
      );
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
      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, dynamic>) {
        logger.e('$_logTag Import failed: JSON root is not an object');
        return null;
      }

      final RecordingSession session = RecordingSession.fromJson(decoded);

      // Basic validation: session must have an id and at least one event.
      if (session.id.isEmpty) {
        logger.e('$_logTag Import failed: session has no id');
        return null;
      }

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
    return <String, dynamic>{
      'generalSettings': DB().generalSettings.toJson(),
      'ruleSettings': DB().ruleSettings.toJson(),
      'displaySettings': DB().displaySettings.toJson(),
      'colorSettings': DB().colorSettings.toJson(),
    };
  }

  /// Flushes the in-memory buffer to a temporary file as a safety net.
  Future<void> _flushBuffer() async {
    if (!isRecording || _events.isEmpty) {
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
    final String json = const JsonEncoder.withIndent(
      '  ',
    ).convert(session.toJson());
    await file.writeAsString(json);
  }

  /// Returns the [File] for a given session id.
  Future<File> _sessionFile(String id) async {
    final Directory dir = await _getRecordingsDirectory();
    return File('${dir.path}/$id.json');
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
        _cachedDeviceInfo =
            '${info.brand} ${info.model} (Android ${info.version.release})';
      } else if (Platform.isIOS) {
        final IosDeviceInfo info = await plugin.iosInfo;
        _cachedDeviceInfo =
            '${info.utsname.machine} (iOS ${info.systemVersion})';
      } else if (Platform.isLinux) {
        final LinuxDeviceInfo info = await plugin.linuxInfo;
        _cachedDeviceInfo = info.prettyName;
      } else if (Platform.isWindows) {
        final WindowsDeviceInfo info = await plugin.windowsInfo;
        _cachedDeviceInfo = info.productName;
      } else if (Platform.isMacOS) {
        final MacOsDeviceInfo info = await plugin.macOsInfo;
        _cachedDeviceInfo = '${info.model} (macOS ${info.osRelease})';
      } else {
        _cachedDeviceInfo = Platform.operatingSystem;
      }
    } catch (_) {
      _cachedDeviceInfo = Platform.operatingSystem;
    }
    return _cachedDeviceInfo!;
  }
}
