// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

/// How the user moved between shell routes (drawer vs back stack).
enum ShellRouteNavigationSource {
  /// User selected a route from the drawer (may show confirm dialogs).
  drawer,

  /// In-app route stack pop (e.g. Android back). Skips Mill LAN first-entry flow.
  backStack,
}
