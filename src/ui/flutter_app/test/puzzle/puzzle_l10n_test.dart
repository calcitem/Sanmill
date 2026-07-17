// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n.dart';

void main() {
  test('Simplified Chinese localizes puzzle progress and actions', () async {
    final S strings = await S.delegate.load(const Locale('zh'));

    expect(strings.puzzleCompletionProgress('0.0'), '已完成 0.0%');
    expect(strings.puzzleCompletionProgress('42.5'), '已完成 42.5%');
    expect(strings.cancelPuzzleSelection, '取消选择');
    expect(strings.puzzleSolutionActionCount(1), '1 个原子动作');
    expect(strings.puzzleSolutionActionCount(3), '3 个原子动作');
    expect(strings.puzzleStatsCurrentRating, '当前等级分');
    expect(strings.puzzleStreakQuitTitle, '退出连续解谜？');
    expect(strings.puzzlesExportedForContribution(1), '已导出 1 个谜题以供贡献');
    expect(strings.puzzlesExportedForContribution(3), '已导出 3 个谜题以供贡献');
    expect(strings.viewContributionGuide, '查看指南');
  });
}
