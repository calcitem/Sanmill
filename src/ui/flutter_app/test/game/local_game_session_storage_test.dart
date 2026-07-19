// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_platform/game_session.dart' show GameOutcome;
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
  late LocalGameSessionStorage storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'sanmill_local_game_session_test_',
    );
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('local_game_session');
    storage = LocalGameSessionStorage.forTesting(box);
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteFromDisk();
    await directory.delete(recursive: true);
  });

  test(
    'round-trips exact rules, current position, and computer side',
    () async {
      const RuleSettings rules = RuleSettings(
        hasDiagonalLines: true,
        nMoveRule: 42,
        mayRemoveFromMillsAlways: true,
      );
      final NativeMillGameSession source = NativeMillGameSession(rules: rules);
      addTearDown(source.dispose);
      expect(source.applyMoveString('d6'), isTrue);
      expect(source.applyMoveString('f4'), isTrue);

      final GameController controller = GameController();
      controller
        ..gameInstance.gameMode = GameMode.humanVsAi
        ..gameRecorder = GameRecorder(recordedRuleSettings: rules)
        ..bindActiveSession(source);
      controller.gameRecorder
        ..appendMove(ExtMove('d6', side: PieceColor.white))
        ..appendMove(ExtMove('f4', side: PieceColor.black));
      DB().generalSettings = const GeneralSettings(aiMovesFirst: true);
      final String expectedFen = source.getFen();

      await storage.persistCurrent(controller);
      expect(storage.hasSession, isTrue);
      await box.close();
      box = await Hive.openBox<dynamic>('local_game_session');
      storage = LocalGameSessionStorage.forTesting(box);

      controller.unbindActiveSession(source);
      final NativeMillGameSession target = NativeMillGameSession();
      addTearDown(target.dispose);
      controller
        ..gameRecorder = GameRecorder()
        ..bindActiveSession(target);
      addTearDown(() => controller.unbindActiveSession(target));

      expect(
        storage.restoreCurrent(
          controller,
          generalSettings: const GeneralSettings(),
        ),
        isTrue,
      );
      expect(controller.gameInstance.gameMode, GameMode.humanVsAi);
      expect(target.getFen(), expectedFen);
      expect(target.activeRuleSettings.toJson(), rules.toJson());
      expect(target.undoDepth, 2);
      expect(
        controller.gameRecorder.currentPath.map((ExtMove move) => move.move),
        <String>['d6', 'f4'],
      );
      expect(
        controller.gameInstance.getPlayerByColor(PieceColor.white).isAi,
        isTrue,
      );
      expect(
        controller.gameInstance.getPlayerByColor(PieceColor.black).isAi,
        isFalse,
      );
    },
  );

  test('clears a completed game instead of retaining it as ongoing', () async {
    final NativeMillGameSession session = NativeMillGameSession();
    addTearDown(session.dispose);
    expect(session.applyMoveString('d6'), isTrue);
    final GameController controller = GameController();
    controller
      ..gameInstance.gameMode = GameMode.humanVsHuman
      ..gameRecorder = GameRecorder()
      ..bindActiveSession(session);
    controller.gameRecorder.appendMove(ExtMove('d6', side: PieceColor.white));
    addTearDown(() => controller.unbindActiveSession(session));

    await storage.persistCurrent(controller);
    expect(storage.hasSession, isTrue);

    session.forceTerminal(const GameOutcome.draw());
    await storage.persistCurrent(controller);
    expect(storage.hasSession, isFalse);
  });

  test('opening a tool does not discard the saved local game', () async {
    final Map<String, dynamic> raw = <String, dynamic>{
      'version': LocalGameSessionStorage.schemaVersion,
      'mode': GameMode.humanVsHuman.name,
      'aiMovesFirst': false,
      'position': AnalysisSessionRecord.capture(
        rules: const RuleSettings(),
        recorder: GameRecorder()..setupPosition = _setupFen,
        currentFen: _setupFen,
      ).toJson(),
      'savedAt': DateTime.utc(2026, 7, 19).toIso8601String(),
    };
    await box.put(LocalGameSessionStorage.storageKey, raw);

    final GameController controller = GameController();
    controller.gameInstance.gameMode = GameMode.analysis;
    await storage.persistCurrent(controller);

    expect(storage.hasSession, isTrue);
  });
}

const String _setupFen =
    '********/********/******** w p p 0 9 0 9 0 0 -1 -1 -1 -1 0 0 1 '
    'ids:nodes';
