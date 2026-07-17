// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';

void main() {
  test(
    'localizes canonical PGN player pairs without changing custom names',
    () async {
      final S strings = await S.delegate.load(const Locale('zh'));

      expect(
        localizedGamePlayersSummary(strings, white: 'Human', black: 'Human'),
        strings.humanVsHuman,
      );
      expect(
        localizedGamePlayersSummary(strings, white: 'Human', black: 'AI'),
        strings.humanVsAi,
      );
      expect(
        localizedGamePlayersSummary(strings, white: 'Computer', black: 'AI'),
        strings.aiVsAi,
      );
      expect(
        localizedGamePlayersSummary(strings, white: 'Alice', black: 'Bob'),
        'Alice – Bob',
      );
    },
  );
}
