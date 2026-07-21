// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

part of '../mill.dart';

/// Versioned, local-only snapshot of an Analysis session.
///
/// The recorder tree is encoded directly instead of flattening it through a
/// PGN mainline. This preserves variations, comments, NAGs, per-node board
/// layouts, and the exact node the user was viewing.
@immutable
class AnalysisSessionRecord {
  const AnalysisSessionRecord({
    required this.rules,
    required this.recorder,
    required this.activePath,
    required this.currentFen,
    required this.savedAt,
  });

  factory AnalysisSessionRecord.capture({
    required RuleSettings rules,
    required GameRecorder recorder,
    required String currentFen,
    DateTime? savedAt,
  }) {
    final String normalizedFen = currentFen.trim();
    assert(normalizedFen.isNotEmpty, 'Analysis session FEN cannot be empty.');
    return AnalysisSessionRecord(
      rules: rules,
      recorder: recorder,
      activePath: _activePathFor(recorder),
      currentFen: normalizedFen,
      savedAt: (savedAt ?? DateTime.now()).toUtc(),
    );
  }

  factory AnalysisSessionRecord.fromJson(Map<dynamic, dynamic> json) {
    final Map<String, dynamic> data = _analysisStringMap(
      json,
      'analysis session',
    );
    final int version = _analysisInt(data['version'], 'version');
    if (version != AnalysisSessionStorage.schemaVersion) {
      throw FormatException('Unsupported analysis session version: $version');
    }

    final RuleSettings rules = RuleSettings.fromJson(
      _analysisStringMap(data['rules'], 'rules'),
    );
    final String? setupPosition = _analysisNullableString(
      data['setupPosition'],
      'setupPosition',
    );
    final String? lastPositionWithRemove = _analysisNullableString(
      data['lastPositionWithRemove'],
      'lastPositionWithRemove',
    );
    final List<String> rootComments = _analysisStringList(
      data['rootComments'],
      'rootComments',
    );
    final GameRecorder recorder = GameRecorder(
      setupPosition: setupPosition,
      lastPositionWithRemove: lastPositionWithRemove,
      recordedRuleSettings: rules,
      rootComments: rootComments,
    );

    final List<dynamic> children = _analysisList(data['tree'], 'tree');
    for (final dynamic child in children) {
      _decodeAnalysisNode(child, recorder.pgnRoot);
    }

    final List<int> activePath = _analysisIntList(
      data['activePath'],
      'activePath',
    );
    PgnNode<ExtMove> activeNode = recorder.pgnRoot;
    for (final int childIndex in activePath) {
      if (childIndex < 0 || childIndex >= activeNode.children.length) {
        throw FormatException(
          'Analysis active path index $childIndex is outside the move tree.',
        );
      }
      activeNode = activeNode.children[childIndex];
    }
    recorder.activeNode = activeNode;
    recorder.moveCountNotifier.value = recorder.currentPath.length;

    return AnalysisSessionRecord(
      rules: rules,
      recorder: recorder,
      activePath: activePath,
      currentFen: _analysisString(data['currentFen'], 'currentFen'),
      savedAt: DateTime.parse(_analysisString(data['savedAt'], 'savedAt')),
    );
  }

  final RuleSettings rules;
  final GameRecorder recorder;
  final List<int> activePath;
  final String currentFen;
  final DateTime savedAt;

