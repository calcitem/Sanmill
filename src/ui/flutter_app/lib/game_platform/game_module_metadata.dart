// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';

import 'game_id.dart';

@immutable
class GameModuleMetadata {
  const GameModuleMetadata({
    required this.id,
    required this.shortLabel,
    this.showInGamePicker = true,
  });

  final GameId id;
  final String shortLabel;
  final bool showInGamePicker;
}
