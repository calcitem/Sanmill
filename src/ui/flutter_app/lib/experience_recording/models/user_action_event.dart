// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:convert';

/// The lifecycle phase of one semantic user action.
enum UserActionPhase { attempt, success, failure, cancel }

/// How a diagnostic action may be handled by the replay UI.
enum UserActionReplayPolicy { replayable, stateOnly, displayOnly, blocked }

/// JSON scalar types accepted by a registered payload field.
enum UserActionValueType { boolean, integer, number, string, jsonScalar }

/// Schema and privacy policy for one semantic action identifier.
class UserActionDefinition {
  const UserActionDefinition({
    required this.actionId,
    required this.fields,
    required this.replayPolicy,
    this.maxStringLength = 160,
    this.allowedInReports = true,
  });

  final String actionId;
  final Map<String, UserActionValueType> fields;
  final UserActionReplayPolicy replayPolicy;
  final int maxStringLength;
  final bool allowedInReports;

  /// Validates and normalizes a payload from trusted application code.
  ///
  /// Unknown or invalid fields are dropped in release builds. Debug builds
  /// assert so that a newly added field cannot silently bypass review.
  Map<String, Object?> sanitizeInternal(Map<String, dynamic> payload) {
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<String, dynamic> entry in payload.entries) {
      final UserActionValueType? expected = fields[entry.key];
      if (expected == null) {
        assert(false, 'Unregistered diagnostic field: $actionId.${entry.key}');
        continue;
      }
      final Object? value = _normalizeValue(entry.value, expected);
      if (value == null && entry.value != null) {
        assert(
          false,
          'Invalid diagnostic field type: $actionId.${entry.key} '
          '(${entry.value.runtimeType})',
        );
        continue;
      }
      result[entry.key] = value is String && value.length > maxStringLength
          ? value.substring(0, maxStringLength)
          : value;
    }
    return result;
  }

  /// Strictly validates untrusted payload data while importing a bundle.
  Map<String, Object?> validateExternal(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Action payload must be a JSON object.');
    }
    final Set<String> unknown = raw.keys.toSet().difference(
      fields.keys.toSet(),
    );
    if (unknown.isNotEmpty) {
      throw FormatException(
        'Unknown fields for $actionId: ${unknown.toList()..sort()}',
      );
    }
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<String, dynamic> entry in raw.entries) {
      final Object? value = _normalizeValue(entry.value, fields[entry.key]!);
      if (value == null && entry.value != null) {
        throw FormatException(
          'Invalid type for $actionId.${entry.key}: '
          '${entry.value.runtimeType}',
        );
      }
      if (value is String && value.length > maxStringLength) {
        throw FormatException(
          '$actionId.${entry.key} exceeds $maxStringLength characters.',
        );
      }
      result[entry.key] = value;
    }
    return result;
  }

  /// Enforces action-specific required fields and bounded value ranges.
  void validateSemantics(UserActionPhase phase, Map<String, Object?> payload) {
    _validateActionSemantics(actionId, phase, payload);
  }

  static Object? _normalizeValue(Object? value, UserActionValueType type) {
    if (value == null) {
      return null;
    }
    return switch (type) {
      UserActionValueType.boolean => value is bool ? value : null,
      UserActionValueType.integer => value is int ? value : null,
      UserActionValueType.number => value is num ? value : null,
      UserActionValueType.string => value is String ? value : null,
      UserActionValueType.jsonScalar =>
        value is bool || value is num || value is String ? value : null,
    };
  }
}

/// Registry of every action that is allowed to enter a report or replay.
///
/// Adding an action requires selecting its payload schema and replay policy in
/// this file. External imports reject anything not registered here.
class UserActionCatalog {
  const UserActionCatalog._();

  static const Map<String, UserActionValueType> _commonFields =
      <String, UserActionValueType>{
        'action': UserActionValueType.string,
        'status': UserActionValueType.string,
        'errorCategory': UserActionValueType.string,
        'gameMode': UserActionValueType.string,
        'phase': UserActionValueType.string,
        'sideToMove': UserActionValueType.string,
        'source': UserActionValueType.string,
        'format': UserActionValueType.string,
        'lengthBucket': UserActionValueType.string,
        'sizeBucket': UserActionValueType.string,
      };

