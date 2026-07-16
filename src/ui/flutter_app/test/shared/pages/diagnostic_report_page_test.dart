// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sanmill/experience_recording/models/user_action_event.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/models/diagnostic_bundle.dart';
import 'package:sanmill/shared/pages/diagnostic_report_page.dart';
import 'package:sanmill/shared/services/diagnostic_bundle_codec.dart';
import 'package:sanmill/shared/services/diagnostic_report_service.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';

void main() {
  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'Sanmill',
      packageName: 'com.calcitem.sanmill',
      version: 'test',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  DiagnosticReportDraft draft(DiagnosticReportKind kind) {
    return DiagnosticReportDraft(
      id: '01234567-89ab-cdef-0123-456789abcdef',
      createdAtUtc: DateTime.utc(2026, 7, 16),
      kind: kind,
      feedbackText: kind == DiagnosticReportKind.feedback ? '' : null,
      errorMessage: kind == DiagnosticReportKind.feedback ? null : 'boom',
      stackTrace: kind == DiagnosticReportKind.feedback ? null : '#0 test',
      config: const <String, dynamic>{
        'generalSettings': <String, dynamic>{},
        'ruleSettings': <String, dynamic>{},
        'displaySettings': <String, dynamic>{},
        'colorSettings': <String, dynamic>{},
        'informationalOnly': <String, dynamic>{},
      },
      game: const <String, dynamic>{'fen': 'example-fen'},
      actionTrail: DiagnosticActionTrailSnapshot(
        checkpoint: null,
        events: const <UserActionEventV1>[],
        truncatedEventCount: 0,
        recordedAtUtc: DateTime.utc(2026, 7, 16),
      ),
      logs: 'sanitized log',
    );
  }

  Widget app(DiagnosticReportDraft report) {
    return MaterialApp(
      localizationsDelegates: sanmillLocalizationsDelegates,
      supportedLocales: S.supportedLocales,
      locale: const Locale('en'),
      home: DiagnosticReportPage(draft: report),
    );
  }

  bool checkboxValue(WidgetTester tester, String key) {
    return tester.widget<CheckboxListTile>(find.byKey(Key(key))).value ?? false;
  }

  testWidgets('crash defaults config, action trail and logs to included', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(draft(DiagnosticReportKind.crash)));
    await tester.pump();

    expect(checkboxValue(tester, 'diagnostic_include_config'), isTrue);
    expect(checkboxValue(tester, 'diagnostic_include_action_trail'), isTrue);
    expect(checkboxValue(tester, 'diagnostic_include_logs'), isTrue);
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.camera_alt), findsNothing);
  });

  testWidgets('ordinary feedback leaves logs unchecked', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(draft(DiagnosticReportKind.feedback)));
    await tester.pump();

    expect(checkboxValue(tester, 'diagnostic_include_config'), isTrue);
    expect(checkboxValue(tester, 'diagnostic_include_action_trail'), isTrue);
    expect(checkboxValue(tester, 'diagnostic_include_logs'), isFalse);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('visible exact preview changes when a category is cancelled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(draft(DiagnosticReportKind.crash)));
    await tester.pumpAndSettle();

    String preview() {
      return tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((SelectableText widget) => widget.data ?? '')
          .firstWhere((String text) => text.startsWith(diagnosticBundleBegin));
    }

    expect(preview(), contains('"logs": "sanitized log"'));

    await tester.tap(find.byKey(const Key('diagnostic_include_logs')));
    await tester.pumpAndSettle();

    expect(preview(), isNot(contains('"logs":')));
    expect(find.byIcon(Icons.camera_alt), findsNothing);
  });
}