  List<PgnNode<ExtMove>> get activePathNodes {
    final List<PgnNode<ExtMove>> nodes = <PgnNode<ExtMove>>[];
    PgnNode<ExtMove> node = recorder.pgnRoot;
    for (final int childIndex in activePath) {
      node = node.children[childIndex];
      nodes.add(node);
    }
    return nodes;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'version': AnalysisSessionStorage.schemaVersion,
      'rules': Map<String, dynamic>.from(rules.toJson()),
      'setupPosition': recorder.setupPosition,
      'lastPositionWithRemove': recorder.lastPositionWithRemove,
      'rootComments': List<String>.from(recorder.rootComments),
      'tree': recorder.pgnRoot.children
          .map<Map<String, dynamic>>(_encodeAnalysisNode)
          .toList(),
      'activePath': List<int>.from(activePath),
      'currentFen': currentFen,
      'savedAt': savedAt.toUtc().toIso8601String(),
    };
  }

  static List<int> _activePathFor(GameRecorder recorder) {
    final List<int> path = <int>[];
    PgnNode<ExtMove>? node = recorder.activeNode;
    while (node != null && node.parent != null) {
      final PgnNode<ExtMove> parent = node.parent!;
      final int childIndex = parent.children.indexOf(node);
      assert(
        childIndex >= 0,
        'Active analysis node must belong to its parent.',
      );
      if (childIndex < 0) {
        throw const FormatException(
          'Active analysis node is detached from its move tree.',
        );
      }
      path.insert(0, childIndex);
      node = parent;
    }
    assert(
      node == null || identical(node, recorder.pgnRoot),
      'Active analysis path must terminate at the recorder root.',
    );
    return path;
  }
}

/// Stores and restores the single most recent Analysis session.
class AnalysisSessionStorage {
  const AnalysisSessionStorage._() : _box = null;

  @visibleForTesting
  const AnalysisSessionStorage.forTesting(Box<dynamic> box) : _box = box;

  static const AnalysisSessionStorage instance = AnalysisSessionStorage._();
  static const int schemaVersion = 1;
  static const String storageKey = 'latestAnalysisSession';

  final Box<dynamic>? _box;

  Box<dynamic> get _dataBox => _box ?? DB().reviewDataBox;

  bool get hasSession {
    final dynamic raw = _dataBox.get(storageKey);
    if (raw is! Map<dynamic, dynamic>) {
      return false;
    }
    return raw['version'] == schemaVersion;
  }

  AnalysisSessionRecord? read() {
    final dynamic raw = _dataBox.get(storageKey);
    if (raw == null) {
      return null;
    }
    if (raw is! Map<dynamic, dynamic>) {
      throw const FormatException('Analysis session must be a map.');
    }
    return AnalysisSessionRecord.fromJson(raw);
  }

  Future<void> saveCurrent(GameController controller) async {
    assert(
      controller.gameInstance.gameMode == GameMode.analysis,
      'Only Analysis sessions can be persisted.',
    );
    final NativeMillGameSession? session = controller.activeNativeMillSession;
    if (session == null) {
      throw StateError('Cannot save Analysis without an active Mill session.');
    }
    final AnalysisSessionRecord record = AnalysisSessionRecord.capture(
      rules: session.activeRuleSettings,
      recorder: controller.gameRecorder,
      currentFen: session.getFen(),
    );
    await _dataBox.put(storageKey, record.toJson());
  }

  /// Restores the saved tree and silently rebuilds the native undo stack.
  ///
  /// Returns false only when no record exists. Malformed records throw so the
  /// caller can surface the failure instead of silently opening another game.
  bool restoreCurrent(
    GameController controller, {
    GeneralSettings? generalSettings,
  }) {
    final AnalysisSessionRecord? record = read();
    if (record == null) {
      return false;
    }
    _restoreRecordedSessionPosition(
      controller,
      record,
      mode: GameMode.analysis,
      generalSettings: generalSettings,
    );
    controller.disableStats = true;
    return true;
  }

  Future<void> clear() => _dataBox.delete(storageKey);
}

