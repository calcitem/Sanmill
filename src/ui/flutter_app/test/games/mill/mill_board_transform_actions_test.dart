// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/transform/transform.dart';
import 'package:sanmill/games/mill/mill_board_transform_actions.dart';

void main() {
  test('board transform actions remain the setup toolbar generators', () {
    final Set<String> ids = millBoardTransformActions
        .map((MillBoardTransformAction action) => action.id)
        .toSet();
    final Set<TransformationType> types = millBoardTransformActions
        .map((MillBoardTransformAction action) => action.type)
        .toSet();

    expect(millBoardTransformActions, hasLength(4));
    expect(ids, hasLength(millBoardTransformActions.length));
    expect(types, hasLength(millBoardTransformActions.length));
    expect(
      millBoardTransformActions.map(
        (MillBoardTransformAction action) => action.type,
      ),
      <TransformationType>[
        TransformationType.rotate90,
        TransformationType.mirrorHorizontal,
        TransformationType.mirrorVertical,
        TransformationType.swap,
      ],
    );
  });
}
