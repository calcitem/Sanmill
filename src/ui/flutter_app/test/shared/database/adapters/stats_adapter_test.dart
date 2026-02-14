// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// stats_adapter_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/database/adapters/adapters.dart';
import 'package:sanmill/statistics/model/stats_settings.dart';

void main() {
  group('PlayerStatsAdapter', () {
    test('should have the correct typeId', () {
      final PlayerStatsAdapter adapter = PlayerStatsAdapter();
      expect(adapter.typeId, kPlayerStatsTypeId);
      expect(adapter.typeId, 50);
    });
  });

  group('StatsSettingsAdapter', () {
    test('should have the correct typeId', () {
      final StatsSettingsAdapter adapter = StatsSettingsAdapter();
      expect(adapter.typeId, kStatsSettingsTypeId);
      expect(adapter.typeId, 51);
    });
  });

  group('LegacyColorAdapter', () {
    test('should have typeId 6', () {
      final LegacyColorAdapter adapter = LegacyColorAdapter();
      expect(adapter.typeId, 6);
    });
  });

  group('TypeId uniqueness', () {
    test('PlayerStats and StatsSettings should have different typeIds', () {
      expect(kPlayerStatsTypeId, isNot(kStatsSettingsTypeId));
    });

    test('typeIds should be in the high range to avoid collisions', () {
      expect(kPlayerStatsTypeId, greaterThanOrEqualTo(50));
      expect(kStatsSettingsTypeId, greaterThanOrEqualTo(50));
    });
  });
}
