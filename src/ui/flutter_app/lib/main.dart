// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/widgets.dart';

import 'app.dart';
import 'online_play/online_play_contribution.dart';

export 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  OnlinePlayContribution.initializeDeepLinks();
  await runSanmillApp(
    playModeContributions: const <OnlinePlayContribution>[
      OnlinePlayContribution(),
    ],
  );
}
