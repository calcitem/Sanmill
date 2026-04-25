// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../game_platform/game_module.dart';
import '../game_platform/game_registry.dart';

class GamePickerPage extends StatelessWidget {
  const GamePickerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final GameRegistry registry = GameRegistry.instance;
    final List<GameModule> modules = registry.registeredModules
        .where((GameModule module) => module.metadata.showInGamePicker)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Games')),
      body: ListView.builder(
        itemCount: modules.length,
        itemBuilder: (BuildContext context, int index) {
          final GameModule module = modules[index];
          return ListTile(
            title: Text(module.metadata.shortLabel),
            selected: module.metadata.id == registry.currentId,
            onTap: () {
              registry.select(module.metadata.id);
              Navigator.of(context).pop();
            },
          );
        },
      ),
    );
  }
}
