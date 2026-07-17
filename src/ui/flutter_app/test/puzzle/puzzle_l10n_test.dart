// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n.dart';

void main() {
  test('Simplified Chinese localizes puzzle completion progress', () async {
    final S strings = await S.delegate.load(const Locale('zh'));

    expect(strings.puzzleCompletionProgress('0.0'), '已完成 0.0%');
    expect(strings.puzzleCompletionProgress('42.5'), '已完成 42.5%');
  });
}
