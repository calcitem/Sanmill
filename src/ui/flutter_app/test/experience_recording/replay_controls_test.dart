// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/experience_recording/services/replay_service.dart';
import 'package:sanmill/experience_recording/widgets/replay_controls.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';

void main() {
  testWidgets('replay controls expose localized actions and progress', (
    WidgetTester tester,
  ) async {
    final ReplayService service = ReplayService();
    final ReplayState previousState = service.stateNotifier.value;
    final int previousProgress = service.progressNotifier.value;
    final int previousTotal = service.totalEventsNotifier.value;
    final ReplaySpeed previousSpeed = service.speedNotifier.value;
    final String? previousDivergence = service.divergenceNotifier.value;
    addTearDown(() {
      service.stateNotifier.value = previousState;
      service.progressNotifier.value = previousProgress;
      service.totalEventsNotifier.value = previousTotal;
      service.speedNotifier.value = previousSpeed;
      service.divergenceNotifier.value = previousDivergence;
    });

    service.stateNotifier.value = ReplayState.paused;
    service.progressNotifier.value = 1;
    service.totalEventsNotifier.value = 4;
    service.speedNotifier.value = ReplaySpeed.x2;
    service.divergenceNotifier.value = null;

    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: sanmillLocalizationsDelegates,
        supportedLocales: S.supportedLocales,
        locale: Locale('en'),
        home: Scaffold(body: Center(child: ReplayControls())),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('Resume'), findsOneWidget);
    expect(find.bySemanticsLabel('Step forward'), findsOneWidget);
    expect(find.bySemanticsLabel('Stop'), findsOneWidget);
    expect(find.bySemanticsLabel('Replay speed: 2×'), findsOneWidget);
    expect(find.bySemanticsLabel('Replay event 2 of 4'), findsOneWidget);
    semantics.dispose();
  });
}
