// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/widgets/lichess_list_section.dart';

void main() {
  testWidgets('iOS list sections assign unique divider keys', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: const Scaffold(
          body: LichessListSection(
            children: <Widget>[
              ListTile(title: Text('First')),
              ListTile(title: Text('Second')),
              ListTile(title: Text('Third')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('lichess_list_section_divider_0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('lichess_list_section_divider_1')),
      findsOneWidget,
    );
  });
}
