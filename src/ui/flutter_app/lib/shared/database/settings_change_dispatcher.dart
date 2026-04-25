// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async' show Timer;

import '../../appearance_settings/models/display_settings.dart';
import '../../experience_recording/models/recording_models.dart';
import '../../experience_recording/services/recording_service.dart';
import '../../game_page/services/mill.dart';
import '../../general_settings/models/general_settings.dart';
import '../../rule_settings/models/rule_settings.dart';

/// Coordinates side effects that must happen after settings are persisted.
class SettingsChangeDispatcher {
  SettingsChangeDispatcher._();

  static final SettingsChangeDispatcher instance = SettingsChangeDispatcher._();

  // Debounce engine option updates triggered by rapid settings changes.
  // This is important for stress tests (e.g. Monkey) where sliders/toggles may
  // fire in bursts and would otherwise spam `setoption` calls.
  static const Duration _engineOptionsDebounceDuration = Duration(
    milliseconds: 300,
  );

  Timer? _engineOptionsDebounceTimer;
  Timer? _engineRuleOptionsDebounceTimer;

  void onGeneralSettingsSaved(GeneralSettings generalSettings) {
    _engineOptionsDebounceTimer?.cancel();
    _engineOptionsDebounceTimer = Timer(_engineOptionsDebounceDuration, () {
      GameController().engine.setGeneralOptions();
    });

    RecordingService().recordEvent(
      RecordingEventType.settingsChange,
      <String, dynamic>{
        'category': 'general',
        'settings': generalSettings.toJson(),
      },
    );
  }

  void onRuleSettingsPersisted() {
    _engineRuleOptionsDebounceTimer?.cancel();
    _engineRuleOptionsDebounceTimer = Timer(_engineOptionsDebounceDuration, () {
      GameController().engine.setRuleOptions();
    });
  }

  void recordRuleSettingsChange(RuleSettings ruleSettings) {
    RecordingService().recordEvent(
      RecordingEventType.settingsChange,
      <String, dynamic>{'category': 'rule', 'settings': ruleSettings.toJson()},
    );
  }

  void onDisplaySettingsSaved(DisplaySettings displaySettings) {
    RecordingService().recordEvent(
      RecordingEventType.settingsChange,
      <String, dynamic>{
        'category': 'display',
        'settings': displaySettings.toJson(),
      },
    );
  }
}