  static const Map<String, UserActionDefinition> definitions =
      <String, UserActionDefinition>{
        'game.board.tap': UserActionDefinition(
          actionId: 'game.board.tap',
          fields: <String, UserActionValueType>{
            ..._commonFields,
            'sq': UserActionValueType.integer,
            'selectedFrom': UserActionValueType.string,
          },
          replayPolicy: UserActionReplayPolicy.replayable,
        ),
        'game.ai.move': UserActionDefinition(
          actionId: 'game.ai.move',
          fields: <String, UserActionValueType>{
            ..._commonFields,
            'move': UserActionValueType.string,
            'side': UserActionValueType.string,
            'value': UserActionValueType.string,
            'depth': UserActionValueType.integer,
          },
          replayPolicy: UserActionReplayPolicy.replayable,
        ),
        'settings.changed': UserActionDefinition(
          actionId: 'settings.changed',
          fields: <String, UserActionValueType>{
            ..._commonFields,
            'category': UserActionValueType.string,
            'settingId': UserActionValueType.string,
            'oldValue': UserActionValueType.jsonScalar,
            'newValue': UserActionValueType.jsonScalar,
          },
          replayPolicy: UserActionReplayPolicy.replayable,
        ),
        'game.reset': UserActionDefinition(
          actionId: 'game.reset',
          fields: <String, UserActionValueType>{
            ..._commonFields,
            'force': UserActionValueType.boolean,
            'lanRestart': UserActionValueType.boolean,
          },
          replayPolicy: UserActionReplayPolicy.replayable,
        ),
        'game.mode.changed': UserActionDefinition(
          actionId: 'game.mode.changed',
          fields: <String, UserActionValueType>{
            ..._commonFields,
            'mode': UserActionValueType.string,
          },
          replayPolicy: UserActionReplayPolicy.replayable,
        ),
        'game.import': UserActionDefinition(
          actionId: 'game.import',
          fields: <String, UserActionValueType>{
            ..._commonFields,
            'includeVariations': UserActionValueType.boolean,
          },
          replayPolicy: UserActionReplayPolicy.blocked,
        ),
        'game.history.navigate': UserActionDefinition(
          actionId: 'game.history.navigate',
          fields: <String, UserActionValueType>{
            ..._commonFields,
            'index': UserActionValueType.integer,
            'direction': UserActionValueType.string,
          },
          replayPolicy: UserActionReplayPolicy.replayable,
        ),
        'game.over': UserActionDefinition(
          actionId: 'game.over',
          fields: <String, UserActionValueType>{
            ..._commonFields,
            'winner': UserActionValueType.string,
            'reason': UserActionValueType.string,
          },
          replayPolicy: UserActionReplayPolicy.stateOnly,
        ),
        'game.undo': UserActionDefinition(
          actionId: 'game.undo',
          fields: <String, UserActionValueType>{
            ..._commonFields,
            'steps': UserActionValueType.integer,
            'requester': UserActionValueType.string,
          },
          replayPolicy: UserActionReplayPolicy.replayable,
        ),
        'ui.toolbar.action': UserActionDefinition(
          actionId: 'ui.toolbar.action',
          fields: <String, UserActionValueType>{
            ..._commonFields,
            'toolbar': UserActionValueType.string,
            'enabled': UserActionValueType.boolean,
            'visible': UserActionValueType.boolean,
            'type': UserActionValueType.string,
            'requester': UserActionValueType.string,
            'steps': UserActionValueType.integer,
            'searchTimeMs': UserActionValueType.integer,
            'count': UserActionValueType.integer,
            'dataIndex': UserActionValueType.integer,
          },
          replayPolicy: UserActionReplayPolicy.displayOnly,
        ),
        'ui.dialog.action': UserActionDefinition(
          actionId: 'ui.dialog.action',
          fields: <String, UserActionValueType>{
            ..._commonFields,
            'dialog': UserActionValueType.string,
            'selection': UserActionValueType.string,
          },
          replayPolicy: UserActionReplayPolicy.displayOnly,
        ),
        'navigation.changed': UserActionDefinition(
          actionId: 'navigation.changed',
          fields: <String, UserActionValueType>{
            ..._commonFields,
            'page': UserActionValueType.string,
            'navigatorId': UserActionValueType.string,
          },
          replayPolicy: UserActionReplayPolicy.displayOnly,
        ),
        'annotation.action': UserActionDefinition(
          actionId: 'annotation.action',
          fields: <String, UserActionValueType>{
            ..._commonFields,
            'tool': UserActionValueType.string,
            'color': UserActionValueType.integer,
          },
          replayPolicy: UserActionReplayPolicy.displayOnly,
        ),
        'setup.position.action': UserActionDefinition(
          actionId: 'setup.position.action',
          fields: <String, UserActionValueType>{
            ..._commonFields,
            'value': UserActionValueType.string,
            'type': UserActionValueType.string,
            'piece': UserActionValueType.string,
            'side': UserActionValueType.string,
            'direction': UserActionValueType.string,
          },
          replayPolicy: UserActionReplayPolicy.stateOnly,
        ),
        'app.lifecycle': UserActionDefinition(
          actionId: 'app.lifecycle',
          fields: <String, UserActionValueType>{
            ..._commonFields,
            'state': UserActionValueType.string,
          },
          replayPolicy: UserActionReplayPolicy.displayOnly,
        ),
        'llm.request': UserActionDefinition(
          actionId: 'llm.request',
          fields: <String, UserActionValueType>{
            'feature': UserActionValueType.string,
            'providerCategory': UserActionValueType.string,
            'textLengthBucket': UserActionValueType.string,
            'errorCategory': UserActionValueType.string,
          },
          replayPolicy: UserActionReplayPolicy.blocked,
        ),
        'remote.state.changed': UserActionDefinition(
          actionId: 'remote.state.changed',
          fields: <String, UserActionValueType>{
            'transport': UserActionValueType.string,
            'fromState': UserActionValueType.string,
            'toState': UserActionValueType.string,
            'errorCategory': UserActionValueType.string,
          },
          replayPolicy: UserActionReplayPolicy.displayOnly,
        ),
        'external.operation': UserActionDefinition(
          actionId: 'external.operation',
          fields: <String, UserActionValueType>{..._commonFields},
          replayPolicy: UserActionReplayPolicy.blocked,
        ),
      };

