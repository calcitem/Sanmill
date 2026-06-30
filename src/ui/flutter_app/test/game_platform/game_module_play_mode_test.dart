// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_module.dart';
import 'package:sanmill/game_platform/game_registry.dart';
import 'package:sanmill/game_shell/shell_route_ids.dart';
import 'package:sanmill/games/mill/mill_game_module.dart';
import 'package:sanmill/games/mill/mill_route_ids.dart';

import '../helpers/locale_helper.dart';

void main() {
  group('GameModule.isPlayModeRoute', () {
    setUp(() {
      GameRegistry.instance.resetForTesting();
      GameRegistry.instance.register(MillGameModule());
    });

    testWidgets('Mill play mode routes are primary play surfaces', (
      WidgetTester tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        makeTestableWidget(
          Builder(
            builder: (BuildContext ctx) {
              context = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final GameModule module = GameRegistry.instance.getModule(GameId.mill)!;
      expect(
        module.isPlayModeRoute(MillRouteIds.humanVsAi.value, context),
        isTrue,
      );
      expect(
        module.isPlayModeRoute(MillRouteIds.humanVsHuman.value, context),
        isTrue,
      );
      expect(
        module.isPlayModeRoute(MillRouteIds.aiVsAi.value, context),
        isTrue,
      );
      expect(
        module.isPlayModeRoute(MillRouteIds.humanVsLan.value, context),
        isTrue,
      );
    });

    testWidgets('drawer contributions and app routes are not play modes', (
      WidgetTester tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        makeTestableWidget(
          Builder(
            builder: (BuildContext ctx) {
              context = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final GameModule module = GameRegistry.instance.getModule(GameId.mill)!;
      expect(
        module.isPlayModeRoute(MillRouteIds.statistics.value, context),
        isFalse,
      );
      expect(
        module.isPlayModeRoute(ShellRouteIds.appGeneralSettings.value, context),
        isFalse,
      );
    });
  });
}