void _restoreRecordedSessionPosition(
  GameController controller,
  AnalysisSessionRecord record, {
  required GameMode mode,
  GeneralSettings? generalSettings,
}) {
  final NativeMillGameSession? session = controller.activeNativeMillSession;
  if (session == null) {
    throw StateError('Cannot restore a game without an active Mill session.');
  }

  controller.gameInstance.gameMode = mode;
  session.resetGame(
    rules: record.rules,
    generalSettings: generalSettings ?? DB().generalSettings,
  );
  final String? setupPosition = record.recorder.setupPosition?.trim();
  if (setupPosition != null && setupPosition.isNotEmpty) {
    final bool loaded = session.loadFen(setupPosition);
    if (!loaded) {
      throw const FormatException('Saved setup position is invalid.');
    }
  }

  final List<PgnNode<ExtMove>> activeNodes = record.activePathNodes;
  record.recorder.activeNode = record.recorder.pgnRoot;
  record.recorder.moveCountNotifier.value = 0;
  controller.gameRecorder = record.recorder;

  final bool restored = session.restoreMoveStrings(
    activeNodes.map((PgnNode<ExtMove> node) => node.data!.move),
  );
  if (!restored) {
    throw const FormatException(
      'Saved game path is illegal under its recorded rules.',
    );
  }
  controller.gameRecorder.activeNode = activeNodes.isEmpty
      ? controller.gameRecorder.pgnRoot
      : activeNodes.last;
  controller.gameRecorder.moveCountNotifier.value = activeNodes.length;
  controller.gameRecorder.lastPositionWithRemove =
      record.recorder.lastPositionWithRemove;

  final String restoredFen = session.getFen();
  if (restoredFen != record.currentFen) {
    throw FormatException(
      'Saved position mismatch: expected ${record.currentFen}, '
      'restored $restoredFen.',
    );
  }

  controller.activeSessionSnapshot = session.state.value;
  controller.headerIconsNotifier.showIcons();
  controller.boardSemanticsNotifier.updateSemantics();
}

Map<String, dynamic> _encodeAnalysisNode(PgnNode<ExtMove> node) {
  final ExtMove? move = node.data;
  if (move == null) {
    throw const FormatException('Analysis move node cannot be empty.');
  }
  return <String, dynamic>{
    'move': move.move,
    'side': move.side.name,
    'boardLayout': move.boardLayout,
    'moveIndex': move.moveIndex,
    'roundIndex': move.roundIndex,
    'preferredRemoveTarget': move.preferredRemoveTarget,
    'analysisEvaluation': move.analysisEvaluation,
    'analysisEvaluationDepth': move.analysisEvaluationDepth,
    'nags': move.nags == null ? null : List<int>.from(move.nags!),
    'startingComments': move.startingComments == null
        ? null
        : List<String>.from(move.startingComments!),
    'comments': move.comments == null
        ? null
        : List<String>.from(move.comments!),
    'quality': move.quality?.name,
    'isVariation': move.isVariation,
    'variationDepth': move.variationDepth,
    'branchColumns': move.branchColumns == null
        ? null
        : List<bool>.from(move.branchColumns!),
    'branchColumn': move.branchColumn,
    'branchLineType': move.branchLineType,
    'isLastSibling': move.isLastSibling,
    'siblingIndex': move.siblingIndex,
    'children': node.children
        .map<Map<String, dynamic>>(_encodeAnalysisNode)
        .toList(),
  };
}

PgnNode<ExtMove> _decodeAnalysisNode(dynamic raw, PgnNode<ExtMove> parent) {
  final Map<String, dynamic> json = _analysisStringMap(raw, 'move node');
  final String sideName = _analysisString(json['side'], 'move side');
  final PieceColor side = PieceColor.values.singleWhere(
    (PieceColor value) => value.name == sideName,
    orElse: () =>
        throw FormatException('Unknown Analysis move side: $sideName'),
  );
  final ExtMove move = ExtMove(
    _analysisString(json['move'], 'move'),
    side: side,
    boardLayout: _analysisNullableString(json['boardLayout'], 'boardLayout'),
    moveIndex: _analysisNullableInt(json['moveIndex'], 'moveIndex'),
    roundIndex: _analysisNullableInt(json['roundIndex'], 'roundIndex'),
    preferredRemoveTarget: _analysisNullableInt(
      json['preferredRemoveTarget'],
      'preferredRemoveTarget',
    ),
    analysisEvaluation: _analysisNullableInt(
      json['analysisEvaluation'],
      'analysisEvaluation',
    ),
    analysisEvaluationDepth: _analysisNullableInt(
      json['analysisEvaluationDepth'],
      'analysisEvaluationDepth',
    ),
    nags: _analysisNullableIntList(json['nags'], 'nags'),
    startingComments: _analysisNullableStringList(
      json['startingComments'],
      'startingComments',
    ),
    comments: _analysisNullableStringList(json['comments'], 'comments'),
  );
  final String? qualityName = _analysisNullableString(
    json['quality'],
    'quality',
  );
  if (qualityName != null) {
    move.quality = MoveQuality.values.singleWhere(
      (MoveQuality value) => value.name == qualityName,
      orElse: () =>
          throw FormatException('Unknown Analysis move quality: $qualityName'),
    );
  }
  move.isVariation = _analysisNullableBool(json['isVariation'], 'isVariation');
  move.variationDepth = _analysisNullableInt(
    json['variationDepth'],
    'variationDepth',
  );
  move.branchColumns = _analysisNullableBoolList(
    json['branchColumns'],
    'branchColumns',
  );
  move.branchColumn = _analysisNullableInt(
    json['branchColumn'],
    'branchColumn',
  );
  move.branchLineType = _analysisNullableString(
    json['branchLineType'],
    'branchLineType',
  );
  move.isLastSibling = _analysisNullableBool(
    json['isLastSibling'],
    'isLastSibling',
  );
  move.siblingIndex = _analysisNullableInt(
    json['siblingIndex'],
    'siblingIndex',
  );

  final PgnNode<ExtMove> node = PgnNode<ExtMove>(move)..parent = parent;
  parent.children.add(node);
  for (final dynamic child in _analysisList(json['children'], 'children')) {
    _decodeAnalysisNode(child, node);
  }
  return node;
}

