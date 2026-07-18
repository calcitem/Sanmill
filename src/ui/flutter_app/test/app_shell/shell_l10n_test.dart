// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n.dart';

void main() {
  test('Simplified Chinese localizes More tools and shell tabs', () async {
    final S strings = await S.delegate.load(const Locale('zh'));

    expect(strings.tools, '工具');
    expect(strings.home, '首页');
    expect(strings.learn, '学习');
    expect(strings.todayProgress, '今天');
    expect(strings.todayProgressSummary(2, 1), '完成 2 局 · 复盘 1 份');
    expect(strings.recentGames, '最近保存的棋局');
  });

  test('Simplified Chinese uses step-based navigation labels', () async {
    final S strings = await S.delegate.load(const Locale('zh'));

    expect(strings.previous, '上一步');
    expect(strings.next, '下一步');
  });

  test('Simplified Chinese localizes Learn section labels', () async {
    final S strings = await S.delegate.load(const Locale('zh'));

    expect(strings.practice, '练习');
    expect(strings.guides, '指南');
    expect(strings.millBasicsDescription, '逐步学习基础玩法');
    expect(strings.howToPlayDescription, '阅读完整规则');
    expect(strings.coordinateTrainingStandardOrientation, '标准');
    expect(strings.coordinateTrainingCurrentTarget('d4'), '当前目标：d4');
    expect(strings.coordinateTrainingNextTarget('g7'), '下一个目标：g7');
  });
}
