// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/services/offline_board_clock.dart';
import 'package:sanmill/game_page/widgets/game_page.dart';
import 'package:sanmill/game_page/widgets/modals/offline_board_options_sheet.dart';
import 'package:sanmill/game_page/widgets/play_area.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/config/constants.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/themes/app_theme.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';
import 'package:sanmill/shared/widgets/lichess_bottom_bar.dart';
import 'package:sanmill/shared/widgets/snackbars/scaffold_messenger.dart';

import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDB db;

  setUp(() {
    db = _OfflineBoardTestDb(
      displaySettings: const DisplaySettings(
        isUnplacedAndRemovedPiecesShown: false,
        isHistoryNavigationToolbarShown: false,
      ),
    );
    db.generalSettings = const GeneralSettings();
    DB.instance = db;
    final GameController controller = GameController();
    SoundManager.instance = MockAudios();
    controller.animationManager = MockAnimationManager();
    controller.gameInstance.gameMode = GameMode.humanVsHuman;
    controller.gameRecorder.reset();
    controller.activeSessionSnapshot = null;
    controller.isEngineRunning = false;
    controller.isEngineInDelay = false;
    OfflineBoardClock().reset();
  });

  tearDown(() {
    OfflineBoardClock()
      ..reset()
      ..onFlag = null;
    GameController().activeSessionSnapshot = null;
    DB.instance = null;
  });

  testWidgets('new game sheet matches Lichess clock terminology and defaults', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _localizedApp(
        Builder(
          builder: (BuildContext context) => FilledButton(
            key: const Key('open_offline_board_setup'),
            onPressed: () => showOfflineBoardNewGameSheet(context),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open_offline_board_setup')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('offline_board_new_game_sheet')), findsOne);
    expect(find.text('Time control'), findsOne);
    expect(find.text('Clock'), findsOne);
    expect(find.text('Minutes per side: 5'), findsOne);
    expect(find.text('Increment in seconds: 3'), findsOne);
    expect(find.text("Nine Men's Morris"), findsOne);
    expect(find.text('Play'), findsOne);

    await tester.tap(
      find.byKey(const Key('offline_board_time_control_picker')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('offline_board_time_control_unlimited')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unlimited'), findsOne);
    expect(find.textContaining('Minutes per side:'), findsNothing);
    expect(find.textContaining('Increment in seconds:'), findsNothing);

    await tester.tap(find.byKey(const Key('offline_board_start_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('offline_board_new_game_sheet')), findsNothing);
    expect(db.generalSettings.offlineBoardTimeSeconds, 0);
    expect(db.generalSettings.offlineBoardIncrementSeconds, 0);
    expect(OfflineBoardClock().state.isEnabled, isFalse);
  });

  testWidgets('variant picker exposes Mill variants using Sanmill names', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _localizedApp(
        Builder(
          builder: (BuildContext context) => FilledButton(
            key: const Key('open_offline_board_setup'),
            onPressed: () => showOfflineBoardNewGameSheet(context),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_offline_board_setup')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('offline_board_variant_picker')));
    await tester.pumpAndSettle();
    expect(find.text("Twelve Men's Morris"), findsOne);
    expect(find.text('Morabaraba'), findsOne);
    expect(find.text('Zhi Qi'), findsOne);
    await tester.tap(
      find.byKey(const Key('offline_board_variant_twelve_mens_morris')),
    );
    await tester.pumpAndSettle();

    expect(find.text("Twelve Men's Morris"), findsOne);
    await tester.tap(find.byKey(const Key('offline_board_start_button')));
    await tester.pumpAndSettle();

    expect(db.ruleSettings.piecesCount, 12);
    expect(OfflineBoardClock().state.whiteTime, const Duration(minutes: 5));
    expect(OfflineBoardClock().state.increment, const Duration(seconds: 3));
  });

  testWidgets('Chinese Offline Board terms match Lichess', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _localizedApp(
        Builder(
          builder: (BuildContext context) => FilledButton(
            key: const Key('open_offline_board_setup'),
            onPressed: () => showOfflineBoardNewGameSheet(context),
            child: const Text('Open'),
          ),
        ),
        locale: const Locale('zh'),
      ),
    );
    await tester.tap(find.byKey(const Key('open_offline_board_setup')));
    await tester.pumpAndSettle();

    expect(find.text('时间限制'), findsOne);
    expect(find.text('棋钟'), findsOne);
    expect(find.text('各方限时（分钟）: 5'), findsOne);
    expect(find.text('每步加时（秒）: 3'), findsOne);
    expect(find.text('对弈'), findsOne);
    await tester.tap(find.byKey(const Key('offline_board_start_button')));
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _localizedApp(
        const Scaffold(
          body: PlayArea(
            boardImage: null,
            child: SizedBox.square(dimension: 390),
          ),
        ),
        locale: const Locale('zh'),
      ),
    );
    await tester.pump();

    expect(find.text('白方'), findsOne);
    expect(find.text('黑方'), findsOne);
    expect(
      tester
          .widget<LichessBottomBarButton>(
            find.byKey(const Key('play_area_offline_board_bottom_take_back')),
          )
          .label,
      '悔棋',
    );
    await tester.tap(
      find.byKey(const Key('play_area_offline_board_bottom_menu')),
    );
    await tester.pumpAndSettle();
    expect(find.text('新的对局'), findsOne);
    expect(find.text('翻转棋盘'), findsOne);
  });

  testWidgets('game page uses a left title and mandatory initial setup', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _localizedApp(const GamePage(GameMode.humanVsHuman)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final AppBar appBar = tester.widget<AppBar>(
      find.byKey(const Key('game_page_offline_board_appbar')),
    );
    expect(appBar.centerTitle, isFalse);
    expect(find.text('Over the board'), findsOneWidget);
    expect(
      find.byKey(const Key('game_page_offline_board_settings_button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('offline_board_new_game_sheet')), findsOne);
    expect(
      find.byWidgetPredicate(
        (Widget widget) => widget is ModalBarrier && !widget.dismissible,
      ),
      findsAtLeastNWidgets(1),
    );

    await tester.tap(find.byKey(const Key('offline_board_start_button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('offline_board_new_game_sheet')), findsNothing);
    expect(OfflineBoardClock().state.status, OfflineBoardClockStatus.paused);
    expect(OfflineBoardClock().state.whiteTime, const Duration(minutes: 5));

    await tester.tap(
      find.byKey(const Key('game_page_offline_board_settings_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.byKey(const Key('offline_board_display_flip_after_move')),
      findsOneWidget,
    );
  });

  testWidgets('display settings persist automatic board flipping', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _localizedApp(
        Builder(
          builder: (BuildContext context) => FilledButton(
            key: const Key('open_offline_board_display'),
            onPressed: () => showOfflineBoardDisplaySettings(context),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_offline_board_display')));
    await tester.pumpAndSettle();

    final Finder toggle = find.byKey(
      const Key('offline_board_display_flip_after_move'),
    );
    expect(toggle, findsOne);
    expect(find.text('Flip pieces and opponent info after move'), findsOne);
    expect(db.generalSettings.offlineBoardFlipAfterMove, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(db.generalSettings.offlineBoardFlipAfterMove, isTrue);
  });

  testWidgets('game surface has two clocks and Lichess control order', (
    WidgetTester tester,
  ) async {
    OfflineBoardClock().setup(
      initialTime: const Duration(minutes: 5),
      increment: const Duration(seconds: 3),
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _localizedApp(
        const Scaffold(
          body: PlayArea(
            boardImage: null,
            child: SizedBox.square(
              key: Key('offline_board_test_board'),
              dimension: 390,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('play_area_offline_board_top_player')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_offline_board_bottom_player')),
      findsOne,
    );
    expect(find.byKey(const Key('offline_board_white_clock')), findsOne);
    expect(find.byKey(const Key('offline_board_black_clock')), findsOne);
    expect(find.text('White'), findsOne);
    expect(find.text('Black'), findsOne);
    expect(find.text('5:00'), findsNWidgets(2));
    expect(
      find.byKey(const Key('play_area_offline_board_bottom_menu')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_offline_board_bottom_clock')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_offline_board_bottom_previous')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_offline_board_bottom_next')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_offline_board_bottom_take_back')),
      findsOne,
    );
    expect(
      tester
          .widget<LichessBottomBarButton>(
            find.byKey(const Key('play_area_offline_board_bottom_clock')),
          )
          .label,
      'Resume',
    );
    expect(
      tester
          .widget<LichessBottomBarButton>(
            find.byKey(const Key('play_area_offline_board_bottom_take_back')),
          )
          .label,
      'Takeback',
    );

    await tester.tap(
      find.byKey(const Key('play_area_offline_board_bottom_clock')),
    );
    await tester.pump();
    expect(OfflineBoardClock().state.isRunning, isTrue);
    expect(
      tester
          .widget<LichessBottomBarButton>(
            find.byKey(const Key('play_area_offline_board_bottom_clock')),
          )
          .label,
      'Pause',
    );
    OfflineBoardClock().pause();
  });

  testWidgets('automatic display rotation follows the player to move', (
    WidgetTester tester,
  ) async {
    db.generalSettings = const GeneralSettings(offlineBoardFlipAfterMove: true);
    final GameController controller = GameController();
    controller.activeSessionSnapshot = const GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: PlayerSeat.first,
      outcome: GameOutcome.ongoing(),
      phase: 'placing',
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _localizedApp(
        const Scaffold(
          body: PlayArea(
            boardImage: null,
            child: SizedBox.square(dimension: 390),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(_playerQuarterTurns(tester, 'top'), 0);
    expect(_playerQuarterTurns(tester, 'bottom'), 0);
    expect(
      tester
          .widget<RotatedBox>(
            find.byKey(const Key('play_area_board_orientation')),
          )
          .quarterTurns,
      0,
    );

    controller.activeSessionSnapshot = const GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: PlayerSeat.second,
      outcome: GameOutcome.ongoing(),
      phase: 'placing',
    );
    await tester.pumpWidget(
      _localizedApp(
        const Scaffold(
          body: PlayArea(
            boardImage: null,
            child: SizedBox.square(dimension: 390),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(_playerQuarterTurns(tester, 'top'), 2);
    expect(_playerQuarterTurns(tester, 'bottom'), 2);
    expect(
      tester
          .widget<RotatedBox>(
            find.byKey(const Key('play_area_board_orientation')),
          )
          .quarterTurns,
      0,
    );
  });

  testWidgets('menu opens the shared board transform picker', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _localizedApp(
        const Scaffold(
          body: PlayArea(
            boardImage: null,
            child: SizedBox.square(dimension: 390),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<RotatedBox>(
            find.byKey(const Key('play_area_board_orientation')),
          )
          .quarterTurns,
      0,
    );

    await tester.tap(
      find.byKey(const Key('play_area_offline_board_bottom_menu')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('play_area_offline_board_menu_sheet')),
      findsOne,
    );
    expect(find.text('New game'), findsOne);
    expect(find.text('Flip board'), findsOne);
    expect(find.text('Move list'), findsNothing);
    expect(find.text('Options'), findsNothing);
    await tester.tap(
      find.byKey(const Key('play_area_offline_board_menu_flip_board')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('play_area_offline_board_transform_sheet')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_offline_board_menu_sheet')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_offline_board_transform_grid')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_offline_board_transform_identity')),
      findsOne,
    );
  });

  testWidgets('unlimited games hide pause control and show infinity', (
    WidgetTester tester,
  ) async {
    OfflineBoardClock().setup(
      initialTime: Duration.zero,
      increment: Duration.zero,
    );
    await tester.pumpWidget(
      _localizedApp(
        const Scaffold(
          body: PlayArea(
            boardImage: null,
            child: SizedBox.square(dimension: 390),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('∞'), findsNWidgets(2));
    expect(
      find.byKey(const Key('play_area_offline_board_bottom_clock')),
      findsNothing,
    );
  });
}

int _playerQuarterTurns(WidgetTester tester, String position) {
  final Finder panel = find.byKey(
    Key('play_area_offline_board_${position}_player'),
  );
  final Finder rotation = find.descendant(
    of: panel,
    matching: find.byType(RotatedBox),
  );
  if (rotation.evaluate().isEmpty) {
    return 0;
  }
  return tester.widget<RotatedBox>(rotation).quarterTurns;
}

class _OfflineBoardTestDb extends MockDB {
  _OfflineBoardTestDb({required DisplaySettings displaySettings})
    : _displaySettingsListenable = ValueNotifier<Box<DisplaySettings>>(
        _SettingsBox<DisplaySettings>(DB.displaySettingsKey, displaySettings),
      ) {
    this.displaySettings = displaySettings;
  }

  final ValueNotifier<Box<DisplaySettings>> _displaySettingsListenable;

  @override
  ValueListenable<Box<DisplaySettings>> get listenDisplaySettings {
    return _displaySettingsListenable;
  }
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

Widget _localizedApp(Widget child, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      navigatorKey: currentNavigatorKey,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      theme: AppTheme.lightThemeData,
      localizationsDelegates: sanmillLocalizationsDelegates,
      supportedLocales: S.supportedLocales,
      locale: locale,
      home: Scaffold(body: child),
    );
