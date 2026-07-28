// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/board_recognition_import.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/widgets/toolbars/game_toolbar.dart';
import 'package:sanmill/games/mill/mill_route_ids.dart';
import 'package:sanmill/games/mill/mill_setup_position_controller.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/themes/app_theme.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';
import 'package:sanmill/shared/utils/screen_insets.dart';
import 'package:sanmill/shared/widgets/snackbars/scaffold_messenger.dart';

import '../helpers/mocks/mock_database.dart';
import '../helpers/test_native_library.dart';

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

  test(
    'embedded board editors restore their originating mode',
    () {
      final GameController controller = GameController();
      final GameMode originalMode = controller.gameInstance.gameMode;
      final NativeMillGameSession session = NativeMillGameSession();
      controller.bindActiveSession(session);
      addTearDown(() {
        controller.abandonSetupPositionIfActive();
        controller.unbindActiveSession(session);
        controller.gameInstance.gameMode = originalMode;
        session.dispose();
      });

      for (final GameMode origin in const <GameMode>[
        GameMode.humanVsAi,
        GameMode.humanVsHuman,
        GameMode.aiVsAi,
        GameMode.analysis,
      ]) {
        controller.gameInstance.gameMode = origin;
        controller.enterSetupPosition();
        expect(controller.isStandaloneSetupPosition, isFalse);
        final String fen = controller.setupPositionController!.exportFen();

        expect(controller.finishSetupPosition(fen), origin);
        expect(controller.gameInstance.gameMode, origin);

        controller.enterSetupPosition();
        expect(controller.cancelSetupPosition(), origin);
        expect(controller.gameInstance.gameMode, origin);
      }
    },
    skip: _nativeLibrarySkipReason != null,
  );

  test(
    'standalone board editor accepts every local destination',
    () {
      final GameController controller = GameController();
      final GameMode originalMode = controller.gameInstance.gameMode;
      final NativeMillGameSession session = NativeMillGameSession();
      controller.bindActiveSession(session);
      addTearDown(() {
        controller.abandonSetupPositionIfActive();
        controller.unbindActiveSession(session);
        controller.gameInstance.gameMode = originalMode;
        session.dispose();
      });

      for (final GameMode destination in const <GameMode>[
        GameMode.humanVsAi,
        GameMode.humanVsHuman,
        GameMode.aiVsAi,
        GameMode.analysis,
      ]) {
        controller.gameInstance.gameMode = GameMode.setupPosition;
        controller.enterSetupPosition();
        expect(controller.isStandaloneSetupPosition, isTrue);
        final String fen = controller.setupPositionController!.exportFen();

        expect(
          controller.finishSetupPosition(fen, destination: destination),
          destination,
        );
        expect(controller.gameInstance.gameMode, destination);
      }
    },
    skip: _nativeLibrarySkipReason != null,
  );

  test(
    'board recognition requires an active board editor session',
    () {
      final GameMode originalMode = GameController().gameInstance.gameMode;
      addTearDown(() => GameController().gameInstance.gameMode = originalMode);
      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);
      final MillSetupPositionController controller =
          MillSetupPositionController(
            session: session,
            ruleSettings: const RuleSettings(),
          )..initFromSession();
      GameController().setupPositionController = controller;

      GameController().gameInstance.gameMode = GameMode.humanVsHuman;
      expect(BoardRecognitionImport.isAvailable, isFalse);

      GameController().gameInstance.gameMode = GameMode.setupPosition;
      expect(BoardRecognitionImport.isAvailable, isTrue);
    },
    skip: _nativeLibrarySkipReason != null,
  );

  testWidgets(
    'standalone done offers play and analysis destinations',
    (WidgetTester tester) async {
      final GameController controller = GameController();
      final GameMode originalMode = controller.gameInstance.gameMode;
      final NativeMillGameSession session = NativeMillGameSession();
      controller.bindActiveSession(session);
      controller.gameInstance.gameMode = GameMode.setupPosition;
      controller.enterSetupPosition();
      addTearDown(() {
        controller.abandonSetupPositionIfActive();
        controller.unbindActiveSession(session);
        controller.gameInstance.gameMode = originalMode;
        session.dispose();
      });
      GameMode? returnedMode;

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
                  onPressed: () async {
                    returnedMode = await Navigator.of(context).push<GameMode>(
                      MaterialPageRoute<GameMode>(
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
      await tester.tap(find.byKey(const Key('done_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('setup_position_destination_sheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('setup_position_destination_human_vs_ai')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('setup_position_destination_human_vs_human')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('setup_position_destination_ai_vs_ai')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('setup_position_destination_analysis')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('setup_position_destination_analysis')),
      );
      await tester.pumpAndSettle();

      expect(returnedMode, GameMode.analysis);
      expect(controller.gameInstance.gameMode, GameMode.analysis);
      expect(controller.setupPositionController, isNull);
      expect(find.byKey(const Key('open_board_editor')), findsOneWidget);
    },
    skip: _nativeLibrarySkipReason != null,
  );

  testWidgets(
    'cancel leaves the standalone board editor route',
    (WidgetTester tester) async {
      final GameController controller = GameController();
      final GameMode originalMode = controller.gameInstance.gameMode;
      final NativeMillGameSession session = NativeMillGameSession();
      controller.bindActiveSession(session);
      controller.gameInstance.gameMode = GameMode.setupPosition;
      controller.enterSetupPosition();
      addTearDown(() {
        controller.abandonSetupPositionIfActive();
        controller.unbindActiveSession(session);
        controller.gameInstance.gameMode = originalMode;
        session.dispose();
      });

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
    },
    skip: _nativeLibrarySkipReason != null,
  );

  testWidgets(
    'paint selector uses solid white and black piece indicators',
    (WidgetTester tester) async {
      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);
      final MillSetupPositionController controller =
          MillSetupPositionController(
            session: session,
            ruleSettings: const RuleSettings(),
          )..initFromSession();
      GameController().setupPositionController = controller;
      GameController().gameInstance.gameMode = GameMode.setupPosition;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightThemeData,
          darkTheme: AppTheme.darkThemeData,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SetupPositionToolbar(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      BoxDecoration indicatorDecoration() {
        return tester
                .widget<Container>(
                  find.byKey(const Key('paint_color_piece_indicator')),
                )
                .decoration!
            as BoxDecoration;
      }

      expect(indicatorDecoration().color, DB().colorSettings.whitePieceColor);
      expect(indicatorDecoration().shape, BoxShape.circle);
      expect(indicatorDecoration().border, isNotNull);

      await tester.tap(find.byKey(const Key('paint_color_button')));
      await tester.pumpAndSettle();

      expect(controller.paintColor, PieceColor.black);
      expect(indicatorDecoration().color, DB().colorSettings.blackPieceColor);
      expect(indicatorDecoration().shape, BoxShape.circle);
      expect(indicatorDecoration().border, isNotNull);
    },
    skip: _nativeLibrarySkipReason != null,
  );

  testWidgets(
    'count controls record integer values without opening diagnostics',
    (WidgetTester tester) async {
      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);
      final MillSetupPositionController controller =
          MillSetupPositionController(
              session: session,
              ruleSettings: const RuleSettings(),
            )
            ..initFromSession()
            ..setPaintColor(PieceColor.black)
            ..tapNode(0)
            ..setPaintColor(PieceColor.white);
      GameController().setupPositionController = controller;
      GameController().gameInstance.gameMode = GameMode.setupPosition;

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          locale: Locale('en'),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SetupPositionToolbar(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remove_button')));
      await tester.pumpAndSettle();
      expect(controller.needRemove[PieceColor.white], 1);

      await tester.tap(find.byKey(const Key('placed_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('placed_option_2')));
      await tester.pumpAndSettle();
      expect(controller.placedCount, 2);
      expect(find.text('Diagnostic report'), findsNothing);
    },
    skip: _nativeLibrarySkipReason != null,
  );

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
