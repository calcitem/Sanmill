// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_platform.dart';
import 'package:sanmill/game_shell/game_session_scope.dart';

void main() {
  testWidgets('GameSessionScope exposes session via inherited lookup', (
    WidgetTester tester,
  ) async {
    final StaticGameSession session = StaticGameSession(
      const GameStateSnapshot(
        gameId: GameId('scope_test'),
        activeSeat: PlayerSeat.first,
        outcome: GameOutcome.ongoing(),
      ),
    );
    addTearDown(session.dispose);

    GameSession? observed;

    await tester.pumpWidget(
      MaterialApp(
        home: GameSessionScope(
          session: session,
          child: Builder(
            builder: (BuildContext context) {
              observed = GameSessionScope.sessionOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(observed, same(session));
  });

  testWidgets('GameSessionScope.sessionOf returns null without a scope', (
    WidgetTester tester,
  ) async {
    GameSession? observed;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            observed = GameSessionScope.sessionOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(observed, isNull);
  });
}
