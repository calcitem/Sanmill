// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_platform/rule_settings_port.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../shared/database/settings_repository.dart';

/// Mill-specific [RuleSettingsPort] backed by the existing
/// [SettingsRepository].
///
/// Delegates persistence to the repository, keeping the storage location
/// centralized. New Mill code should access rule settings through this port
/// instead of `DB().ruleSettings` directly.
class MillRuleSettingsPort implements RuleSettingsPort<RuleSettings> {
  const MillRuleSettingsPort(this._repository);

  final SettingsRepository _repository;

  @override
  RuleSettings get ruleSettings => _repository.ruleSettings;

  @override
  set ruleSettings(RuleSettings value) => _repository.ruleSettings = value;
}
