// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/widgets.dart';

import '../game_platform/game_session.dart';

/// Inherited widget that exposes the active [GameSession] to descendants.
///
/// The shell ([Home] or [GameSurfaceHost]) owns the session lifecycle and
/// rebuilds the scope when the active game changes. UI code that needs
/// session-level state should read [GameSessionScope.maybeOf] rather than
/// constructing or addressing a session directly.
class GameSessionScope extends InheritedWidget {
  const GameSessionScope({
    required this.session,
    required super.child,
    super.key,
  });

  final GameSession session;

  static GameSessionScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<GameSessionScope>();
  }

  static GameSession? sessionOf(BuildContext context) {
    return maybeOf(context)?.session;
  }

  @override
  bool updateShouldNotify(covariant GameSessionScope oldWidget) {
    return !identical(oldWidget.session, session);
  }
}
