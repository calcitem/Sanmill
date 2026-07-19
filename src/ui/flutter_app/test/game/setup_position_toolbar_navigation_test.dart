// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/widgets/toolbars/game_toolbar.dart';
import 'package:sanmill/games/mill/mill_route_ids.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';

import '../helpers/mocks/mock_database.dart';

void main() {
  setUp(() {
    DB.instance = MockDB();
  });

  tearDown(() {
    DB.instance = null;
  });

  testWidgets('cancel leaves the standalone board editor route', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: sanmillLocalizationsDelegates,
        supportedLocales: S.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open_board_editor'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      settings: RouteSettings(
                        name: MillRouteIds.setupPosition.value,
                      ),
                      builder: (_) => const Scaffold(
                        body: Align(
                          alignment: Alignment.bottomCenter,
                          child: SetupPositionToolbar(),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open_board_editor')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cancel_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('cancel_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open_board_editor')), findsOneWidget);
    expect(find.byKey(const Key('cancel_button')), findsNothing);
  });
}
