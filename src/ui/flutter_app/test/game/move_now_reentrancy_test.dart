// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// move_now_reentrancy_test.dart
//
// Regression tests for the EngineNoBestMove report caused by "Move Now".
//
// Tapping Move Now while a search was already in flight used to start a
// second engineToGo() loop. Both loops then polled the same FIFO native
// response queue while sharing one Position, so one loop could consume the
// other's `bestmove` and apply it to a position that had already advanced;
// Game.doMove() then failed and surfaced as EngineNoBestMove.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/services/environment_config.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';
import 'package:sanmill/shared/widgets/snackbars/scaffold_messenger.dart';

import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    'com.calcitem.sanmill/engine',
  );

  final List<String> sentCommands = <String>[];
  late GameController controller;

  setUp(() {
    EnvironmentConfig.catcher = false;
    DB.instance = MockDB();
    initBitboards();
    SoundManager.instance = MockAudios();
    sentCommands.clear();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'send':
              sentCommands.add(methodCall.arguments as String);
              return null;
            case 'read':
              return 'uciok';
            case 'isThinking':
              // Mimic a native engine that is busy with the previous search.
              return true;
            default:
              return null;
          }
        });

    controller = GameController();
    controller.animationManager = MockAnimationManager();
    controller.reset(force: true);
    controller.gameInstance.gameMode = GameMode.humanVsAi;
    controller.isEngineRunning = false;
    controller.isEngineInDelay = false;
  });

  tearDown(() {
    controller.isEngineRunning = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
  });

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        localizationsDelegates: sanmillLocalizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: Builder(
          builder: (BuildContext context) {
            hostContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
    return hostContext;
  }

  testWidgets('moveNow only soft-stops the search that is already running', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await pumpHost(tester);

    controller.isEngineRunning = true;
    sentCommands.clear();

    await controller.moveNow(context);

    // Only the soft stop goes out: no second "position"/"go" pair, so the
    // running loop keeps sole ownership of the native response queue.
    expect(sentCommands, <String>['stop']);
    expect(controller.isEngineRunning, isTrue);
  });

  testWidgets('engineToGo stops the running search instead of starting one', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await pumpHost(tester);

    controller.isEngineRunning = true;
    sentCommands.clear();

    final EngineResponse response = await controller.engineToGo(
      context,
      isMoveNow: true,
    );

    expect(response, isA<EngineResponseSkip>());
    expect(sentCommands, <String>['stop']);
    expect(controller.isEngineRunning, isTrue);
  });

  testWidgets('moveNow leaves the AI and human roles untouched', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await pumpHost(tester);

    final bool whiteIsAi = controller.gameInstance
        .getPlayerByColor(PieceColor.white)
        .isAi;
    final bool blackIsAi = controller.gameInstance
        .getPlayerByColor(PieceColor.black)
        .isAi;

    controller.isEngineRunning = true;
    await controller.moveNow(context);

    expect(
      controller.gameInstance.getPlayerByColor(PieceColor.white).isAi,
      whiteIsAi,
    );
    expect(
      controller.gameInstance.getPlayerByColor(PieceColor.black).isAi,
      blackIsAi,
    );
  });

  testWidgets('engineToGo refuses to start a second loop', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await pumpHost(tester);

    controller.isEngineRunning = true;
    sentCommands.clear();

    final EngineResponse response = await controller.engineToGo(
      context,
      isMoveNow: false,
    );

    expect(response, isA<EngineResponseSkip>());
    expect(sentCommands, isEmpty);
  });
}
