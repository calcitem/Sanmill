// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_database.dart';

void main() {
  setUp(() async {
    DB.instance = MockDB();
    await LiveEvaluationService.debugReset();
  });

  tearDown(() async {
    await LiveEvaluationService.debugReset();
    DB.instance = null;
  });

  test('supports only the three local play modes', () {
    expect(LiveEvaluationService.supportsMode(GameMode.humanVsAi), isTrue);
    expect(LiveEvaluationService.supportsMode(GameMode.humanVsHuman), isTrue);
    expect(LiveEvaluationService.supportsMode(GameMode.aiVsAi), isTrue);

    for (final GameMode mode in GameMode.values.where(
      (GameMode mode) =>
          mode != GameMode.humanVsAi &&
          mode != GameMode.humanVsHuman &&
          mode != GameMode.aiVsAi,
    )) {
      expect(
        LiveEvaluationService.supportsMode(mode),
        isFalse,
        reason: mode.name,
      );
    }
  });

  test('display controls jointly drive local live evaluation', () async {
    LiveEvaluationService.debugGameMode = GameMode.humanVsHuman;

    await LiveEvaluationService.syncWithDisplayPreferences(
      showIndicator: false,
      showGraph: false,
    );
    expect(LiveEvaluationService.enabled, isFalse);

    await LiveEvaluationService.syncWithDisplayPreferences(
      showIndicator: true,
      showGraph: false,
    );
    expect(LiveEvaluationService.enabled, isTrue);

    await LiveEvaluationService.syncWithDisplayPreferences(
      showIndicator: false,
      showGraph: false,
    );
    expect(LiveEvaluationService.enabled, isFalse);

    await LiveEvaluationService.syncWithDisplayPreferences(
      showIndicator: false,
      showGraph: true,
    );
    expect(LiveEvaluationService.enabled, isTrue);
  });

  test('display controls never enable evaluation for remote play', () async {
    LiveEvaluationService.debugGameMode = GameMode.humanVsLAN;

    await LiveEvaluationService.syncWithDisplayPreferences(
      showIndicator: true,
      showGraph: true,
    );

    expect(LiveEvaluationService.enabled, isFalse);
  });

  test('publishes progressive pending-removal evaluation', () async {
    LiveEvaluationService.debugEnableForMode(GameMode.humanVsHuman);
    LiveEvaluationService
        .debugSearchOverride = (position, engineSettings, onUpdate) async {
      expect(engineSettings.searchAlgorithm, SearchAlgorithm.pvs);
      expect(engineSettings.skillLevel, 30);
      expect(engineSettings.shufflingEnabled, isFalse);
      expect(engineSettings.engineThreads, 1);
      onUpdate(<NativeMillPrincipalVariation>[_variation(score: 18, depth: 8)]);
      await Future<void>.delayed(Duration.zero);
      onUpdate(<NativeMillPrincipalVariation>[
        _variation(score: 27, depth: 16),
      ]);
      return <NativeMillPrincipalVariation>[_variation(score: 27, depth: 16)];
    };

    await LiveEvaluationService.debugRequestPosition(
      _position(fen: 'pending', isRemovalPending: true),
    );

    expect(LiveEvaluationService.state.enabled, isTrue);
    expect(LiveEvaluationService.state.isSearching, isFalse);
    expect(LiveEvaluationService.state.whiteScore, 27);
    expect(LiveEvaluationService.state.positionKey, 'pending');
    expect(LiveEvaluationService.state.isRemovalPending, isTrue);
  });

  test('maps a black root score to White perspective and clamps it', () async {
    LiveEvaluationService.debugEnableForMode(GameMode.humanVsHuman);
    LiveEvaluationService.debugSearchOverride =
        (position, engineSettings, onUpdate) async =>
            <NativeMillPrincipalVariation>[_variation(score: 140)];

    await LiveEvaluationService.debugRequestPosition(
      _position(fen: 'black', activeSeat: PlayerSeat.second),
    );

    expect(LiveEvaluationService.state.whiteScore, -100);
  });

  test('stopping detaches the cancelled search result', () async {
    final Completer<List<NativeMillPrincipalVariation>> result =
        Completer<List<NativeMillPrincipalVariation>>();
    bool stopRequested = false;
    LiveEvaluationService.debugEnableForMode(GameMode.humanVsHuman);
    LiveEvaluationService.debugSearchOverride =
        (position, engineSettings, onUpdate) {
          onUpdate(<NativeMillPrincipalVariation>[_variation(score: 12)]);
          return result.future;
        };
    LiveEvaluationService.debugStopSearch = () {
      stopRequested = true;
      result.complete(<NativeMillPrincipalVariation>[_variation(score: 90)]);
    };

    final Future<void> search = LiveEvaluationService.debugRequestPosition(
      _position(fen: 'cancelled'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(LiveEvaluationService.state.whiteScore, 12);
    expect(LiveEvaluationService.state.isSearching, isTrue);

    await LiveEvaluationService.stopAndWait();
    await search;

    expect(stopRequested, isTrue);
    expect(LiveEvaluationService.state.whiteScore, 12);
    expect(LiveEvaluationService.state.isSearching, isFalse);
  });

  test('terminal positions publish without starting search', () async {
    bool searched = false;
    LiveEvaluationService.debugEnableForMode(GameMode.humanVsHuman);
    LiveEvaluationService.debugSearchOverride =
        (position, engineSettings, onUpdate) async {
          searched = true;
          return <NativeMillPrincipalVariation>[];
        };

    await LiveEvaluationService.debugRequestPosition(
      _position(
        fen: 'terminal',
        outcome: const GameOutcome.win(PlayerSeat.second),
      ),
    );

    expect(searched, isFalse);
    expect(LiveEvaluationService.state.whiteScore, -100);
    expect(LiveEvaluationService.state.isSearching, isFalse);
  });

  test('keeps Human Database WDL without starting heuristic search', () async {
    bool searched = false;
    const HumanDatabaseMoveStats stats = HumanDatabaseMoveStats(
      notation: 'd6',
      wins: 7,
      draws: 1,
      losses: 2,
      total: 10,
      scoreDelta: 0.25,
    );
    const AppliedAiMoveEvaluation applied = AppliedAiMoveEvaluation(
      source: AiMoveType.humanDatabase,
      whiteScore: -50,
      humanDatabaseStats: stats,
      humanDatabaseMoverWasWhite: false,
    );
    LiveEvaluationService.debugEnableForMode(GameMode.humanVsAi);
    LiveEvaluationService.debugSearchOverride =
        (position, engineSettings, onUpdate) async {
          searched = true;
          return <NativeMillPrincipalVariation>[];
        };

    await LiveEvaluationService.debugRequestPosition(
      _position(fen: 'human-db'),
      appliedAiMoveEvaluation: applied,
    );

    expect(searched, isFalse);
    expect(LiveEvaluationService.state.whiteScore, -50);
    expect(LiveEvaluationService.state.appliedAiMoveEvaluation, same(applied));
  });

  test('keeps a Perfect Database result without heuristic search', () async {
    bool searched = false;
    const AppliedAiMoveEvaluation applied = AppliedAiMoveEvaluation(
      source: AiMoveType.perfect,
      whiteScore: 100,
    );
    LiveEvaluationService.debugEnableForMode(GameMode.humanVsAi);
    LiveEvaluationService.debugSearchOverride =
        (position, engineSettings, onUpdate) async {
          searched = true;
          return <NativeMillPrincipalVariation>[];
        };

    await LiveEvaluationService.debugRequestPosition(
      _position(fen: 'perfect-db'),
      appliedAiMoveEvaluation: applied,
    );

    expect(searched, isFalse);
    expect(LiveEvaluationService.state.whiteScore, 100);
    expect(LiveEvaluationService.state.appliedAiMoveEvaluation, same(applied));
  });

  test('detects either side owing a removal', () {
    final Uint8List payload = Uint8List(30)..[29] = 1;
    final GameStateSnapshot snapshot = GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: PlayerSeat.second,
      outcome: const GameOutcome.ongoing(),
      phase: 'placing',
      payload: <String, Object?>{'tgfPayload': payload},
    );

    expect(LiveEvaluationService.isRemovalPending(snapshot), isTrue);
  });

  test('replaces pending-removal graph point when the turn completes', () {
    final List<int> values = <int>[99];
    final LiveAdvantageHistory history = LiveAdvantageHistory(values);

    history.update(_liveState('start', 10), fallbackScore: 0);
    expect(values, <int>[10]);

    history.update(
      _liveState('formed-mill', 20, isRemovalPending: true),
      fallbackScore: 0,
    );
    expect(values, <int>[10, 20]);

    history.update(
      _liveState('second-pending-position', 25, isRemovalPending: true),
      fallbackScore: 0,
    );
    expect(values, <int>[10, 25]);

    history.update(_liveState('removal-complete', 30), fallbackScore: 0);
    expect(values, <int>[10, 30]);

    history.update(_liveState('next-turn', -8), fallbackScore: 0);
    expect(values, <int>[10, 30, -8]);
  });
}

LiveEvaluationPosition _position({
  required String fen,
  PlayerSeat activeSeat = PlayerSeat.first,
  GameOutcome outcome = const GameOutcome.ongoing(),
  bool isRemovalPending = false,
}) {
  return LiveEvaluationPosition(
    fen: fen,
    rules: const RuleSettings(),
    activeSeat: activeSeat,
    outcome: outcome,
    isRemovalPending: isRemovalPending,
  );
}

NativeMillPrincipalVariation _variation({int score = 0, int depth = 8}) {
  return NativeMillPrincipalVariation(
    rank: 1,
    move: 'd6',
    score: score,
    nodes: 100,
    depth: depth,
  );
}

LiveEvaluationState _liveState(
  String positionKey,
  int whiteScore, {
  bool isRemovalPending = false,
}) {
  return LiveEvaluationState(
    enabled: true,
    isSearching: false,
    whiteScore: whiteScore,
    positionKey: positionKey,
    isRemovalPending: isRemovalPending,
  );
}
