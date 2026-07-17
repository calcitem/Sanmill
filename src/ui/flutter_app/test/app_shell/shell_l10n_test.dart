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
  });

  test('Simplified Chinese uses step-based navigation labels', () async {
    final S strings = await S.delegate.load(const Locale('zh'));

    expect(strings.previous, '上一步');
    expect(strings.next, '下一步');
  });
}
