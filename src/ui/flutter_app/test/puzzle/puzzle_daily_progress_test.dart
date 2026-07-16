// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/puzzle/pages/daily_puzzle_page.dart';
import 'package:sanmill/puzzle/services/daily_puzzle_service.dart';
import 'package:sanmill/puzzle/services/puzzle_manager.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/services/environment_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    'com.calcitem.sanmill/engine',
  );
  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  late Directory appDocDir;

  setUpAll(() async {
    EnvironmentConfig.catcher = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (_) async => null);

    appDocDir = Directory.systemTemp.createTempSync(
      'sanmill_daily_progress_test_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (_) async {
          return appDocDir.path;
        });

    await DB.init();
  });

  setUp(() async {
    await DB().puzzleAnalyticsBox.delete('dailyPuzzleStats');
    DailyPuzzleService.debugNowOverride = () => DateTime(2026, 7, 16, 18);
  });

  tearDown(() {
    DailyPuzzleService.debugNowOverride = null;
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    appDocDir.deleteSync(recursive: true);
  });

  test('records today once for cumulative progress', () async {
    final DailyPuzzleService service = DailyPuzzleService();

    await service.recordCompletion();
    await service.recordCompletion();

    final Map<dynamic, dynamic> stats =
        DB().puzzleAnalyticsBox.get('dailyPuzzleStats')
            as Map<dynamic, dynamic>;
    final List<dynamic> completedDates = stats['completedDates'] as List;
    final String today = DateTime.utc(2026, 7, 16).toIso8601String();

    expect(completedDates, <String>[today]);
    expect(stats['longestStreak'], 0);
  });

  test('preserves legacy longest streak without extending it', () async {
    await DB().puzzleAnalyticsBox.put('dailyPuzzleStats', <String, dynamic>{
      'completedDates': <String>['2025-01-01T00:00:00.000Z'],
      'longestStreak': 17,
    });

    await DailyPuzzleService().recordCompletion();

    final Map<dynamic, dynamic> stats =
        DB().puzzleAnalyticsBox.get('dailyPuzzleStats')
            as Map<dynamic, dynamic>;
    expect(stats['longestStreak'], 17);
    expect((stats['completedDates'] as List<dynamic>).length, 2);
  });

  testWidgets('shows today and cumulative progress without streak pressure', (
    WidgetTester tester,
  ) async {
    final PuzzleManager puzzleManager = PuzzleManager();
    final PuzzleSettings originalSettings =
        puzzleManager.settingsNotifier.value;
    addTearDown(() {
      puzzleManager.settingsNotifier.value = originalSettings;
    });
    puzzleManager.settingsNotifier.value = PuzzleSettings(
      allPuzzles: <PuzzleInfo>[_dailyPuzzle()],
    );

    Future<void> pumpPage() async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: DailyPuzzlePage(key: UniqueKey()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    await pumpPage();

    expect(find.byKey(const Key('daily_puzzle_progress_section')), findsOne);
    expect(find.byKey(const Key('daily_puzzle_today_tile')), findsOne);
    expect(find.byKey(const Key('daily_puzzle_total_tile')), findsOne);
    expect(find.byKey(const Key('daily_puzzle_streak_button')), findsNothing);
    expect(
      find.byKey(const Key('daily_puzzle_best_streak_tile')),
      findsNothing,
    );
    expect(find.text('Not completed yet'), findsOne);
    expect(find.text('0'), findsOne);

    await tester.runAsync(DailyPuzzleService().recordCompletion);
    await pumpPage();

    expect(find.text('Completed'), findsOne);
    expect(find.text('1'), findsOne);
  });
}

PuzzleInfo _dailyPuzzle() {
  return PuzzleInfo(
    id: 'daily-progress-test',
    title: 'Daily progress test',
    description: 'A puzzle used to verify daily progress UI.',
    category: PuzzleCategory.formMill,
    difficulty: PuzzleDifficulty.easy,
    initialPosition:
        '********/********/******** w p p 0 9 0 9 0 0 -1 -1 -1 -1 0 0 1 ids:nodes',
    solutions: const <PuzzleSolution>[
      PuzzleSolution(
        moves: <PuzzleMove>[PuzzleMove(notation: 'a1', side: PieceColor.white)],
      ),
    ],
  );
}
