// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_registry.dart';
import 'package:sanmill/games/demo_probe/demo_probe_game_module.dart';
import 'package:sanmill/games/mill/mill_game_module.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/database/settings_repositories.dart';
import 'package:sanmill/shared/database/settings_repository.dart';

import '../../helpers/mocks/mock_database.dart';

void main() {
  group('SettingsRepositories', () {
    late MockDB mockDB;

    setUp(() {
      mockDB = MockDB();
      DB.instance = mockDB;
      GameRegistry.instance.resetForTesting();
      GameRegistry.instance
        ..register(MillGameModule())
        ..register(DemoProbeGameModule());
      GameRegistry.instance.select(GameId.mill);
      SettingsRepositories.instance.init(
        repository: DatabaseSettingsRepository(DB()),
      );
    });

    tearDown(() {
      SettingsRepositories.instance.resetForTesting();
      GameRegistry.instance.resetForTesting();
      DB.instance = null;
    });

    test('uses the current game persistence scope', () {
      expect(SettingsRepositories.instance.current.boxPrefix, 'game.mill.');
    });

    test('updates the current port when the selected game changes', () {
      expect(SettingsRepositories.instance.current.boxPrefix, 'game.mill.');

      GameRegistry.instance.select(GameId.demoProbe);

      expect(
        SettingsRepositories.instance.current.boxPrefix,
        'game.demo_probe.',
      );
    });

    test('exposes the configured settings repository', () {
      final SettingsRepository repository =
          SettingsRepositories.instance.current.repository;

      repository.generalSettings = const GeneralSettings(aiIsLazy: true);

      expect(mockDB.generalSettings.aiIsLazy, isTrue);
    });
  });
}
