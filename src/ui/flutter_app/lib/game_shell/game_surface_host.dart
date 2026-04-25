// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../game_platform/game_id.dart';
import '../game_platform/game_menu.dart';
import '../game_platform/game_module.dart';
import '../game_platform/game_registry.dart';
import '../game_platform/game_session.dart';
import 'game_session_scope.dart';

/// Optional compact scaffold for embedding a [GameId] (e.g. game picker, tests).
/// The main app uses [Home] with [SharedGameShell] and [GameModule] hooks.
///
/// Two ownership modes:
///
/// * If [externalSession] is non-null, [GameSurfaceHost] is a thin wrapper:
///   it uses the provided session, never disposes it, and exposes it via
///   [GameSessionScope]. The shell ([Home]) is the owner.
/// * Otherwise, [GameSurfaceHost] creates the session via
///   [GameModule.startSession], owns its lifecycle, and disposes it on
///   widget teardown or [gameId]/[routeId] change.
class GameSurfaceHost extends StatefulWidget {
  const GameSurfaceHost({
    required this.gameId,
    this.routeId,
    this.externalSession,
    this.onClose,
    super.key,
  });

  final GameId gameId;
  final String? routeId;
  final GameSession? externalSession;
  final VoidCallback? onClose;

  @override
  State<GameSurfaceHost> createState() => _GameSurfaceHostState();
}

class _GameSurfaceHostState extends State<GameSurfaceHost> {
  GameSession? _ownedSession;

  GameSession get _session => widget.externalSession ?? _ownedSession!;

  @override
  void initState() {
    super.initState();
    if (widget.externalSession == null) {
      _ownedSession = _startSession();
    }
  }

  @override
  void didUpdateWidget(covariant GameSurfaceHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool ownershipFlipped =
        (oldWidget.externalSession == null) != (widget.externalSession == null);
    final bool reset =
        oldWidget.gameId != widget.gameId ||
        oldWidget.routeId != widget.routeId;
    if (ownershipFlipped) {
      _ownedSession?.dispose();
      _ownedSession = widget.externalSession == null ? _startSession() : null;
    } else if (reset && widget.externalSession == null) {
      _ownedSession?.dispose();
      _ownedSession = _startSession();
    }
  }

  @override
  void dispose() {
    _ownedSession?.dispose();
    _ownedSession = null;
    super.dispose();
  }

  GameSession _startSession() {
    final GameRegistry registry = GameRegistry.instance;
    final GameModule? module = registry.getModule(widget.gameId);
    assert(module != null, 'No GameModule registered for ${widget.gameId}.');
    return module!.startSession();
  }

  @override
  Widget build(BuildContext context) {
    final GameRegistry registry = GameRegistry.instance;
    final GameModule? module = registry.getModule(widget.gameId);
    assert(module != null, 'No GameModule registered for ${widget.gameId}.');
    final GameModeEntry? mode = _findMode(module!.playModes(context));
    final String title = mode?.label ?? module.metadata.shortLabel;
    final Widget surface =
        mode?.builder(context, key: mode.contentKey, session: _session) ??
        module.buildGameSurface(context, session: _session);

    return GameSessionScope(
      session: _session,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: widget.onClose == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                ),
        ),
        body: surface,
      ),
    );
  }

  GameModeEntry? _findMode(List<GameModeEntry> modes) {
    if (widget.routeId == null) {
      return modes.isEmpty ? null : modes.first;
    }
    for (final GameModeEntry mode in modes) {
      if (mode.id == widget.routeId) {
        return mode;
      }
    }
    return null;
  }
}