  static UserActionDefinition require(String actionId) {
    final UserActionDefinition? definition = definitions[actionId];
    if (definition == null) {
      throw FormatException('Unknown diagnostic action: $actionId');
    }
    return definition;
  }
}

/// One strictly typed, privacy-reviewed semantic action.
class UserActionEventV1 {
  const UserActionEventV1({
    required this.sequence,
    required this.elapsedMs,
    required this.runId,
    required this.routeId,
    required this.actionId,
    required this.phase,
    required this.correlationId,
    required this.payload,
    required this.stateDigest,
  });

  factory UserActionEventV1.fromJson(Map<String, dynamic> json) {
    _rejectUnknownKeys(json, const <String>{
      'sequence',
      'elapsedMs',
      'runId',
      'routeId',
      'actionId',
      'phase',
      'correlationId',
      'payload',
      'stateDigest',
    }, 'action event');
    final String actionId = _requiredString(json, 'actionId', 96);
    final UserActionDefinition definition = UserActionCatalog.require(actionId);
    if (!definition.allowedInReports) {
      throw FormatException('$actionId is not allowed in reports.');
    }
    final Map<String, Object?> payload = definition.validateExternal(
      json['payload'],
    );
    final Map<String, String> digest = _strictStringMap(
      json['stateDigest'],
      allowedKeys: const <String>{'fen', 'zobrist', 'config', 'route'},
      maxValueLength: 256,
      label: 'stateDigest',
    );
    final UserActionPhase phase = _enumByName(
      UserActionPhase.values,
      json['phase'],
      'phase',
    );
    definition.validateSemantics(phase, payload);
    return UserActionEventV1(
      sequence: _requiredNonNegativeInt(json, 'sequence'),
      elapsedMs: _requiredNonNegativeInt(json, 'elapsedMs'),
      runId: _requiredString(json, 'runId', 64),
      routeId: _requiredString(json, 'routeId', 160),
      actionId: actionId,
      phase: phase,
      correlationId: _requiredString(json, 'correlationId', 64),
      payload: payload,
      stateDigest: digest,
    );
  }

  final int sequence;
  final int elapsedMs;
  final String runId;
  final String routeId;
  final String actionId;
  final UserActionPhase phase;
  final String correlationId;
  final Map<String, Object?> payload;
  final Map<String, String> stateDigest;

  UserActionReplayPolicy get replayPolicy =>
      UserActionCatalog.require(actionId).replayPolicy;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'sequence': sequence,
    'elapsedMs': elapsedMs,
    'runId': runId,
    'routeId': routeId,
    'actionId': actionId,
    'phase': phase.name,
    'correlationId': correlationId,
    'payload': payload,
    'stateDigest': stateDigest,
  };

  int get encodedBytes => utf8.encode(jsonEncode(toJson())).length;
}

