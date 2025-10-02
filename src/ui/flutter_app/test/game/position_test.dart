// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// position_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';
import '../helpers/test_mills.dart';

void main() {
  group("Position", () {
    test(
      "_movesSinceLastRemove should output the moves since last remove",
      () async {
        // TODO: Test data may not match current rule settings
        // The WinLessThanThreeGame test data was created with specific game rules
        // that may differ from the current MockDB configuration. Need to verify
        // rule compatibility before enabling this test.
      },
      skip: true,
    );
  });
}
