// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/transform/transform.dart';
import 'package:sanmill/games/mill/mill_board_transform_actions.dart';

void main() {
  test('full board transform actions expose all visible symmetries', () {
    final Set<String> ids = millBoardTransformFullActions
        .map((MillBoardTransformAction action) => action.id)
        .toSet();
    final Set<TransformationType> types = millBoardTransformFullActions
        .map((MillBoardTransformAction action) => action.type)
        .toSet();

    expect(millBoardTransformFullActions, hasLength(15));
    expect(ids, hasLength(millBoardTransformFullActions.length));
    expect(types, hasLength(millBoardTransformFullActions.length));
    expect(types, isNot(contains(TransformationType.identity)));
    expect(
      types,
      equals(
        TransformationType.values
            .where(
              (TransformationType type) => type != TransformationType.identity,
            )
            .toSet(),
      ),
    );
  });

  test('quick board transform actions remain the setup toolbar generators', () {
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
