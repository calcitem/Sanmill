// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../appearance_settings/models/display_settings.dart';
import '../../general_settings/models/general_settings.dart';
import '../../rule_settings/models/rule_settings.dart';
import 'settings_side_effect_coordinator.dart';

/// Compatibility entry point for settings persistence side effects.
class SettingsChangeDispatcher {
  SettingsChangeDispatcher._({SettingsSideEffectCoordinator? coordinator})
    : _coordinator = coordinator ?? SettingsSideEffectCoordinator.instance;

  static final SettingsChangeDispatcher instance = SettingsChangeDispatcher._();

  final SettingsSideEffectCoordinator _coordinator;

  void onGeneralSettingsSaved(GeneralSettings generalSettings) {
    _coordinator.onGeneralSettingsSaved(generalSettings);
  }

  void onRuleSettingsPersisted() {
    _coordinator.onRuleSettingsPersisted();
  }

  void recordRuleSettingsChange(RuleSettings ruleSettings) {
    _coordinator.recordRuleSettingsChange(ruleSettings);
  }

  void onDisplaySettingsSaved(DisplaySettings displaySettings) {
    _coordinator.onDisplaySettingsSaved(displaySettings);
  }
}
