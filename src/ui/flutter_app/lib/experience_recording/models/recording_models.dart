// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// recording_models.dart

/// Categorizes recorded events for structured replay and analysis.
///
/// Each variant maps to a distinct user or system action. New event types
/// can be appended without breaking existing session files, because the
/// JSON representation uses the enum name as a plain string.
enum RecordingEventType {
  /// User tapped a board square (place, select, move, or remove).
  boardTap,

  /// AI engine produced a move.
  aiMove,

  /// Any settings change (general / rule / display / color).
  settingsChange,

  /// Game was reset (new game, forced reset, or LAN restart).
  gameReset,

  /// Game mode switched (e.g. Human vs AI → Human vs Human).
  gameModeChange,

  /// Game state imported from clipboard.
  gameImport,

  /// Game state loaded from a file.
  gameLoad,

  /// History navigation (forward / back / jump).
  historyNavigation,

  /// Game reached a conclusion (win / loss / draw).
  gameOver,

  /// Undo / take-back action.
  undoMove,

  /// Extension point for future event categories.
  custom,
}

/// A single recorded event with a relative timestamp and typed payload.
///
/// The [timestampMs] field stores the number of milliseconds elapsed since
/// the recording session started, enabling accurate replay timing.
class RecordingEvent {
  const RecordingEvent({
    required this.timestampMs,
    required this.type,
    required this.data,
  });

  /// Deserializes a [RecordingEvent] from a JSON map.
  factory RecordingEvent.fromJson(Map<String, dynamic> json) {
    return RecordingEvent(
      timestampMs: json['timestampMs'] as int? ?? 0,
      type: _eventTypeFromString(json['type'] as String? ?? 'custom'),
      data: (json['data'] as Map<String, dynamic>?) ??
          const <String, dynamic>{},
    );
  }

  /// Milliseconds elapsed since the recording session started.
  final int timestampMs;

  /// The category of this event.
  final RecordingEventType type;

  /// Type-specific payload containing event details.
  ///
  /// For [RecordingEventType.boardTap]: `{'sq': int}`
  /// For [RecordingEventType.aiMove]: `{'move': String, 'value': String?}`
  /// For [RecordingEventType.settingsChange]: `{'category': String, ...}`
  /// For [RecordingEventType.gameReset]: `{'force': bool, 'lanRestart': bool}`
  /// For [RecordingEventType.gameModeChange]: `{'mode': String}`
  /// For [RecordingEventType.historyNavigation]: `{'action': String}`
  /// For [RecordingEventType.gameOver]: `{'winner': String, 'reason': String}`
  final Map<String, dynamic> data;

  /// Serializes this event to a JSON-compatible map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'timestampMs': timestampMs,
        'type': type.name,
        'data': data,
      };

  @override
  String toString() =>
      'RecordingEvent(${type.name}, +${timestampMs}ms, $data)';
}

/// A complete recording session capturing an initial configuration snapshot
/// and a chronological sequence of user / system events.
///
/// Sessions are persisted as JSON files under the app's documents directory
/// and can be shared for offline bug reproduction (digital twin replay).
class RecordingSession {
  const RecordingSession({
    required this.id,
    required this.appVersion,
    required this.deviceInfo,
    required this.startTime,
    required this.durationMs,
    required this.initialSnapshot,
    required this.events,
    this.gameMode,
    this.notes,
  });

  /// Deserializes a [RecordingSession] from a JSON map.
  factory RecordingSession.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawEvents =
        (json['events'] as List<dynamic>?) ?? const <dynamic>[];

    return RecordingSession(
      id: json['id'] as String? ?? '',
      appVersion: json['appVersion'] as String? ?? '',
      deviceInfo: json['deviceInfo'] as String? ?? '',
      startTime: DateTime.tryParse(json['startTime'] as String? ?? '') ??
          DateTime.now(),
      durationMs: json['durationMs'] as int? ?? 0,
      initialSnapshot:
          (json['initialSnapshot'] as Map<String, dynamic>?) ??
              const <String, dynamic>{},
      events: rawEvents
          .map((dynamic e) =>
              RecordingEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      gameMode: json['gameMode'] as String?,
      notes: json['notes'] as String?,
    );
  }

  /// Unique session identifier (UUID v4).
  final String id;

  /// Application version string at the time of recording.
  final String appVersion;

  /// Human-readable device information string.
  final String deviceInfo;

  /// Wall-clock time when the recording session started.
  final DateTime startTime;

  /// Total recording duration in milliseconds.
  final int durationMs;

  /// Complete settings snapshot taken at the start of recording.
  ///
  /// Contains keys: `generalSettings`, `ruleSettings`,
  /// `displaySettings`, `colorSettings`.
  final Map<String, dynamic> initialSnapshot;

  /// Chronologically ordered list of recorded events.
  final List<RecordingEvent> events;

  /// The primary game mode active when recording started (optional).
  final String? gameMode;

  /// Optional user-provided notes describing the session / bug.
  final String? notes;

  /// Total duration as a [Duration] object.
  Duration get duration => Duration(milliseconds: durationMs);

  /// Serializes this session to a JSON-compatible map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'appVersion': appVersion,
        'deviceInfo': deviceInfo,
        'startTime': startTime.toIso8601String(),
        'durationMs': durationMs,
        'initialSnapshot': initialSnapshot,
        'events':
            events.map((RecordingEvent e) => e.toJson()).toList(),
        if (gameMode != null) 'gameMode': gameMode,
        if (notes != null) 'notes': notes,
      };

  /// Creates a copy of this session with selected fields replaced.
  RecordingSession copyWith({
    String? id,
    String? appVersion,
    String? deviceInfo,
    DateTime? startTime,
    int? durationMs,
    Map<String, dynamic>? initialSnapshot,
    List<RecordingEvent>? events,
    String? gameMode,
    String? notes,
  }) {
    return RecordingSession(
      id: id ?? this.id,
      appVersion: appVersion ?? this.appVersion,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      startTime: startTime ?? this.startTime,
      durationMs: durationMs ?? this.durationMs,
      initialSnapshot: initialSnapshot ?? this.initialSnapshot,
      events: events ?? this.events,
      gameMode: gameMode ?? this.gameMode,
      notes: notes ?? this.notes,
    );
  }

  @override
  String toString() =>
      'RecordingSession($id, ${events.length} events, '
      '${duration.inSeconds}s)';
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Converts a string name to a [RecordingEventType], falling back to
/// [RecordingEventType.custom] for unrecognised values.
RecordingEventType _eventTypeFromString(String name) {
  for (final RecordingEventType t in RecordingEventType.values) {
    if (t.name == name) {
      return t;
    }
  }
  return RecordingEventType.custom;
}
