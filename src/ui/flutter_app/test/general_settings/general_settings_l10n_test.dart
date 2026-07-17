// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n.dart';

void main() {
  test(
    'Simplified Chinese localizes first move and thinking-time values',
    () async {
      final S strings = await S.delegate.load(const Locale('zh'));

      expect(strings.humanMovesFirst, '真人先手');
      expect(strings.aiThinkingTimeValue(0), '不限时');
      expect(strings.aiThinkingTimeValue(1), '1 秒');
      expect(strings.aiThinkingTimeValue(6), '6 秒');
    },
  );
}
