// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_responses_test.dart
//
// Tests for game response types, select responses, remove responses,
// engine responses, and history responses.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    "com.calcitem.sanmill/engine",
  );

  setUp(() {
    DB.instance = MockDB();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
  });

  // ---------------------------------------------------------------------------
  // GameResponse hierarchy
  // ---------------------------------------------------------------------------
  group('GameResponse types', () {
    test('GameResponseOK should be a GameResponse', () {
      const GameResponseOK ok = GameResponseOK();
      expect(ok, isA<GameResponse>());
    });

    test('IllegalAction should be a GameResponse', () {
      const IllegalAction action = IllegalAction();
      expect(action, isA<GameResponse>());
    });

    test('IllegalPhase should be a GameResponse', () {
      const IllegalPhase phase = IllegalPhase();
      expect(phase, isA<GameResponse>());
    });
  });

  // ---------------------------------------------------------------------------
  // SelectResponse hierarchy
  // ---------------------------------------------------------------------------
  group('SelectResponse types', () {
    test('CanOnlyMoveToAdjacentEmptyPoints should be SelectResponse', () {
      const CanOnlyMoveToAdjacentEmptyPoints resp =
          CanOnlyMoveToAdjacentEmptyPoints();
      expect(resp, isA<SelectResponse>());
      expect(resp, isA<GameResponse>());
    });

    test('NoPieceSelected should be SelectResponse', () {
      const NoPieceSelected resp = NoPieceSelected();
      expect(resp, isA<SelectResponse>());
    });

    test('SelectOurPieceToMove should be SelectResponse', () {
      const SelectOurPieceToMove resp = SelectOurPieceToMove();
      expect(resp, isA<SelectResponse>());
    });
  });

  // ---------------------------------------------------------------------------
  // RemoveResponse hierarchy
  // ---------------------------------------------------------------------------
  group('RemoveResponse types', () {
    test('NoPieceToRemove should be RemoveResponse', () {
      const NoPieceToRemove resp = NoPieceToRemove();
      expect(resp, isA<RemoveResponse>());
      expect(resp, isA<GameResponse>());
    });

    test('CanNotRemoveSelf should be RemoveResponse', () {
      const CanNotRemoveSelf resp = CanNotRemoveSelf();
      expect(resp, isA<RemoveResponse>());
    });

    test('ShouldRemoveSelf should be RemoveResponse', () {
      const ShouldRemoveSelf resp = ShouldRemoveSelf();
      expect(resp, isA<RemoveResponse>());
    });

    test('CanNotRemoveMill should be RemoveResponse', () {
      const CanNotRemoveMill resp = CanNotRemoveMill();
      expect(resp, isA<RemoveResponse>());
    });

    test('CanNotRemoveNonadjacent should be RemoveResponse', () {
      const CanNotRemoveNonadjacent resp = CanNotRemoveNonadjacent();
      expect(resp, isA<RemoveResponse>());
    });
  });

  // ---------------------------------------------------------------------------
  // EngineResponse hierarchy
  // ---------------------------------------------------------------------------
  group('EngineResponse types', () {
    test('EngineResponseOK should be EngineResponse', () {
      const EngineResponseOK resp = EngineResponseOK();
      expect(resp, isA<EngineResponse>());
    });

    test('EngineResponseHumanOK should be EngineResponse', () {
      const EngineResponseHumanOK resp = EngineResponseHumanOK();
      expect(resp, isA<EngineResponse>());
    });

    test('EngineResponseSkip should be EngineResponse', () {
      const EngineResponseSkip resp = EngineResponseSkip();
      expect(resp, isA<EngineResponse>());
    });

    test('EngineNoBestMove should be both EngineResponse and Exception', () {
      const EngineNoBestMove resp = EngineNoBestMove();
      expect(resp, isA<EngineResponse>());
      expect(resp, isA<Exception>());
    });

    test('EngineGameIsOver should be EngineResponse', () {
      const EngineGameIsOver resp = EngineGameIsOver();
      expect(resp, isA<EngineResponse>());
    });

    test('EngineTimeOut should be both EngineResponse and Exception', () {
      const EngineTimeOut resp = EngineTimeOut();
      expect(resp, isA<EngineResponse>());
      expect(resp, isA<Exception>());
    });

    test('EngineCancelled should be both EngineResponse and Exception', () {
      const EngineCancelled resp = EngineCancelled();
      expect(resp, isA<EngineResponse>());
      expect(resp, isA<Exception>());
    });

    test('EngineDummy should be EngineResponse', () {
      const EngineDummy resp = EngineDummy();
      expect(resp, isA<EngineResponse>());
    });
  });

  // ---------------------------------------------------------------------------
  // HistoryResponse hierarchy
  // ---------------------------------------------------------------------------
  group('HistoryResponse types', () {
    test('HistoryOK should be HistoryResponse', () {
      const HistoryOK resp = HistoryOK();
      expect(resp, isA<HistoryResponse>());
    });

    test('HistoryOK toString should contain tag', () {
      const HistoryOK resp = HistoryOK();
      expect(resp.toString(), contains(HistoryResponse.tag));
      expect(resp.toString(), contains('OK'));
    });

    test('HistoryAbort should be HistoryResponse', () {
      const HistoryAbort resp = HistoryAbort();
      expect(resp, isA<HistoryResponse>());
    });

    test('HistoryAbort toString should contain tag', () {
      const HistoryAbort resp = HistoryAbort();
      expect(resp.toString(), contains(HistoryResponse.tag));
      expect(resp.toString(), contains('aborted'));
    });

    test('HistoryRule should be HistoryResponse', () {
      const HistoryRule resp = HistoryRule();
      expect(resp, isA<HistoryResponse>());
    });

    test('HistoryRule toString should mention rules', () {
      const HistoryRule resp = HistoryRule();
      expect(resp.toString(), contains('rules'));
    });

    test('HistoryRange should be HistoryResponse', () {
      const HistoryRange resp = HistoryRange();
      expect(resp, isA<HistoryResponse>());
    });

    test('HistoryRange toString should mention moveIndex', () {
      const HistoryRange resp = HistoryRange();
      expect(resp.toString(), contains('moveIndex'));
    });

    test('HistoryResponse tag should be defined', () {
      expect(HistoryResponse.tag, isNotEmpty);
      expect(HistoryResponse.tag, contains('History'));
    });
  });

  // ---------------------------------------------------------------------------
  // Type safety: responses should NOT cross hierarchies
  // ---------------------------------------------------------------------------
  group('Response type isolation', () {
    test('SelectResponse should not be RemoveResponse', () {
      const NoPieceSelected resp = NoPieceSelected();
      expect(resp, isNot(isA<RemoveResponse>()));
    });

    test('RemoveResponse should not be SelectResponse', () {
      const NoPieceToRemove resp = NoPieceToRemove();
      expect(resp, isNot(isA<SelectResponse>()));
    });

    test('EngineResponse should not be GameResponse', () {
      const EngineResponseOK resp = EngineResponseOK();
      expect(resp, isNot(isA<GameResponse>()));
    });

    test('HistoryResponse should not be GameResponse', () {
      const HistoryOK resp = HistoryOK();
      expect(resp, isNot(isA<GameResponse>()));
    });
  });
}
