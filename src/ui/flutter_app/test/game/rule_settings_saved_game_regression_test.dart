// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/widgets/game_page.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_action_codec.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/games/mill/native_mill_snapshot_board_view.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/rule_settings/widgets/rule_settings_page.dart';
import 'package:sanmill/shared/config/constants.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/themes/app_theme.dart';
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

  testWidgets(
    'opening a saved game after rule settings keeps the loaded position',
    (WidgetTester tester) async {
      final _RuleSettingsTestDb db = _RuleSettingsTestDb();
      DB.instance = db;
      addTearDown(() => DB.instance = null);
      SoundManager.instance = MockAudios();

      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);
      final GameController controller = GameController();
      controller
        ..animationManager = MockAnimationManager()
        ..bindActiveSession(session)
        ..gameInstance.gameMode = GameMode.humanVsHuman;
      addTearDown(() => controller.unbindActiveSession(session));

      await session.apply(_action(session, 'a1'));
      expect(_occupiedNodes(session), hasLength(1));

      await tester.pumpWidget(_localizedApp(const RuleSettingsPage()));
      await tester.pump();
      expect(_occupiedNodes(session), isEmpty);

      // This move represents the final position installed by a successful
      // saved-game import after the settings page has already reset the old
      // game. Mounting the destination board must not reset it a second time.
      await session.apply(_action(session, 'a1'));
      await tester.pumpWidget(
        _localizedApp(
          const GamePage(
            GameMode.humanVsHuman,
            showInitialOfflineBoardNewGameSheet: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(_occupiedNodes(session), hasLength(1));
    },
    skip: nativeLibrarySkipReason() != null,
  );
}

GameAction _action(NativeMillGameSession session, String notation) {
  return session.legalActions.singleWhere(
    (GameAction action) => MillActionCodec.moveStringFrom(action) == notation,
  );
}

Set<int> _occupiedNodes(NativeMillGameSession session) {
  return NativeMillSnapshotBoardView.fromSnapshot(
    session.state.value,
  )!.occupiedNodes().keys.toSet();
}

Widget _localizedApp(Widget home) {
  return MaterialApp(
    navigatorKey: currentNavigatorKey,
    scaffoldMessengerKey: rootScaffoldMessengerKey,
    theme: AppTheme.lightThemeData,
    localizationsDelegates: sanmillLocalizationsDelegates,
    supportedLocales: S.supportedLocales,
    locale: const Locale('en'),
    home: home,
  );
}

class _RuleSettingsTestDb extends MockDB {
  _RuleSettingsTestDb()
    : _displaySettingsListenable = ValueNotifier<Box<DisplaySettings>>(
        _SettingsBox<DisplaySettings>(
          DB.displaySettingsKey,
          const DisplaySettings(),
        ),
      ),
      _ruleSettingsListenable = ValueNotifier<Box<RuleSettings>>(
        _SettingsBox<RuleSettings>(DB.ruleSettingsKey, const RuleSettings()),
      );

  final ValueNotifier<Box<DisplaySettings>> _displaySettingsListenable;
  final ValueNotifier<Box<RuleSettings>> _ruleSettingsListenable;

  @override
  ValueListenable<Box<DisplaySettings>> get listenDisplaySettings =>
      _displaySettingsListenable;

  @override
  ValueListenable<Box<RuleSettings>> get listenRuleSettings =>
      _ruleSettingsListenable;
}

class _SettingsBox<T> extends Fake implements Box<T> {
  _SettingsBox(this.settingsKey, this.value);

  final String settingsKey;
  final T value;

  @override
  T? get(dynamic key, {T? defaultValue}) {
    return key == settingsKey ? value : defaultValue;
  }
}
