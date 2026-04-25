// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../game_platform/game_id.dart';
import '../game_platform/game_registry.dart';

/// Generic host for a non-Mill game surface.
class GameSurfaceHost extends StatelessWidget {
  const GameSurfaceHost({
    required this.gameId,
    required this.onClose,
    super.key,
  });

  final GameId gameId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final GameRegistry registry = GameRegistry.instance;
    final String title = registry.getModule(gameId)?.metadata.shortLabel ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: onClose),
      ),
      body:
          registry.getModule(gameId)?.buildGameSurface(context) ??
          const SizedBox.shrink(),
    );
  }
}
