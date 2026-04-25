// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_feature_flags.dart';
import 'package:sanmill/game_platform/game_menu.dart';
import 'package:sanmill/game_platform/game_module.dart';
import 'package:sanmill/game_platform/game_registry.dart';
import 'package:sanmill/games/mill/mill_game_module.dart';
import 'package:sanmill/games/mill/mill_route_ids.dart';

import '../helpers/locale_helper.dart';

void main() {
  group('game menu metadata', () {
    setUp(() {
      GameRegistry.instance.resetForTesting();
      GameRegistry.instance.register(MillGameModule());
    });

    tearDown(() {
      GameRegistry.instance.resetForTesting();
    });

    testWidgets('Mill contributes stable drawer metadata from its module', (
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

      final GameModule module = GameRegistry.instance.current;
      final List<GameModeEntry> playModes = module.playModes(context);
      final GameModeEntry humanVsAi = playModes.singleWhere(
        (GameModeEntry mode) => mode.id == MillRouteIds.humanVsAi,
      );
      final GameModeEntry humanVsHuman = playModes.singleWhere(
        (GameModeEntry mode) => mode.id == MillRouteIds.humanVsHuman,
      );

      expect(humanVsAi.drawerKey, const Key('drawer_item_human_vs_ai'));
      expect(humanVsAi.contentKey, const Key('human_ai'));
      expect(humanVsAi.icon, isNotNull);
      expect(humanVsHuman.drawerKey, const Key('drawer_item_human_vs_human'));
      expect(humanVsHuman.contentKey, const Key('human_human'));
      expect(humanVsHuman.icon, isNotNull);
    });

    testWidgets('Mill gates optional drawer contributions with capabilities', (
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

      final GameModule module = GameRegistry.instance.current;
      expect(module.features.supports(GameCapability.puzzles), isTrue);
      expect(module.features.supports(GameCapability.statistics), isTrue);

      final List<GameMenuContribution> contributions = module
          .drawerContributions(context);
      final GameMenuContribution puzzles = contributions.singleWhere(
        (GameMenuContribution contribution) =>
            contribution.id == MillRouteIds.puzzles,
      );
      final GameMenuContribution statistics = contributions.singleWhere(
        (GameMenuContribution contribution) =>
            contribution.id == MillRouteIds.statistics,
      );

      expect(puzzles.drawerKey, const Key('drawer_item_puzzles'));
      expect(puzzles.contentKey, const Key('puzzles'));
      expect(puzzles.icon, isNotNull);
      expect(statistics.drawerKey, const Key('drawer_item_statistics'));
      expect(statistics.contentKey, const Key('statistics'));
      expect(statistics.icon, isNotNull);
    });
  });
}