/// Reproducible baseline kept immediately before retained trail events.
class ActionTrailCheckpoint {
  const ActionTrailCheckpoint({
    required this.sequence,
    required this.elapsedMs,
    required this.safeConfig,
    required this.routeStack,
    required this.game,
  });

  factory ActionTrailCheckpoint.fromJson(Map<String, dynamic> json) {
    _rejectUnknownKeys(json, const <String>{
      'sequence',
      'elapsedMs',
      'safeConfig',
      'routeStack',
      'game',
    }, 'checkpoint');
    final Object? rawRoutes = json['routeStack'];
    if (rawRoutes is! List<dynamic> ||
        rawRoutes.any((dynamic route) => route is! String)) {
      throw const FormatException('routeStack must contain only strings.');
    }
    if (rawRoutes.length > 32) {
      throw const FormatException('routeStack exceeds 32 entries.');
    }
    if (rawRoutes.any(
      (dynamic route) => (route as String).isEmpty || route.length > 160,
    )) {
      throw const FormatException('routeStack contains an invalid route ID.');
    }
    return ActionTrailCheckpoint(
      sequence: _requiredNonNegativeInt(json, 'sequence'),
      elapsedMs: _requiredNonNegativeInt(json, 'elapsedMs'),
      safeConfig: _strictJsonObject(
        json['safeConfig'],
        maxEncodedBytes: 32 * 1024,
        label: 'safeConfig',
      ),
      routeStack: rawRoutes.cast<String>(),
      game: _strictJsonObject(
        json['game'],
        maxEncodedBytes: 64 * 1024,
        label: 'game',
      ),
    );
  }

  final int sequence;
  final int elapsedMs;
  final Map<String, dynamic> safeConfig;
  final List<String> routeStack;
  final Map<String, dynamic> game;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'sequence': sequence,
    'elapsedMs': elapsedMs,
    'safeConfig': safeConfig,
    'routeStack': routeStack,
    'game': game,
  };
}

/// Immutable result frozen into a report draft.
class DiagnosticActionTrailSnapshot {
  const DiagnosticActionTrailSnapshot({
    required this.checkpoint,
    required this.events,
    required this.truncatedEventCount,
    required this.recordedAtUtc,
  });

  factory DiagnosticActionTrailSnapshot.fromJson(Map<String, dynamic> json) {
    _rejectUnknownKeys(json, const <String>{
      'checkpoint',
      'events',
      'truncatedEventCount',
      'recordedAtUtc',
    }, 'action trail');
    final Object? rawEvents = json['events'];
    if (rawEvents is! List<dynamic>) {
      throw const FormatException('events must be an array.');
    }
    if (rawEvents.length > 500) {
      throw const FormatException('Action trail exceeds 500 events.');
    }
    final List<UserActionEventV1> events = rawEvents
        .map(
          (dynamic value) =>
              UserActionEventV1.fromJson(_asStringMap(value, 'event')),
        )
        .toList(growable: false);
    int previous = -1;
    int previousElapsedMs = -1;
    String? runId;
    final Map<String, UserActionPhase> correlations =
        <String, UserActionPhase>{};
    for (final UserActionEventV1 event in events) {
      if (event.sequence <= previous) {
        throw const FormatException('Event sequence is not strictly ordered.');
      }
      if (event.elapsedMs < previousElapsedMs) {
        throw const FormatException('Event elapsed times are not ordered.');
      }
      runId ??= event.runId;
      if (event.runId != runId) {
        throw const FormatException('Action trail contains multiple run IDs.');
      }
      final UserActionPhase? previousPhase = correlations[event.correlationId];
      if (previousPhase == null) {
        correlations[event.correlationId] = event.phase;
      } else if (previousPhase == UserActionPhase.attempt &&
          event.phase != UserActionPhase.attempt) {
        correlations[event.correlationId] = event.phase;
      } else {
        throw FormatException(
          'Invalid correlation lifecycle for ${event.correlationId}.',
        );
      }
      previous = event.sequence;
      previousElapsedMs = event.elapsedMs;
    }
    final String recordedAt = _requiredString(json, 'recordedAtUtc', 64);
    final DateTime? parsed = DateTime.tryParse(recordedAt);
    if (parsed == null || !parsed.isUtc) {
      throw const FormatException('recordedAtUtc must be a UTC timestamp.');
    }
    final ActionTrailCheckpoint? checkpoint = json['checkpoint'] == null
        ? null
        : ActionTrailCheckpoint.fromJson(
            _asStringMap(json['checkpoint'], 'checkpoint'),
          );
    if (checkpoint != null && events.isNotEmpty) {
      if (checkpoint.sequence >= events.first.sequence ||
          checkpoint.elapsedMs > events.first.elapsedMs) {
        throw const FormatException(
          'Action checkpoint must precede all retained events.',
        );
      }
    }
    return DiagnosticActionTrailSnapshot(
      checkpoint: checkpoint,
      events: events,
      truncatedEventCount: _requiredNonNegativeInt(json, 'truncatedEventCount'),
      recordedAtUtc: parsed,
    );
  }

