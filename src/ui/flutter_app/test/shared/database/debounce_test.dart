// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';
import 'package:sanmill/experience_recording/models/recording_models.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/settings_side_effect_coordinator.dart';

void main() {
  group('SettingsSideEffectCoordinator', () {
    late int generalEngineUpdates;
    late int ruleEngineUpdates;
    late List<Map<String, dynamic>> recordedData;
    late SettingsSideEffectCoordinator coordinator;

    setUp(() {
      generalEngineUpdates = 0;
      ruleEngineUpdates = 0;
      recordedData = <Map<String, dynamic>>[];
      coordinator = SettingsSideEffectCoordinator(
        engineOptionsDebounceDuration: const Duration(milliseconds: 10),
        updateGeneralEngineOptions: () {
          generalEngineUpdates++;
        },
        updateRuleEngineOptions: () {
          ruleEngineUpdates++;
        },
        recordEvent: (RecordingEventType type, Map<String, dynamic> data) {
          recordedData.add(<String, dynamic>{'type': type, 'data': data});
        },
      );
    });

    tearDown(() {
      coordinator.dispose();
    });

    test('debounces rapid general settings engine updates', () async {
      for (int i = 0; i < 10; i++) {
        coordinator.onGeneralSettingsSaved(const GeneralSettings());
      }

      expect(generalEngineUpdates, 0);

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(generalEngineUpdates, 1);
      expect(ruleEngineUpdates, 0);
    });

    test(
      'debounces rapid rule settings engine updates independently',
      () async {
        for (int i = 0; i < 10; i++) {
          coordinator.onRuleSettingsPersisted();
        }

        expect(ruleEngineUpdates, 0);

        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(ruleEngineUpdates, 1);
        expect(generalEngineUpdates, 0);
      },
    );

    test('records privacy-reviewed settings change payloads', () {
      coordinator.onGeneralSettingsSaved(const GeneralSettings(aiIsLazy: true));
      coordinator.recordRuleSettingsChange(const RuleSettings(piecesCount: 12));
      coordinator.onDisplaySettingsSaved(const DisplaySettings(fontScale: 1.2));

      expect(recordedData, hasLength(3));
      expect(
        recordedData.map(
          (Map<String, dynamic> event) =>
              (event['data'] as Map<String, dynamic>)['category'],
        ),
        <String>['general', 'rule', 'display'],
      );
      expect(
        recordedData.map((Map<String, dynamic> event) => event['type']),
        everyElement(RecordingEventType.settingsChange),
      );
      expect(
        recordedData.map(
          (Map<String, dynamic> event) =>
              (event['data'] as Map<String, dynamic>)['settingId'],
        ),
        everyElement('initialSnapshotChanged'),
      );
      expect(
        recordedData.map(
          (Map<String, dynamic> event) => event['data'] as Map<String, dynamic>,
        ),
        everyElement(isNot(contains('settings'))),
      );
    });

    test('records only changed field id and safe old/new values', () {
      coordinator.onGeneralSettingsSaved(const GeneralSettings(skillLevel: 1));
      recordedData.clear();

      coordinator.onGeneralSettingsSaved(const GeneralSettings(skillLevel: 5));

      expect(recordedData, hasLength(1));
      expect(recordedData.single['data'], <String, dynamic>{
        'category': 'general',
        'settingId': 'SkillLevel',
        'oldValue': 1,
        'newValue': 5,
      });
    });
  });
}
