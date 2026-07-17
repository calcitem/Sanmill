// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n.dart';

void main() {
  test(
    'Simplified Chinese localizes analysis settings and semantics',
    () async {
      final S strings = await S.delegate.load(const Locale('zh'));

      expect(strings.analysisSettingsTitle, '分析设置');
      expect(strings.analysisEngineLinesDescription, '在棋盘下方显示引擎变化。');
      expect(strings.analysisBestMoveArrow, '引擎变化标记');
      expect(strings.analysisBestMoveArrowDescription, '在棋盘上标出每条可见引擎变化的首着。');
      expect(strings.analysisEngineLineDisplay(0), '关闭');
      expect(strings.analysisEngineLineDisplay(1), '1 条变化 · 文字和棋盘标记');
      expect(strings.analysisEngineLineDisplay(3), '3 条变化 · 文字和棋盘标记');
      expect(strings.analysisEngineLineSemantics(2), '第 2 条引擎变化');
      expect(strings.analysisDepthSemantics(24), '搜索深度 24');
      expect(strings.analysisEvaluationSemantics('+1.2'), '评估 +1.2');
      expect(strings.analysisPerfectDatabaseShortLabel, '完美数据库');
    },
  );
}
