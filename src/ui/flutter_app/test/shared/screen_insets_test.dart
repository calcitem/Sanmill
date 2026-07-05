// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/utils/screen_insets.dart';

void main() {
  testWidgets('modalBottomSheetPadding includes navigation bar inset', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.only(bottom: 48),
          ),
          child: Builder(
            builder: (BuildContext context) {
              return Text(
                '${ScreenInsets.modalBottomSheetPadding(context)}',
                key: const Key('padding_value'),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('48.0'), findsOneWidget);
  });

  testWidgets('modalBottomSheetPadding adds keyboard inset on top', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.only(bottom: 48),
            viewInsets: EdgeInsets.only(bottom: 320),
          ),
          child: Builder(
            builder: (BuildContext context) {
              return Text(
                '${ScreenInsets.modalBottomSheetPadding(context, extra: 16)}',
                key: const Key('padding_value'),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('384.0'), findsOneWidget);
  });
}
