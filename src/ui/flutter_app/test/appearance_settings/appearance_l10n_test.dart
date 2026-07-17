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
  });
}
