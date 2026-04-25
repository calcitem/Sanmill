// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_shell/debug_route_ids.dart';

void main() {
  group('DebugRouteIds', () {
    test('debug route ids share the "debug." prefix', () {
      expect(DebugRouteIds.platformProbe, startsWith('debug.'));
    });
  });
}
