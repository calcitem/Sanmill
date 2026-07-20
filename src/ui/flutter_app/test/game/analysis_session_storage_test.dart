// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:sanmill/game_page/services/import_export/pgn.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_database.dart';
import '../helpers/test_native_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    DB.instance = MockDB();
    await initRustLibForTests();
  });
  tearDownAll(disposeRustLibForTests);

  late Directory directory;
  late Box<dynamic> box;
  late AnalysisSessionStorage storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'sanmill_analysis_session_test_',
    );
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('analysis_session');
    storage = AnalysisSessionStorage.forTesting(box);
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteFromDisk();
    await directory.delete(recursive: true);
  });

  test('round-trips the full tree, exact rules, and active branch', () async {
    const RuleSettings rules = RuleSettings(
      hasDiagonalLines: true,
      nMoveRule: 42,
      mayRemoveFromMillsAlways: true,
    );
    final GameRecorder recorder = _branchedRecorder(rules);

    final NativeMillGameSession source = NativeMillGameSession(rules: rules);
    addTearDown(source.dispose);
    expect(source.restoreMoveStrings(<String>['f4', 'b4']), isTrue);
    final String currentFen = source.getFen();

    final AnalysisSessionRecord captured = AnalysisSessionRecord.capture(
      rules: rules,
      recorder: recorder,
      currentFen: currentFen,
      savedAt: DateTime.utc(2026, 7, 19, 8, 30),
    );
    await box.put(AnalysisSessionStorage.storageKey, captured.toJson());
    await box.close();
    box = await Hive.openBox<dynamic>('analysis_session');
    storage = AnalysisSessionStorage.forTesting(box);

    expect(storage.hasSession, isTrue);
    final AnalysisSessionRecord restored = storage.read()!;
    expect(restored.rules.toJson(), rules.toJson());
    expect(restored.activePath, <int>[1, 0]);
    expect(restored.currentFen, currentFen);
    expect(restored.savedAt, DateTime.utc(2026, 7, 19, 8, 30));
    expect(restored.recorder.rootComments, <String>['root note']);
    expect(restored.recorder.pgnRoot.children, hasLength(2));
    expect(
      restored.recorder.currentPath.map((ExtMove move) => move.move),
      <String>['f4', 'b4'],
    );

    final ExtMove restoredMove = restored.recorder.currentPath.last;
    expect(restoredMove.boardLayout, 'restored-board-layout');
    expect(restoredMove.moveIndex, 8);
    expect(restoredMove.roundIndex, 4);
    expect(restoredMove.preferredRemoveTarget, 3);
    expect(restoredMove.nags, <int>[3, 14]);
    expect(restoredMove.startingComments, <String>['before']);
    expect(restoredMove.comments, <String>['after']);
    expect(restoredMove.quality, MoveQuality.majorGoodMove);
    expect(restoredMove.isVariation, isTrue);
    expect(restoredMove.variationDepth, 1);
    expect(restoredMove.branchColumns, <bool>[true, false]);
    expect(restoredMove.branchColumn, 1);
    expect(restoredMove.branchLineType, 'end');
    expect(restoredMove.isLastSibling, isTrue);
    expect(restoredMove.siblingIndex, 1);
  });

  test(
    'restores the native position and undo stack without UI move events',
    () async {
      const RuleSettings rules = RuleSettings(
        hasDiagonalLines: true,
        nMoveRule: 42,
        mayRemoveFromMillsAlways: true,
      );
      final GameRecorder recorder = _branchedRecorder(rules);
      final NativeMillGameSession source = NativeMillGameSession(rules: rules);
      addTearDown(source.dispose);
      expect(source.restoreMoveStrings(<String>['f4', 'b4']), isTrue);

      final AnalysisSessionRecord record = AnalysisSessionRecord.capture(
        rules: rules,
        recorder: recorder,
        currentFen: source.getFen(),
      );
      await box.put(AnalysisSessionStorage.storageKey, record.toJson());

      final NativeMillGameSession target = NativeMillGameSession();
      addTearDown(target.dispose);
      final List<String> moveEvents = <String>[];
      final subscription = target.events.listen((event) {
        if (event.type == 'millMoveApplied') {
          moveEvents.add(event.payload['move']! as String);
        }
      });
      addTearDown(subscription.cancel);

      final GameController controller = GameController();
      controller.gameInstance.gameMode = GameMode.analysis;
      controller.bindActiveSession(target);
      addTearDown(() => controller.unbindActiveSession(target));

      expect(
        storage.restoreCurrent(
          controller,
          generalSettings: const GeneralSettings(),
        ),
        isTrue,
      );

      expect(target.getFen(), source.getFen());
      expect(target.undoDepth, 2);
      expect(target.activeRuleSettings.toJson(), rules.toJson());
      expect(moveEvents, isEmpty);
      expect(
        controller.gameRecorder.currentPath.map((ExtMove move) => move.move),
        <String>['f4', 'b4'],
      );
      expect(controller.gameRecorder.pgnRoot.children, hasLength(2));
    },
  );

  test('starts a new analysis with the current rules and an empty tree', () {
    const RuleSettings previousRules = RuleSettings(hasDiagonalLines: true);
    const RuleSettings currentRules = RuleSettings(
      nMoveRule: 42,
      mayRemoveFromMillsAlways: true,
    );
    DB().ruleSettings = currentRules;

    final NativeMillGameSession session = NativeMillGameSession(
      rules: previousRules,
    );
    addTearDown(session.dispose);
    expect(session.applyMoveString('d6'), isTrue);

    final GameRecorder recorder = GameRecorder(
      setupPosition: session.getFen(),
      recordedRuleSettings: previousRules,
    )..appendMove(ExtMove('d6', side: PieceColor.white));
    final GameController controller = GameController();
    controller.gameInstance.gameMode = GameMode.analysis;
    controller.gameRecorder = recorder;
    controller.bindActiveSession(session);
    addTearDown(() => controller.unbindActiveSession(session));

    controller.startNewAnalysis(session: session);

    expect(identical(controller.gameRecorder, recorder), isTrue);
    expect(controller.gameRecorder.currentPath, isEmpty);
    expect(controller.gameRecorder.setupPosition, isNull);
    expect(session.undoDepth, 0);
    expect(session.activeRuleSettings.toJson(), currentRules.toJson());

    final NativeMillGameSession expected = NativeMillGameSession(
      rules: currentRules,
    );
    addTearDown(expected.dispose);
    expect(session.getFen(), expected.getFen());
  });

  test('detects content that requires confirmation before replacement', () {
    final GameRecorder recorder = GameRecorder();

    expect(recorder.hasReplaceableAnalysisContent, isFalse);
    recorder.rootComments.add('   ');
    expect(recorder.hasReplaceableAnalysisContent, isFalse);

    recorder.rootComments.add('Opening idea');
    expect(recorder.hasReplaceableAnalysisContent, isTrue);

    recorder.reset();
    expect(recorder.hasReplaceableAnalysisContent, isFalse);
    recorder.appendMove(
      ExtMove(
        'd6',
        side: PieceColor.white,
        nags: <int>[1],
        comments: <String>['Candidate move'],
      )..isVariation = true,
    );
    expect(recorder.hasReplaceableAnalysisContent, isTrue);
  });

  test('rejects a detached current-position path', () async {
    const RuleSettings rules = RuleSettings();
    final GameRecorder recorder = _branchedRecorder(rules);
    final AnalysisSessionRecord record = AnalysisSessionRecord.capture(
      rules: rules,
      recorder: recorder,
      currentFen: 'EEEEEEEEEEEEEEEEEEEEEEEEEE w p p 0 9 9 0 0 0 0 0 0 0 0 0',
    );
    final Map<String, dynamic> json = record.toJson();
    json['activePath'] = <int>[7];
    await box.put(AnalysisSessionStorage.storageKey, json);

    expect(storage.read, throwsFormatException);
  });
}

