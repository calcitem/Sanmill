// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n.dart';

void main() {
  test('Simplified Chinese localizes rule preset and flying labels', () async {
    final S strings = await S.delegate.load(const Locale('zh'));

    expect(strings.rulePreset, '预设');
    expect(strings.chooseRulePreset, '选择预设');
    expect(strings.allowFlying, '允许飞子');
  });

  test('Simplified Chinese uses capture wording for opposing pieces', () async {
    final S strings = await S.delegate.load(const Locale('zh'));

    expect(strings.sideToMoveRemovePiece, '进入走子阶段前，先行方吃掉对方一枚棋子。');
    expect(strings.takeOpponentsPiece, '吃掉对方一枚棋子。');
    expect(strings.firstAndSecondPlayerRemovePiece, '先手方、后手方依次吃掉对方一枚棋子。');
    expect(strings.secondAndFirstPlayerRemovePiece, '后手方、先手方依次吃掉对方一枚棋子。');
    expect(strings.removeOpponentsPieceAndMakeNextMove, '吃掉对方一枚棋子，然后继续行棋。');
    expect(
      strings.removeOpponentsPieceAndChangeSideToMove,
      '吃掉对方一枚棋子，然后轮到对方行棋。',
    );
    expect(strings.bothPlayersRemoveOpponentsPiece, '双方各吃掉对方一枚相邻的棋子，然后继续对局。');
    expect(strings.tipCanNotRemoveNonadjacent, '只能吃掉与己方棋子相邻的对方棋子。');
    expect(
      strings.stalemateRemovalRegardlessOfMillFormation,
      '无子可走时，可以吃掉与己方棋子相邻的对方棋子，不论它是否在三连中。',
    );
  });
}