Map<String, dynamic> _analysisStringMap(dynamic raw, String field) {
  if (raw is! Map<dynamic, dynamic>) {
    throw FormatException('Analysis $field must be a map.');
  }
  final Map<String, dynamic> result = <String, dynamic>{};
  raw.forEach((dynamic key, dynamic value) {
    if (key is! String) {
      throw FormatException('Analysis $field contains a non-string key.');
    }
    result[key] = value;
  });
  return result;
}

List<dynamic> _analysisList(dynamic raw, String field) {
  if (raw is! List<dynamic>) {
    throw FormatException('Analysis $field must be a list.');
  }
  return raw;
}

String _analysisString(dynamic raw, String field) {
  if (raw is! String || raw.isEmpty) {
    throw FormatException('Analysis $field must be a non-empty string.');
  }
  return raw;
}

String? _analysisNullableString(dynamic raw, String field) {
  if (raw == null) {
    return null;
  }
  if (raw is! String) {
    throw FormatException('Analysis $field must be a string or null.');
  }
  return raw;
}

int _analysisInt(dynamic raw, String field) {
  if (raw is! int) {
    throw FormatException('Analysis $field must be an integer.');
  }
  return raw;
}

bool _analysisBool(dynamic raw, String field) {
  if (raw is! bool) {
    throw FormatException('Analysis $field must be a boolean.');
  }
  return raw;
}

int? _analysisNullableInt(dynamic raw, String field) {
  if (raw == null) {
    return null;
  }
  return _analysisInt(raw, field);
}

bool? _analysisNullableBool(dynamic raw, String field) {
  if (raw == null) {
    return null;
  }
  if (raw is! bool) {
    throw FormatException('Analysis $field must be a boolean or null.');
  }
  return raw;
}

List<int> _analysisIntList(dynamic raw, String field) {
  return _analysisList(raw, field).map<int>((dynamic value) {
    return _analysisInt(value, field);
  }).toList();
}

List<int>? _analysisNullableIntList(dynamic raw, String field) {
  return raw == null ? null : _analysisIntList(raw, field);
}

List<String> _analysisStringList(dynamic raw, String field) {
  return _analysisList(raw, field).map<String>((dynamic value) {
    if (value is! String) {
      throw FormatException('Analysis $field must contain strings.');
    }
    return value;
  }).toList();
}

List<String>? _analysisNullableStringList(dynamic raw, String field) {
  return raw == null ? null : _analysisStringList(raw, field);
}

List<bool>? _analysisNullableBoolList(dynamic raw, String field) {
  if (raw == null) {
    return null;
  }
  return _analysisList(raw, field).map<bool>((dynamic value) {
    if (value is! bool) {
      throw FormatException('Analysis $field must contain booleans.');
    }
    return value;
  }).toList();
}
