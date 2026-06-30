// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';

import 'game_id.dart';

/// Optional naming for Hive / keys; [Hive] typeId values must be frozen in code
/// and must not be reshuffled. Legacy Mill models already use low typeIds; new
/// games get new ids from an unoccupied high range.
@immutable
class GamePersistenceScope {
  const GamePersistenceScope({
    required this.gameId,
    this.hiveTypeIdMin,
    this.hiveTypeIdMax,
    this.migrationVersion = 0,
  });

  final GameId gameId;
  final int? hiveTypeIdMin;
  final int? hiveTypeIdMax;
  final int migrationVersion;

  bool ownsHiveTypeId(int typeId) {
    final int? min = hiveTypeIdMin;
    final int? max = hiveTypeIdMax;
    if (min == null || max == null) {
      return false;
    }
    return min <= typeId && typeId <= max;
  }
}
