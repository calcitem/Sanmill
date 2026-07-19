// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

part of '../mill.dart';

/// Versioned, local-only snapshot of the unfinished playable game.
///
/// User-saved PGNs remain regular files. This record lives in the app's
/// internal data box so automatic recovery never creates a second, ambiguous
/// item in the user's records directory.
@immutable
class LocalGameSessionRecord {
  const LocalGameSessionRecord({
    required this.mode,
    required this.aiMovesFirst,
    required this.position,
    required this.savedAt,
  });

  factory LocalGameSessionRecord.capture(
    GameController controller, {
    DateTime? savedAt,
  }) {
    final GameMode mode = controller.gameInstance.gameMode;
    assert(
      LocalGameSessionStorage.supportedModes.contains(mode),
      'Only local playable games can be captured for automatic recovery.',
    );
    final NativeMillGameSession? session = controller.activeNativeMillSession;
    if (session == null) {
      throw StateError('Cannot save a local game without a Mill session.');
    }
    final DateTime capturedAt = (savedAt ?? DateTime.now()).toUtc();
    return LocalGameSessionRecord(
      mode: mode,
      aiMovesFirst:
          mode == GameMode.humanVsAi && DB().generalSettings.aiMovesFirst,
      position: AnalysisSessionRecord.capture(
        rules: session.activeRuleSettings,
        recorder: controller.gameRecorder,
        currentFen: session.getFen(),
        savedAt: capturedAt,
      ),
      savedAt: capturedAt,
    );
  }

  factory LocalGameSessionRecord.fromJson(Map<dynamic, dynamic> json) {
    final Map<String, dynamic> data = _analysisStringMap(
      json,
      'local game session',
    );
    final int version = _analysisInt(data['version'], 'version');
    if (version != LocalGameSessionStorage.schemaVersion) {
      throw FormatException('Unsupported local game version: $version');
    }
    final String modeName = _analysisString(data['mode'], 'mode');
    final GameMode mode = GameMode.values.singleWhere(
      (GameMode value) => value.name == modeName,
      orElse: () => throw FormatException('Unknown local game mode: $modeName'),
    );
    if (!LocalGameSessionStorage.supportedModes.contains(mode)) {
      throw FormatException('Unsupported local game mode: $modeName');
    }
    final AnalysisSessionRecord position = AnalysisSessionRecord.fromJson(
      _analysisStringMap(data['position'], 'position'),
    );
    if (position.activePath.isEmpty &&
        (position.recorder.setupPosition?.trim().isEmpty ?? true)) {
      throw const FormatException(
        'An unfinished local game must contain a move or setup position.',
      );
    }
    return LocalGameSessionRecord(
      mode: mode,
      aiMovesFirst: _analysisBool(data['aiMovesFirst'], 'aiMovesFirst'),
      position: position,
      savedAt: DateTime.parse(_analysisString(data['savedAt'], 'savedAt')),
    );
  }

  final GameMode mode;
  final bool aiMovesFirst;
  final AnalysisSessionRecord position;
  final DateTime savedAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'version': LocalGameSessionStorage.schemaVersion,
      'mode': mode.name,
      'aiMovesFirst': aiMovesFirst,
      'position': position.toJson(),
      'savedAt': savedAt.toUtc().toIso8601String(),
    };
  }
}

/// Stores and restores the most recent unfinished local game.
class LocalGameSessionStorage {
  const LocalGameSessionStorage._() : _box = null;

  @visibleForTesting
  const LocalGameSessionStorage.forTesting(Box<dynamic> box) : _box = box;

  static const LocalGameSessionStorage instance = LocalGameSessionStorage._();
  static const int schemaVersion = 1;
  static const String storageKey = 'latestLocalGameSession';
  static const Set<GameMode> supportedModes = <GameMode>{
    GameMode.humanVsAi,
    GameMode.humanVsHuman,
  };

  final Box<dynamic>? _box;

  Box<dynamic> get _dataBox => _box ?? DB().reviewDataBox;

  bool get hasSession {
    final dynamic raw = _dataBox.get(storageKey);
    return raw is Map<dynamic, dynamic> && raw['version'] == schemaVersion;
  }

  LocalGameSessionRecord? read() {
    final dynamic raw = _dataBox.get(storageKey);
    if (raw == null) {
      return null;
    }
    if (raw is! Map<dynamic, dynamic>) {
      throw const FormatException('Local game session must be a map.');
    }
    return LocalGameSessionRecord.fromJson(raw);
  }

  /// Saves a recoverable local game or removes an obsolete local snapshot.
  ///
  /// Unsupported modes leave the snapshot untouched: opening Analysis or a
  /// puzzle must not silently discard a local game the user intended to keep.
  Future<void> persistCurrent(GameController controller) async {
    final GameMode mode = controller.gameInstance.gameMode;
    if (!supportedModes.contains(mode)) {
      return;
    }
    final NativeMillGameSession? session = controller.activeNativeMillSession;
    final bool hasPlayablePosition =
        controller.gameRecorder.currentPath.isNotEmpty ||
        (controller.gameRecorder.setupPosition?.trim().isNotEmpty ?? false);
    if (session == null ||
        session.outcome.isTerminal ||
        !hasPlayablePosition ||
        controller.loadedGameSourcePath != null) {
      await clear();
      return;
    }
    final LocalGameSessionRecord record = LocalGameSessionRecord.capture(
      controller,
    );
    await _dataBox.put(storageKey, record.toJson());
  }

  /// Restores the exact rules, recorder tree, active path, and player sides.
  ///
  /// Returns false only when no record exists. Malformed records throw so the
  /// shell can log and remove them instead of presenting a corrupt game.
  bool restoreCurrent(
    GameController controller, {
    GeneralSettings? generalSettings,
  }) {
    final LocalGameSessionRecord? record = read();
    if (record == null) {
      return false;
    }

    _restoreRecordedSessionPosition(
      controller,
      record.position,
      mode: record.mode,
      generalSettings: generalSettings,
    );
    final Player white = controller.gameInstance.getPlayerByColor(
      PieceColor.white,
    );
    final Player black = controller.gameInstance.getPlayerByColor(
      PieceColor.black,
    );
    if (record.mode == GameMode.humanVsAi) {
      if (DB().generalSettings.aiMovesFirst != record.aiMovesFirst) {
        DB().generalSettings = DB().generalSettings.copyWith(
          aiMovesFirst: record.aiMovesFirst,
        );
      }
      white.isAi = record.aiMovesFirst;
      black.isAi = !record.aiMovesFirst;
      controller.disableStats = false;
    } else {
      white.isAi = false;
      black.isAi = false;
      controller.disableStats = true;
    }
    controller.loadedGameFilenamePrefix = null;
    controller.loadedGameSourcePath = null;
    return true;
  }

  Future<void> clear() => _dataBox.delete(storageKey);
}
