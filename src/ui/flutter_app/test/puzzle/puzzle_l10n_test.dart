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
    expect(strings.allPuzzles, '解谜');
    expect(strings.allPuzzlesDesc, '从所有可用谜题中选择');
    expect(strings.customPuzzles, '谜题编辑器');
    expect(strings.customPuzzlesDesc, '创建、导入和管理谜题');
    expect(strings.noCustomPuzzles, '暂无谜题');
    expect(strings.noCustomPuzzlesHint, '创建或导入谜题，练习特定局面');
    expect(strings.puzzleSolutionActionCount(1), '1 个原子动作');
    expect(strings.puzzleSolutionActionCount(3), '3 个原子动作');
    expect(strings.puzzleStatsCurrentRating, '当前等级分');
    expect(strings.puzzleStreakQuitTitle, '退出连续解谜？');
    expect(strings.puzzlesExportedForContribution(1), '已导出 1 个谜题以供贡献');
    expect(strings.puzzlesExportedForContribution(3), '已导出 3 个谜题以供贡献');
    expect(strings.viewContributionGuide, '查看指南');
  });

  test('Simplified Chinese describes the puzzle creation workflow', () async {
    final S strings = await S.delegate.load(const Locale('zh'));

    expect(strings.puzzlePositionSnapshotted2, '局面已保存');
    expect(strings.puzzleNoPositionSnapshotted, '尚未保存局面');
    expect(strings.puzzleSnapshotPositionFirst, '请先保存起始局面');
    expect(strings.puzzleOpenBoardSetup, '打开棋盘（设置局面）');
    expect(strings.puzzleOpenBoardPlay, '打开棋盘（行棋）');
    expect(strings.puzzleFailedLoadPosition, '无法加载此局面，请重新保存。');
    expect(strings.puzzleInvalidPositionFormatRecapture, '局面格式无效，请重新保存。');
    expect(strings.puzzleWorkflowStepSetupDesc, '打开棋盘，设置并保存局面。');
    expect(strings.puzzleWorkflowStepRecordDesc, '开始录制，完成着法后停止录制。');
    expect(strings.puzzleWorkflowStepDetailsDesc, '填写标题、类别和难度。');
    expect(strings.puzzleWorkflowStepSaveDesc, '点按“保存”。');
    expect(strings.puzzlePositionSnapshotHelp, '起始局面帮助');
    expect(strings.puzzleSolutionStep1, '先保存起始局面');
    expect(strings.puzzleSolutionStep2, '点按“开始录制”，棋盘会重置到已保存的局面。');
    expect(strings.puzzleSolutionStep4, '返回本页并点按“停止录制”。');
    expect(strings.puzzleShowPositionSnapshotHelp, '显示起始局面帮助');
  });
}
