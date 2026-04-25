// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_route_id.dart';
import 'package:sanmill/game_shell/shell_route_ids.dart';

void main() {
  group('ShellRouteIds', () {
    test('app-level route ids share the "app." prefix', () {
      const List<GameRouteId> appRoutes = <GameRouteId>[
        ShellRouteIds.appBackToMainGame,
        ShellRouteIds.appSettingsGroup,
        ShellRouteIds.appHelpGroup,
        ShellRouteIds.appGeneralSettings,
        ShellRouteIds.appRuleSettings,
        ShellRouteIds.appAppearance,
        ShellRouteIds.appHowToPlay,
        ShellRouteIds.appFeedback,
        ShellRouteIds.appAbout,
        ShellRouteIds.appExit,
      ];
      for (final GameRouteId routeId in appRoutes) {
        expect(routeId.value, startsWith('app.'));
      }
    });

    test('each route id has a unique value', () {
      const List<GameRouteId> all = <GameRouteId>[
        ShellRouteIds.appBackToMainGame,
        ShellRouteIds.appSettingsGroup,
        ShellRouteIds.appHelpGroup,
        ShellRouteIds.appGeneralSettings,
        ShellRouteIds.appRuleSettings,
        ShellRouteIds.appAppearance,
        ShellRouteIds.appHowToPlay,
        ShellRouteIds.appFeedback,
        ShellRouteIds.appAbout,
        ShellRouteIds.appExit,
      ];
      final Set<String> values = all.map((GameRouteId r) => r.value).toSet();
      expect(values.length, all.length);
    });
  });
}
