// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n.dart';

void main() {
  test('Simplified Chinese localizes appearance theme labels', () async {
    final S strings = await S.delegate.load(const Locale('zh'));

    expect(strings.boardTheme, '棋盘主题');
    expect(strings.themeMode, '主题模式');
    expect(strings.system, '跟随系统');
    expect(strings.animationDurationValue(0), '关闭');
    expect(strings.animationDurationValue(1), '1 秒');
    expect(strings.animationDurationValue(1.5), '1.5 秒');
    expect(strings.backgroundImageOption(2), '背景图片 2');
    expect(strings.boardImageOption(3), '棋盘图片 3');
    expect(strings.boardImageDescription, '选择用于棋盘表面的图片。');
    expect(strings.backgroundImageDescription, '选择用于对局区域背景的图片。');
    expect(strings.boardColors, '棋盘颜色');
    expect(strings.pieceColors, '棋子颜色');
    expect(strings.interfaceColors, '界面颜色');
    expect(strings.customBackgroundImage, '自定义背景图片');
    expect(strings.customBoardImage, '自定义棋盘图片');
    expect(strings.transparentToolbars, '透明工具栏');
    expect(strings.pieceEffectName('RippleGradient'), '渐变涟漪');
    expect(strings.pieceEffectName('FireTrail'), '火焰拖尾');
    expect(strings.pieceEffectName('Unknown'), 'Unknown');
    expect(strings.fontSizePreview, '示例文字 123');
    expect(strings.showLegalMovesDescription, '仅在走子或飞子阶段选中棋子后显示合法目的地。');
  });
}