  final ActionTrailCheckpoint? checkpoint;
  final List<UserActionEventV1> events;
  final int truncatedEventCount;
  final DateTime recordedAtUtc;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'checkpoint': checkpoint?.toJson(),
    'events': events.map((UserActionEventV1 event) => event.toJson()).toList(),
    'truncatedEventCount': truncatedEventCount,
    'recordedAtUtc': recordedAtUtc.toUtc().toIso8601String(),
  };
}

void _validateActionSemantics(
  String actionId,
  UserActionPhase phase,
  Map<String, Object?> payload,
) {
  if (actionId == 'game.board.tap') {
    final Object? square = payload['sq'];
    if (square is! int || square < 0 || square > 31) {
      throw const FormatException('game.board.tap.sq must be in 0..31.');
    }
  }
  if (actionId == 'game.ai.move') {
    if (payload['side'] is! String) {
      throw const FormatException('game.ai.move.side is required.');
    }
    if (phase == UserActionPhase.success && payload['move'] is! String) {
      throw const FormatException(
        'Successful game.ai.move requires a recorded move.',
      );
    }
  }
  if (actionId == 'settings.changed') {
    const Set<String> categories = <String>{
      'general',
      'rule',
      'display',
      'color',
    };
    if (!categories.contains(payload['category']) ||
        payload['settingId'] is! String) {
      throw const FormatException('Invalid settings.changed target.');
    }
    if (phase == UserActionPhase.success && !payload.containsKey('newValue')) {
      throw const FormatException(
        'Successful settings.changed requires newValue.',
      );
    }
  }
}

void _rejectUnknownKeys(
  Map<String, dynamic> json,
  Set<String> allowed,
  String label,
) {
  final Set<String> unknown = json.keys.toSet().difference(allowed);
  if (unknown.isNotEmpty) {
    throw FormatException('Unknown $label keys: ${unknown.toList()..sort()}');
  }
}

int _requiredNonNegativeInt(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is! int || value < 0) {
    throw FormatException('$key must be a non-negative integer.');
  }
  return value;
}

String _requiredString(Map<String, dynamic> json, String key, int maxLength) {
  final Object? value = json[key];
  if (value is! String || value.isEmpty || value.length > maxLength) {
    throw FormatException('$key must be a non-empty string <= $maxLength.');
  }
  return value;
}

T _enumByName<T extends Enum>(List<T> values, Object? raw, String label) {
  if (raw is! String) {
    throw FormatException('$label must be a string.');
  }
  for (final T value in values) {
    if (value.name == raw) {
      return value;
    }
  }
  throw FormatException('Unknown $label: $raw');
}

Map<String, dynamic> _asStringMap(Object? raw, String label) {
  if (raw is! Map<String, dynamic>) {
    throw FormatException('$label must be a JSON object.');
  }
  return raw;
}

Map<String, String> _strictStringMap(
  Object? raw, {
  required Set<String> allowedKeys,
  required int maxValueLength,
  required String label,
}) {
  if (raw is! Map<String, dynamic>) {
    throw FormatException('$label must be a JSON object.');
  }
  final Set<String> unknown = raw.keys.toSet().difference(allowedKeys);
  if (unknown.isNotEmpty) {
    throw FormatException('Unknown $label keys: ${unknown.toList()..sort()}');
  }
  final Map<String, String> result = <String, String>{};
  for (final MapEntry<String, dynamic> entry in raw.entries) {
    if (entry.value is! String ||
        (entry.value as String).length > maxValueLength) {
      throw FormatException('$label.${entry.key} must be a short string.');
    }
    result[entry.key] = entry.value as String;
  }
  return result;
}

Map<String, dynamic> _strictJsonObject(
  Object? raw, {
  required int maxEncodedBytes,
  required String label,
}) {
  if (raw is! Map<String, dynamic>) {
    throw FormatException('$label must be a JSON object.');
  }
  if (utf8.encode(jsonEncode(raw)).length > maxEncodedBytes) {
    throw FormatException('$label exceeds $maxEncodedBytes bytes.');
  }
  return raw;
}