GameRecorder _branchedRecorder(RuleSettings rules) {
  final GameRecorder recorder = GameRecorder(
    recordedRuleSettings: rules,
    rootComments: <String>['root note'],
  );

  final PgnNode<ExtMove> mainline = PgnNode<ExtMove>(
    ExtMove('d6', side: PieceColor.white),
  )..parent = recorder.pgnRoot;
  recorder.pgnRoot.children.add(mainline);
  final PgnNode<ExtMove> mainlineReply = PgnNode<ExtMove>(
    ExtMove('d2', side: PieceColor.black),
  )..parent = mainline;
  mainline.children.add(mainlineReply);

  final PgnNode<ExtMove> variation = PgnNode<ExtMove>(
    ExtMove('f4', side: PieceColor.white),
  )..parent = recorder.pgnRoot;
  recorder.pgnRoot.children.add(variation);
  final ExtMove annotatedReply =
      ExtMove(
          'b4',
          side: PieceColor.black,
          boardLayout: 'restored-board-layout',
          moveIndex: 8,
          roundIndex: 4,
          preferredRemoveTarget: 3,
          nags: <int>[3, 14],
          startingComments: <String>['before'],
          comments: <String>['after'],
        )
        ..quality = MoveQuality.majorGoodMove
        ..isVariation = true
        ..variationDepth = 1
        ..branchColumns = <bool>[true, false]
        ..branchColumn = 1
        ..branchLineType = 'end'
        ..isLastSibling = true
        ..siblingIndex = 1;
  final PgnNode<ExtMove> variationReply = PgnNode<ExtMove>(annotatedReply)
    ..parent = variation;
  variation.children.add(variationReply);

  recorder.activeNode = variationReply;
  recorder.moveCountNotifier.value = recorder.currentPath.length;
  return recorder;
}
