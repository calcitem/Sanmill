// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/appearance_settings/models/color_settings.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/database/settings_repository.dart';

import '../../helpers/mocks/mock_database.dart';

void main() {
  group('DatabaseSettingsRepository', () {
    late MockDB mockDB;
    late DatabaseSettingsRepository repository;

    setUp(() {
      mockDB = MockDB();
      DB.instance = mockDB;
      repository = DatabaseSettingsRepository(DB());
    });

    tearDown(() {
      DB.instance = null;
    });

    test('delegates general settings reads and writes to Database', () {
      repository.generalSettings = const GeneralSettings(aiIsLazy: true);

      expect(mockDB.generalSettings.aiIsLazy, isTrue);
      expect(repository.generalSettings.aiIsLazy, isTrue);
    });

    test('delegates rule settings reads and writes to Database', () {
      repository.ruleSettings = const RuleSettings(piecesCount: 12);

      expect(mockDB.ruleSettings.piecesCount, 12);
      expect(repository.ruleSettings.piecesCount, 12);
    });

    test('delegates display settings reads and writes to Database', () {
      repository.displaySettings = const DisplaySettings(fontScale: 1.2);

      expect(mockDB.displaySettings.fontScale, 1.2);
      expect(repository.displaySettings.fontScale, 1.2);
    });

    test('delegates color settings reads and writes to Database', () {
      repository.colorSettings = const ColorSettings();

      expect(repository.colorSettings, mockDB.colorSettings);
    });
  });
}
