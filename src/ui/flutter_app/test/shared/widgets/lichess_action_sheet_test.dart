// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';
import 'package:sanmill/shared/widgets/lichess_action_sheet.dart';

void main() {
  testWidgets('Material action sheet uses standard dismissal affordances', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pumpActionSheetApp(tester);

    await _openActionSheet(tester);

    expect(find.byKey(const Key('test_action_sheet')), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);

    final Finder dismissBarrier = find.bySemanticsLabel('Dismiss');
    expect(dismissBarrier, findsOneWidget);
    final SemanticsNode dismissNode = tester.getSemantics(dismissBarrier);
    expect(
      dismissNode.getSemanticsData().hasAction(SemanticsAction.dismiss),
      isTrue,
    );

    tester.binding.pipelineOwner.semanticsOwner!.performAction(
      dismissNode.id,
      SemanticsAction.dismiss,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('test_action_sheet')), findsNothing);
    semantics.dispose();
  });

  testWidgets(
    'Material action sheet closes with Escape, back, and the barrier',
    (WidgetTester tester) async {
      await _pumpActionSheetApp(tester);

      await _openActionSheet(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('test_action_sheet')), findsNothing);

      await _openActionSheet(tester);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('test_action_sheet')), findsNothing);

      await _openActionSheet(tester);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('test_action_sheet')), findsNothing);
    },
  );

  testWidgets('Material action sheet action remains directly selectable', (
    WidgetTester tester,
  ) async {
    bool actionSelected = false;
    await _pumpActionSheetApp(tester, onAction: () => actionSelected = true);

    await _openActionSheet(tester);
    await tester.tap(find.text('Action'));
    await tester.pumpAndSettle();

    expect(actionSelected, isTrue);
    expect(find.byKey(const Key('test_action_sheet')), findsNothing);
  });

  testWidgets('Cupertino action sheet keeps its system Cancel action', (
    WidgetTester tester,
  ) async {
    await _pumpActionSheetApp(tester, platform: TargetPlatform.iOS);

    await _openActionSheet(tester);

    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('test_action_sheet')), findsNothing);
  });
}

Future<void> _pumpActionSheetApp(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.android,
  VoidCallback? onAction,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
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
                  onPressed: onAction ?? () {},
                ),
              ],
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openActionSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open_sheet')));
  await tester.pumpAndSettle();
}
