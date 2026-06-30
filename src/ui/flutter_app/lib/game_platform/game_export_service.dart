// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// ignore_for_file: avoid_classes_with_only_static_members

import 'package:flutter/widgets.dart';

import 'game_export.dart';
import 'game_module.dart';
import 'game_registry.dart';
import 'game_session.dart';
import 'notation_port.dart';

/// Cross-game export coordinator.
///
/// The first consumer is the legacy Mill UI: it prefers module-owned
/// [NotationPort] exports but can safely fall back to the old export path.
abstract final class GameExportService {
  /// Builds an export text for the currently selected game module.
  ///
  /// Returns `null` when export is not supported by the active module or when
  /// the module did not provide export data for the given [session].
  static String? buildCurrentExportText(
    BuildContext context, {
    required GameSession session,
  }) {
    final GameModule module = GameRegistry.instance.current;
    final GameExportData? data = module.buildExportData(
      context,
      session: session,
    );
    final NotationPort? port = module.notationPort;
    if (data == null || port == null) {
      return null;
    }
    return port.exportGame(data.snapshot, data.actions);
  }
}
