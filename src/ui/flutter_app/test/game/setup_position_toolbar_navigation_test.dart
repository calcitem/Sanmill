// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/widgets/toolbars/game_toolbar.dart';
import 'package:sanmill/games/mill/mill_setup_position_controller.dart';
import 'package:sanmill/games/mill/mill_route_ids.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/themes/app_theme.dart';
import 'package:sanmill/shared/utils/screen_insets.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';
import 'package:sanmill/shared/widgets/snackbars/scaffold_messenger.dart';

import '../helpers/test_native_library.dart';
import '../helpers/mocks/mock_database.dart';

final String? _nativeLibrarySkipReason = nativeLibrarySkipReason();

void main() {
  setUpAll(initRustLibForTests);

  setUp(() {
    DB.instance = MockDB();
  });

  tearDown(() {
    GameController().setupPositionController = null;
    DB.instance = null;
  });

  tearDownAll(disposeRustLibForTests);

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

  testWidgets(
    'invalid-position message stays above the editor actions',
    (WidgetTester tester) async {
      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);
      final MillSetupPositionController controller =
          MillSetupPositionController(
              session: session,
              ruleSettings: const RuleSettings(),
            )
            ..initFromSession()
            ..clear()
            ..setPaintColor(PieceColor.white)
            ..tapNode(0)
            ..setPaintColor(PieceColor.black)
            ..tapNode(8)
            ..setPhase(Phase.moving);
      GameController().setupPositionController = controller;
      GameController().gameInstance.gameMode = GameMode.setupPosition;

      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: SafeArea(
                top: false,
                minimum: EdgeInsets.only(
                  bottom: ScreenInsets.navigationBarInset(context),
                ),
                child: const Column(
                  children: <Widget>[
                    Spacer(),
                    SetupPositionToolbar(),
                    SizedBox(height: AppTheme.boardMargin),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('done_button')));
      await tester.pumpAndSettle();

      final Rect message = tester.getRect(find.text('Invalid position.'));
      final Rect actions = tester.getRect(
        find.byKey(const Key('setup_position_buttons_container_row3')),
      );
      expect(message.bottom, lessThanOrEqualTo(actions.top));
    },
    skip: _nativeLibrarySkipReason != null,
  );
}
