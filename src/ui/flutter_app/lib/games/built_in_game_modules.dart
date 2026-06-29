// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../game_platform/game_registry.dart';
import 'mill/mill_game_module.dart';

void registerBuiltInGameModules(GameRegistry registry) {
  registry.register(MillGameModule());
}
