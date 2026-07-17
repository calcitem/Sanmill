// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/experience_recording/models/recording_models.dart';
import 'package:sanmill/experience_recording/pages/session_list_page.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';

void main() {
  testWidgets('known recording notes are localized and custom notes survive', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: sanmillLocalizationsDelegates,
        supportedLocales: S.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (BuildContext context) {
            final S strings = S.of(context);
            return SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  for (final String note in <String>[
                    RecordingSessionNotes.eventLimitReached,
                    RecordingSessionNotes.typedEventLimitReached,
                    RecordingSessionNotes.recordingInProgress,
                    RecordingSessionNotes.replayStarted,
                    RecordingSessionNotes.diagnosticReplayStarted,
                    RecordingSessionNotes.diagnosticReplayValidated,
                    'My imported note',
                  ])
                    Text(recordingSessionNoteText(strings, note)),
                ],
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('Recording stopped: event limit reached'), findsOneWidget);
    expect(
      find.text('Recording stopped: detailed-event limit reached'),
      findsOneWidget,
    );
    expect(
      find.text('Partial recording: recording still in progress'),
      findsOneWidget,
    );
    expect(find.text('Recording stopped when replay started'), findsOneWidget);
    expect(
      find.text('Recording stopped when diagnostic replay started'),
      findsOneWidget,
    );
    expect(find.text('Diagnostic bundle v1 replay validated'), findsOneWidget);
    expect(find.text('My imported note'), findsOneWidget);
  });
}
