// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/experience_recording/services/recording_service.dart';
import 'package:sanmill/experience_recording/widgets/recording_indicator.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';

void main() {
  testWidgets('recording badge is an accessible localized button', (
    WidgetTester tester,
  ) async {
    final RecordingService service = RecordingService();
    final bool previousRecording = service.isRecordingNotifier.value;
    final int previousCount = service.eventCountNotifier.value;
    addTearDown(() {
      service.isRecordingNotifier.value = previousRecording;
      service.eventCountNotifier.value = previousCount;
    });
    service.isRecordingNotifier.value = true;
    service.eventCountNotifier.value = 2;

    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: sanmillLocalizationsDelegates,
        supportedLocales: S.supportedLocales,
        locale: Locale('en'),
        home: Center(child: RecordingIndicator()),
      ),
    );
    await tester.pump();

    final Finder badge = find.bySemanticsLabel('Recording · 2 events');
    expect(badge, findsOneWidget);
    final SemanticsData data = tester.getSemantics(badge).getSemanticsData();
    expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  });
}
