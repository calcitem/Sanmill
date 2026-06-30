// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../game_id.dart';

/// Whether a setting belongs to the cross-game application shell or to a
/// specific game module.
///
/// Today, all settings live in shared boxes for backward compatibility with
/// existing Mill data. New code should still pick a category so that, when
/// per-game persistence rolls out, the migration can be done category by
/// category without touching call sites.
enum PersistenceScopeCategory {
  /// Cross-game user preferences (theme, locale, accessibility).
  app,

  /// Game-specific configuration (rule variant, recent positions, …).
  game,
}

/// Legacy Mill [Hive] typeIds are already allocated in model files (roughly
/// 0–13 and 30–38). New games must use unallocated high ranges; do not
/// reshuffle existing ids.
///
/// Box name pattern: `app.<scope>` for cross-game data, `game.<id>.<scope>`
/// for per-game data (future migration).
String? scopePrefixFor(GameId? id) {
  if (id == null) {
    return null;
  }
  return 'game.${id.value}.';
}

/// Returns the canonical box-name prefix for a given category.
///
/// `category=app` always yields `app.`, regardless of the active game id.
/// `category=game` yields `game.<id>.` when [id] is provided, or `null` when
/// the active game id is unknown.
String? scopePrefixFromCategory(PersistenceScopeCategory category, GameId? id) {
  switch (category) {
    case PersistenceScopeCategory.app:
      return 'app.';
    case PersistenceScopeCategory.game:
      return scopePrefixFor(id);
  }
}

/// Default app-scoped settings categories. Mirrors today's shared Hive boxes;
/// kept here so future migration can flip them to namespaced boxes en masse.
const Set<String> kAppScopedSettings = <String>{
  'general_settings',
  'appearance',
  'color',
  'display',
  'tutorial',
};

/// Default game-scoped settings categories. Mirrors today's shared Hive boxes
/// that a per-game migration would split first.
const Set<String> kGameScopedSettings = <String>{
  'rule_settings',
  'statistics',
  'experience_recordings',
  'puzzle_progress',
};
