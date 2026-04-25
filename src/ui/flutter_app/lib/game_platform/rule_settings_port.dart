// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

/// Read/write boundary for a game module's rule settings.
///
/// Modules that support configurable rules expose this port so the shared
/// shell (and future cross-game tooling) can access rule state without
/// coupling to a concrete storage implementation.
///
/// ## Migration strategy
///
/// Phase 1 (current): [GameModule.ruleSettingsPort] is optional and Mill's
/// implementation delegates to the existing [SettingsRepository]. Callers
/// inside `lib/games/mill/` should prefer this port over
/// `DB().ruleSettings` in new code.
///
/// Phase 2 (future): Replace `DB().ruleSettings` call sites with this port,
/// introduce per-game Hive box prefixes via [ScopedSettingsRepository], and
/// support multi-game rule isolation.
abstract class RuleSettingsPort<T> {
  /// Returns the current rule settings for the owning module.
  T get ruleSettings;

  /// Persists updated rule settings.
  set ruleSettings(T value);
}
