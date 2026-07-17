// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n.dart';

void main() {
  test('Simplified Chinese localizes Custom rule-set details', () async {
    final S strings = await S.delegate.load(const Locale('zh'));

    expect(strings.customVariantDescription, '微调任意规则');
    expect(strings.customVariantClosestPreset, '最接近的规则集');
    expect(strings.customVariantDifferenceCount(0), '与此规则集完全一致');
    expect(strings.customVariantDifferenceCount(1), '1 项规则不同');
    expect(strings.customVariantDifferenceCount(2), '2 项规则不同');
    expect(strings.customVariantDifferencesFromPreset('莫里斯九子棋'), '与莫里斯九子棋的差异');
    expect(strings.customVariantCustomizeRules, '自定义规则');
    expect(strings.customVariantCurrentValue('允许飞子'), '当前：允许飞子');
  });
}
