// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';
import 'package:sanmill/shared/widgets/lichess_action_sheet.dart';

void main() {
  testWidgets('Material action sheet has an explicit cancel action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: sanmillLocalizationsDelegates,
        supportedLocales: S.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: TextButton(
              key: const Key('open_sheet'),
              onPressed: () => showLichessActionSheet<void>(
                context: context,
                sheetKey: const Key('test_action_sheet'),
                actions: <LichessActionSheetAction>[
                  LichessActionSheetAction(
                    makeLabel: (_) => const Text('Action'),
                    onPressed: () {},
                  ),
                ],
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open_sheet')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('test_action_sheet')), findsOneWidget);
    expect(
      find.byKey(const Key('lichess_action_sheet_cancel_button')),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('lichess_action_sheet_cancel_button')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('test_action_sheet')), findsNothing);
    expect(find.byKey(const Key('open_sheet')), findsOneWidget);
  });
}
