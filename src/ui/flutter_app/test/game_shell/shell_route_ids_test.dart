// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_shell/shell_route_ids.dart';

void main() {
  group('ShellRouteIds', () {
    test('mill play routes are recognized as game surfaces', () {
      expect(isMillPlayRoute(ShellRouteIds.millHumanVsAi), isTrue);
      expect(isMillPlayRoute(ShellRouteIds.millHumanVsHuman), isTrue);
      expect(isMillPlayRoute(ShellRouteIds.millAiVsAi), isTrue);
      expect(isMillPlayRoute(ShellRouteIds.millHumanVsLan), isTrue);
      expect(isMillPlayRoute(ShellRouteIds.millSetupPosition), isTrue);
    });

    test('non-play routes are not game surfaces', () {
      expect(isMillPlayRoute(ShellRouteIds.millPuzzles), isFalse);
      expect(isMillPlayRoute(ShellRouteIds.millStatistics), isFalse);
      expect(isMillPlayRoute(ShellRouteIds.appGeneralSettings), isFalse);
      expect(isMillPlayRoute(ShellRouteIds.appAbout), isFalse);
      expect(isMillPlayRoute(ShellRouteIds.appExit), isFalse);
      expect(isMillPlayRoute(ShellRouteIds.debugPlatformProbe), isFalse);
    });

    test('mill route ids share the "mill." prefix', () {
      const List<String> millRoutes = <String>[
        ShellRouteIds.millHumanVsAi,
        ShellRouteIds.millHumanVsHuman,
        ShellRouteIds.millAiVsAi,
        ShellRouteIds.millHumanVsLan,
        ShellRouteIds.millSetupPosition,
        ShellRouteIds.millPuzzles,
        ShellRouteIds.millStatistics,
      ];
      for (final String routeId in millRoutes) {
        expect(routeId, startsWith('mill.'));
      }
    });

    test('app-level route ids share the "app." prefix', () {
      const List<String> appRoutes = <String>[
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
      for (final String routeId in appRoutes) {
        expect(routeId, startsWith('app.'));
      }
    });

    test('debug route ids share the "debug." prefix', () {
      expect(ShellRouteIds.debugPlatformProbe, startsWith('debug.'));
    });
  });
}
