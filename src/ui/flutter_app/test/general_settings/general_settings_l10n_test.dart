// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n.dart';

void main() {
  test('English localizes diagnostic log selection counts', () async {
    final S strings = await S.delegate.load(const Locale('en'));

    expect(strings.logsSelectionSummary(1, 1), '1 log selected · 1 range');
    expect(strings.logsSelectionSummary(3, 2), '3 logs selected · 2 ranges');
  });

  test(
    'Simplified Chinese localizes first move, tips, and thinking-time values',
    () async {
      final S strings = await S.delegate.load(const Locale('zh'));

      expect(strings.humanMovesFirst, '真人先手');
      expect(strings.aiThinkingTimeValue(0), '不限时');
      expect(strings.aiThinkingTimeValue(1), '1 秒');
      expect(strings.aiThinkingTimeValue(6), '6 秒');
      expect(strings.showGameTips, '显示对局提示');
      expect(strings.showGameTips_Detail, '在当前行棋方旁显示行棋提示和开局信息。');
      expect(
        strings.llmAssistedDevelopmentDescription,
        '描述要完成的任务，以生成可直接分享的提示词。若剪贴板中含有 Sanmill 日志，将附上相关片段。',
      );
      expect(strings.copyPrompt, '复制提示词');
      expect(strings.rename, '重命名');
    },
  );
}
