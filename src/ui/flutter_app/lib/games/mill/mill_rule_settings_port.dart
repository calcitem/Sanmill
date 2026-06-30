// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_platform/rule_settings_port.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../shared/database/settings_repository.dart';
import '../../src/rust/api/simple.dart' as tgf;
import 'mill_variant_options_mapper.dart';

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

  /// Typed Rust/FRB variant options for the currently supported subset of
  /// Mill rule settings, including the engine-behavior toggles (mobility,
  /// blocking-paths) carried by `GeneralSettings`.
  tgf.MillVariantOptions get tgfVariantOptions => ruleSettings
      .toTgfMillVariantOptions(generalSettings: _repository.generalSettings);
}
