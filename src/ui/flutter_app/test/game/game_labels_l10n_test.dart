// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n.dart';

void main() {
  test('Simplified Chinese localizes game labels and tutorials', () async {
    final S strings = await S.delegate.load(const Locale('zh'));

    expect(strings.eloRating(2800), '等级分：2800');
    expect(strings.engineLineCount(1), '1 条变化');
    expect(strings.engineLineCount(3), '3 条变化');
    expect(strings.gameDurationMinutesSeconds(3, 42), '对局时长：3 分 42 秒');
    expect(strings.generatedFen, '生成的 FEN');
    expect(strings.moveListLayoutDetails, '着法详情');
    expect(strings.moveListLayoutLargeBoards, '大棋盘');
    expect(strings.moveListLayoutMediumBoards, '中棋盘');
    expect(strings.moveListLayoutSmallBoards, '小棋盘');
    expect(strings.moveListLayoutTable, '着法表');
    expect(strings.remoteHistoryNavigationUnavailable, '联网对局仅可申请悔回自己最近的一步。');
    expect(strings.restoreDefaultSettingsConfirmation, '这会用默认值替换所有当前设置，且无法撤销。');
    expect(strings.shellBackToMainGame, '返回主对局');
    expect(strings.statisticsOverallRecord, '总计');
    expect(
      strings.tutorialMillCaptureRule,
      '形成三连后，可以吃掉对方一枚棋子。只要对方还有不在三连中的棋子，三连中的棋子通常不能被吃。',
    );
    expect(strings.tutorialFlyingRule, '启用飞子后，当一方棋子达到设定数量时，其任一棋子均可移动到任意空点。');
    expect(strings.tutorialUnplacedPieceCounter, '棋盘中央显示还可摆放的棋子数量。');
  });
}
