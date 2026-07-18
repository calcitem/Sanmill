// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n.dart';

void main() {
  test('Simplified Chinese localizes Opening Book Studio sides', () async {
    final S strings = await S.delegate.load(const Locale('zh'));

    expect(strings.openingBookStudioWhite, '先手方');
    expect(strings.openingBookStudioBlack, '后手方');
    expect(strings.openingBookStudioBothSides, '双方');
    expect(strings.openingBookStudioEqual, '均势');
  });

  test('Simplified Chinese localizes Opening Explorer source states', () async {
    final S strings = await S.delegate.load(const Locale('zh'));

    expect(strings.openingExplorerSourceMoveCount(8), '8 种着法');
    expect(strings.openingExplorerSourceOff, '已关闭');
  });
}
