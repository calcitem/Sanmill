// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/widgets/import_game_page.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';
import 'package:sanmill/shared/widgets/snackbars/scaffold_messenger.dart';

import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';
import '../helpers/test_native_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initRustLibForTests);
  tearDownAll(disposeRustLibForTests);

  setUp(() {
    DB.instance = MockDB();
    SoundManager.instance = MockAudios();
    final GameController controller = GameController();
    controller.animationManager = MockAnimationManager();
    controller.reset(force: true);
    controller.gameInstance.gameMode = GameMode.humanVsHuman;
  });

  tearDown(() {
    DB.instance = null;
  });

  testWidgets(
    'invalid PGN stays editable with inline feedback',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          locale: const Locale('en'),
          home: const ImportGamePage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('import_game_paste_field')),
        '[Site "PlayOK"]\n1. 1 4 2. x5',
      );
      await tester.pump();
      final Finder loadButton = find.byKey(
        const Key('import_game_load_button'),
      );
      expect(tester.widget<FilledButton>(loadButton).onPressed, isNotNull);
      await tester.tap(loadButton);
      await tester.pumpAndSettle();

      final Finder errorMessage = find.byKey(
        const Key('import_game_error_message'),
      );
      expect(errorMessage, findsOne);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('[Site "PlayOK"]\n1. 1 4 2. x5'), findsOne);

      final Rect errorRect = tester.getRect(errorMessage);
      final Rect loadButtonRect = tester.getRect(
        find.byKey(const Key('import_game_load_button')),
      );
      expect(errorRect.bottom, lessThanOrEqualTo(loadButtonRect.top));

      await tester.enterText(
        find.byKey(const Key('import_game_paste_field')),
        'corrected input',
      );
      await tester.pump();
      expect(errorMessage, findsNothing);
    },
    skip: nativeLibrarySkipReason() != null,
  );
}
