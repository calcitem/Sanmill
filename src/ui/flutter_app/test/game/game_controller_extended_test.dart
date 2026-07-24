// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_controller_extended_test.dart
//
// Extended tests for GameController singleton, reset, state management,
// and notifiers.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/services/transform/transform.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_remote_session_meta.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/games/mill/native_mill_rules_port.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/remote_play/remote_match_controller.dart';
import 'package:sanmill/remote_play/remote_models.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/config/constants.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';
import 'package:sanmill/shared/widgets/snackbars/scaffold_messenger.dart';

import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    "com.calcitem.sanmill/engine",
  );

  setUp(() {
    DB.instance = MockDB();
    SoundManager.instance = MockAudios();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'send':
            case 'shutdown':
            case 'startup':
              return null;
            case 'read':
              return 'bestmove d2';
            case 'isThinking':
              return false;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
  });

  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------
  group('GameController singleton', () {
    test('factory constructor should return same instance', () {
      final GameController c1 = GameController();
      final GameController c2 = GameController();
      expect(identical(c1, c2), isTrue);
    });

    test('instance should be accessible', () {
      expect(GameController.instance, isNotNull);
      expect(identical(GameController(), GameController.instance), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Reset
  // ---------------------------------------------------------------------------
  group('GameController.reset', () {
    test('reset should preserve gameMode', () {
      final GameController controller = GameController();
      controller.animationManager = MockAnimationManager();
      controller.gameInstance.gameMode = GameMode.humanVsHuman;

      controller.reset();

      expect(controller.gameInstance.gameMode, GameMode.humanVsHuman);
    });

    test('reset should clear position to initial state', () {
      final GameController controller = GameController();
      controller.animationManager = MockAnimationManager();
      controller.gameInstance.gameMode = GameMode.humanVsHuman;

      // Make some moves
      controller.reset(force: true);

      // After reset, the active board view should be in placing
      // phase (or "ready" before the native session has finished
      // wiring up).
      final Phase phase = controller.activeBoardView.phase;
      expect(phase == Phase.placing || phase == Phase.ready, isTrue);
    });

    test('reset should clear focus and blur indices', () {
      final GameController controller = GameController();
      controller.animationManager = MockAnimationManager();
      controller.gameInstance.focusIndex = 8;
      controller.gameInstance.blurIndex = 12;

      controller.reset(force: true);

      expect(controller.gameInstance.focusIndex, isNull);
      expect(controller.gameInstance.blurIndex, isNull);
    });

    test('forced reset should work even during game', () {
      final GameController controller = GameController();
      controller.animationManager = MockAnimationManager();
      controller.gameInstance.gameMode = GameMode.humanVsHuman;

      controller.reset(force: true);

      // Should not throw -- read through the native-backed view.
      expect(controller.activeBoardView, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Active board view access (replaces the legacy GameController.position
  // accessor that came with the Dart `Position` rule machine).
  // ---------------------------------------------------------------------------
  group('GameController.activeBoardView', () {
    test('should provide a board view at any time', () {
      final GameController controller = GameController();

      expect(controller.activeBoardView, isNotNull);
    });

    test('default sideToMove is white after a fresh reset', () {
      final GameController controller = GameController();
      controller.animationManager = MockAnimationManager();
      controller.reset(force: true);

      expect(controller.activeBoardView.sideToMove, PieceColor.white);
    });
  });

  // ---------------------------------------------------------------------------
  // Game instance access
  // ---------------------------------------------------------------------------
  group('GameController.gameInstance', () {
    test('should provide access to the Game object', () {
      final GameController controller = GameController();

      expect(controller.gameInstance, isNotNull);
      expect(controller.gameInstance, isA<Game>());
    });

    test('gameInstance players should have two entries', () {
      final GameController controller = GameController();

      expect(controller.gameInstance.players.length, 2);
    });
  });

  // ---------------------------------------------------------------------------
  // Game recorder
  // ---------------------------------------------------------------------------
  group('GameController.gameRecorder', () {
    test('should provide access to the GameRecorder', () {
      final GameController controller = GameController();

      expect(controller.gameRecorder, isNotNull);
      expect(controller.gameRecorder, isA<GameRecorder>());
    });

    test('gameRecorder should have empty mainline after reset', () {
      final GameController controller = GameController();
      controller.animationManager = MockAnimationManager();
      controller.reset(force: true);

      expect(controller.gameRecorder.mainlineMoves, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Notifiers
  // ---------------------------------------------------------------------------
  group('GameController notifiers', () {
    test('headerTipNotifier should be accessible', () {
      final GameController controller = GameController();
      expect(controller.headerTipNotifier, isNotNull);
    });

    test('headerIconsNotifier should be accessible', () {
      final GameController controller = GameController();
      expect(controller.headerIconsNotifier, isNotNull);
    });

    test('gameResultNotifier should be accessible', () {
      final GameController controller = GameController();
      expect(controller.gameResultNotifier, isNotNull);
    });

    test('boardSemanticsNotifier should be accessible', () {
      final GameController controller = GameController();
      expect(controller.boardSemanticsNotifier, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Engine state
  // ---------------------------------------------------------------------------
  group('GameController engine state', () {
    test('isEngineRunning should be false initially', () {
      final GameController controller = GameController();
      expect(controller.isEngineRunning, isFalse);
    });

    test('aiMoveType should have a default', () {
      final GameController controller = GameController();
      expect(controller.aiMoveType, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // disableStats
  // ---------------------------------------------------------------------------
  group('GameController.disableStats', () {
    test('should be settable', () {
      final GameController controller = GameController();
      controller.disableStats = true;
      expect(controller.disableStats, isTrue);

      controller.disableStats = false;
      expect(controller.disableStats, isFalse);
    });
  });

  group('GameController.requestResignation', () {
    testWidgets(
      'delegates a confirmed remote resignation without another dialog',
      (WidgetTester tester) async {
        final GameController controller = GameController();
        final GameMode previousMode = controller.gameInstance.gameMode;
        final RemoteMatchController? previousCoordinator =
            controller.remoteCoordinator;
        final _ResignOnlyRemoteController coordinator =
            _ResignOnlyRemoteController();
        controller.gameInstance.gameMode = GameMode.humanVsCloud;
        controller.remoteCoordinator = coordinator;
        addTearDown(() {
          controller.gameInstance.gameMode = previousMode;
          controller.remoteCoordinator = previousCoordinator;
        });

        await tester.pumpWidget(
          MaterialApp(
            scaffoldMessengerKey: rootScaffoldMessengerKey,
            localizationsDelegates: sanmillLocalizationsDelegates,
            supportedLocales: S.supportedLocales,
            home: Scaffold(
              body: FilledButton(
                onPressed: () async {
                  await controller.requestResignation();
                },
                child: const Text('Confirm resignation'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Confirm resignation'));
        await tester.pumpAndSettle();

        expect(coordinator.resignCalls, 1);
        expect(find.byType(AlertDialog), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'shows a readable dialog when remote resignation fails with tips off',
      (WidgetTester tester) async {
        final GameController controller = GameController();
        final GameMode previousMode = controller.gameInstance.gameMode;
        final RemoteMatchController? previousCoordinator =
            controller.remoteCoordinator;
        final _ResignOnlyRemoteController coordinator =
            _ResignOnlyRemoteController()..resignResult = false;
        controller.gameInstance.gameMode = GameMode.humanVsCloud;
        controller.remoteCoordinator = coordinator;
        addTearDown(() {
          controller.gameInstance.gameMode = previousMode;
          controller.remoteCoordinator = previousCoordinator;
        });

        Future<void>? resignation;
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: currentNavigatorKey,
            scaffoldMessengerKey: rootScaffoldMessengerKey,
            localizationsDelegates: sanmillLocalizationsDelegates,
            supportedLocales: S.supportedLocales,
            home: Scaffold(
              body: FilledButton(
                onPressed: () {
                  resignation = controller.requestResignation();
                },
                child: const Text('Confirm resignation'),
              ),
            ),
          ),
        );

        expect(DB().generalSettings.showGameTips, isFalse);
        await tester.tap(find.text('Confirm resignation'));
        await tester.pumpAndSettle();

        final Finder resultDialog = find.byKey(
          const Key('remote_resignation_failure_dialog'),
        );
        expect(coordinator.resignCalls, 1);
        expect(resultDialog, findsOneWidget);
        final BuildContext dialogContext = tester.element(resultDialog);
        final Text message = tester.widget<Text>(
          find.text(S.of(dialogContext).failedToSendResignation),
        );
        expect(message.style?.fontSize, greaterThanOrEqualTo(16));

        await tester.tap(find.byKey(const Key('remote_important_dialog_ok')));
        await tester.pumpAndSettle();
        await resignation;
        expect(resultDialog, findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });

  group('GameController outgoing remote request dialogs', () {
    testWidgets('shows restart waiting and rejection dialogs with tips off', (
      WidgetTester tester,
    ) async {
      final GameController controller = GameController();
      final GameMode previousMode = controller.gameInstance.gameMode;
      final RemoteMatchController? previousCoordinator =
          controller.remoteCoordinator;
      final _ResignOnlyRemoteController coordinator =
          _ResignOnlyRemoteController();
      controller.gameInstance.gameMode = GameMode.humanVsCloud;
      controller.remoteCoordinator = coordinator;
      addTearDown(() {
        controller.gameInstance.gameMode = previousMode;
        controller.remoteCoordinator = previousCoordinator;
      });

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: currentNavigatorKey,
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: FilledButton(
              onPressed: controller.requestRestart,
              child: const Text('Request restart'),
            ),
          ),
        ),
      );

      expect(DB().generalSettings.showGameTips, isFalse);
      await tester.tap(find.text('Request restart'));
      await tester.pump();

      expect(coordinator.restartCalls, 1);
      expect(
        find.byKey(const Key('remote_restart_waiting_dialog')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      coordinator.restartResult!.complete(false);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('remote_restart_waiting_dialog')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('remote_restart_result_dialog')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('remote_important_dialog_ok')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('shows takeback waiting and rejection dialogs with tips off', (
      WidgetTester tester,
    ) async {
      final GameController controller = GameController();
      final GameMode previousMode = controller.gameInstance.gameMode;
      final RemoteMatchController? previousCoordinator =
          controller.remoteCoordinator;
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: _HistoryRulesPort(),
      );
      final _ResignOnlyRemoteController coordinator =
          _ResignOnlyRemoteController();
      session.remoteMeta = const MillRemoteSessionMeta(
        localSeat: PlayerSeat.second,
        hostPlaysWhite: true,
        transportKind: RemoteTransportKind.cloud,
        role: RemoteRole.join,
        sessionId: 'cloud-takeback-rejection-test',
      );
      controller.bindActiveSession(session);
      controller.gameInstance.gameMode = GameMode.humanVsCloud;
      controller.remoteCoordinator = coordinator;
      addTearDown(() {
        controller.unbindActiveSession(session);
        controller.gameInstance.gameMode = previousMode;
        controller.remoteCoordinator = previousCoordinator;
        session.dispose();
      });

      Future<bool>? request;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: currentNavigatorKey,
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: FilledButton(
              onPressed: () {
                request = controller.requestRemoteTakeBack(1);
              },
              child: const Text('Request takeback'),
            ),
          ),
        ),
      );

      expect(DB().generalSettings.showGameTips, isFalse);
      await tester.tap(find.text('Request takeback'));
      await tester.pump();

      expect(coordinator.takeBackRequests, const <int>[1]);
      expect(
        find.byKey(const Key('remote_takeback_waiting_dialog')),
        findsOneWidget,
      );
      expect(
        find.text(
          'Requested to take back your latest turn together with your '
          "opponent's following reply. Waiting for your opponent…",
        ),
        findsOneWidget,
      );

      coordinator.takeBackResult!.complete(false);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('remote_takeback_result_dialog')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('remote_important_dialog_ok')));
      await tester.pumpAndSettle();
      expect(await request, isFalse);
      expect(find.byType(SnackBar), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'allows requesting only the local turn before the opponent replies',
      (WidgetTester tester) async {
        final GameController controller = GameController();
        final GameMode previousMode = controller.gameInstance.gameMode;
        final RemoteMatchController? previousCoordinator =
            controller.remoteCoordinator;
        final NativeMillGameSession session = NativeMillGameSession(
          rulesPort: _HistoryRulesPort(activeSeat: PlayerSeat.first),
        );
        final _ResignOnlyRemoteController coordinator =
            _ResignOnlyRemoteController();
        session.remoteMeta = const MillRemoteSessionMeta(
          localSeat: PlayerSeat.second,
          hostPlaysWhite: true,
          transportKind: RemoteTransportKind.lan,
          role: RemoteRole.join,
          sessionId: 'lan-own-turn-takeback-test',
        );
        controller.bindActiveSession(session);
        controller.gameInstance.gameMode = GameMode.humanVsLAN;
        controller.remoteCoordinator = coordinator;
        addTearDown(() {
          controller.unbindActiveSession(session);
          controller.gameInstance.gameMode = previousMode;
          controller.remoteCoordinator = previousCoordinator;
          session.dispose();
        });

        Future<bool>? request;
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: currentNavigatorKey,
            scaffoldMessengerKey: rootScaffoldMessengerKey,
            localizationsDelegates: sanmillLocalizationsDelegates,
            supportedLocales: S.supportedLocales,
            home: Scaffold(
              body: FilledButton(
                onPressed: () {
                  request = controller.requestRemoteTakeBack(1);
                },
                child: const Text('Request own turn'),
              ),
            ),
          ),
        );

        expect(controller.isRemoteOpponentTurn, isTrue);
        await tester.tap(find.text('Request own turn'));
        await tester.pump();

        expect(coordinator.takeBackRequests, const <int>[1]);
        expect(
          find.text(
            'Requested to take back only your latest turn. Waiting for your '
            'opponent…',
          ),
          findsOneWidget,
        );

        coordinator.takeBackResult!.complete(true);
        await tester.pumpAndSettle();
        expect(await request, isTrue);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'shows board transformation waiting and rejection dialogs with tips off',
      (WidgetTester tester) async {
        final GameController controller = GameController();
        final GameMode previousMode = controller.gameInstance.gameMode;
        final RemoteMatchController? previousCoordinator =
            controller.remoteCoordinator;
        final NativeMillGameSession session = NativeMillGameSession(
          rulesPort: _HistoryRulesPort(),
        );
        final _ResignOnlyRemoteController coordinator =
            _ResignOnlyRemoteController();
        controller.bindActiveSession(session);
        controller.gameInstance.gameMode = GameMode.humanVsBluetooth;
        controller.remoteCoordinator = coordinator;
        addTearDown(() {
          controller.unbindActiveSession(session);
          controller.gameInstance.gameMode = previousMode;
          controller.remoteCoordinator = previousCoordinator;
          session.dispose();
        });

        Future<bool>? request;
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: currentNavigatorKey,
            scaffoldMessengerKey: rootScaffoldMessengerKey,
            localizationsDelegates: sanmillLocalizationsDelegates,
            supportedLocales: S.supportedLocales,
            home: Scaffold(
              body: FilledButton(
                onPressed: () {
                  request = controller.requestRemoteBoardTransform(
                    TransformationType.rotate180,
                  );
                },
                child: const Text('Request transformation'),
              ),
            ),
          ),
        );

        expect(DB().generalSettings.showGameTips, isFalse);
        await tester.tap(find.text('Request transformation'));
        await tester.pump();

        expect(
          coordinator.requestedBoardTransformation,
          TransformationType.rotate180.name,
        );
        expect(
          find.byKey(const Key('remote_board_transform_waiting_dialog')),
          findsOneWidget,
        );

        coordinator.boardTransformResult!.complete(false);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('remote_board_transform_result_dialog')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('remote_important_dialog_ok')));
        await tester.pumpAndSettle();
        expect(await request, isFalse);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });

  group('HistoryNavigator cloud takeback', () {
    testWidgets('waits for cloud approval without undoing the local session', (
      WidgetTester tester,
    ) async {
      final GameController controller = GameController();
      final GameMode previousMode = controller.gameInstance.gameMode;
      final RemoteMatchController? previousCoordinator =
          controller.remoteCoordinator;
      final _HistoryRulesPort rulesPort = _HistoryRulesPort();
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      final _ResignOnlyRemoteController coordinator =
          _ResignOnlyRemoteController();

      session.remoteMeta = const MillRemoteSessionMeta(
        localSeat: PlayerSeat.second,
        hostPlaysWhite: true,
        transportKind: RemoteTransportKind.cloud,
        role: RemoteRole.join,
        sessionId: 'cloud-takeback-test',
      );
      controller.bindActiveSession(session);
      controller.gameInstance.gameMode = GameMode.humanVsCloud;
      controller.remoteCoordinator = coordinator;
      addTearDown(() {
        controller.unbindActiveSession(session);
        controller.gameInstance.gameMode = previousMode;
        controller.remoteCoordinator = previousCoordinator;
        session.dispose();
      });

      Future<HistoryResponse?>? navigation;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: currentNavigatorKey,
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => FilledButton(
                onPressed: () {
                  navigation = HistoryNavigator.takeBackN(
                    context,
                    1,
                    pop: false,
                    toolbar: true,
                  );
                },
                child: const Text('Request takeback'),
              ),
            ),
          ),
        ),
      );

      expect(session.undoDepth, 1);
      await tester.tap(find.text('Request takeback'));
      await tester.pump();

      expect(coordinator.takeBackRequests, const <int>[1]);
      expect(session.undoDepth, 1);
      expect(rulesPort.undoCalls, 0);
      expect(navigation, isNotNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      final BuildContext dialogContext = tester.element(
        find.byType(AlertDialog),
      );
      expect(
        find.text(
          S.of(dialogContext).takeBackRequestSentWaitingForOpponentResponse,
        ),
        findsOneWidget,
      );

      coordinator.takeBackResult!.complete(true);
      await tester.pumpAndSettle();

      expect(await navigation, isA<HistoryOK>());
      expect(session.undoDepth, 1);
      expect(rulesPort.undoCalls, 0);
      expect(find.byType(AlertDialog), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('GameController remote approval dialogs', () {
    testWidgets(
      'shows an incoming takeback request through the root navigator',
      (WidgetTester tester) async {
        final GameController controller = GameController();
        final GameMode previousMode = controller.gameInstance.gameMode;
        final NativeMillGameSession session = NativeMillGameSession(
          rulesPort: _HistoryRulesPort(),
        );
        final _ResignOnlyRemoteController coordinator =
            _ResignOnlyRemoteController();

        controller.bindActiveSession(session);
        addTearDown(() async {
          if (identical(controller.remoteCoordinator, coordinator)) {
            await controller.disposeRemoteMatch();
          }
          controller.unbindActiveSession(session);
          controller.gameInstance.gameMode = previousMode;
          session.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: currentNavigatorKey,
            scaffoldMessengerKey: rootScaffoldMessengerKey,
            localizationsDelegates: sanmillLocalizationsDelegates,
            supportedLocales: S.supportedLocales,
            home: const Scaffold(body: SizedBox.shrink()),
          ),
        );

        await controller
            .createCloudRemoteController<_ResignOnlyRemoteController>(
              (RemoteGameAdapter game) async => coordinator,
              role: RemoteRole.host,
            );

        coordinator.emit(
          const RemoteTakeBackApprovalRequested(
            'takeback-request',
            3,
            scope: RemoteTakeBackScope.requesterTurnAndOpponentReply,
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(AlertDialog), findsOneWidget);

        final BuildContext dialogContext = tester.element(
          find.byType(AlertDialog),
        );
        expect(
          find.text(
            S.of(dialogContext).opponentRequestsTakeBackTurnAndReplyAccept,
          ),
          findsOneWidget,
        );
        await tester.tap(find.text(S.of(dialogContext).no));
        await tester.pumpAndSettle();

        expect(coordinator.respondedTakeBackRequestId, 'takeback-request');
        expect(coordinator.respondedTakeBackSteps, 3);
        expect(coordinator.respondedTakeBackAccepted, isFalse);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('distinguishes a request for only the opponent turn', (
      WidgetTester tester,
    ) async {
      final GameController controller = GameController();
      final GameMode previousMode = controller.gameInstance.gameMode;
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: _HistoryRulesPort(),
      );
      final _ResignOnlyRemoteController coordinator =
          _ResignOnlyRemoteController();

      controller.bindActiveSession(session);
      addTearDown(() async {
        if (identical(controller.remoteCoordinator, coordinator)) {
          await controller.disposeRemoteMatch();
        }
        controller.unbindActiveSession(session);
        controller.gameInstance.gameMode = previousMode;
        session.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: currentNavigatorKey,
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      await controller.createCloudRemoteController<_ResignOnlyRemoteController>(
        (RemoteGameAdapter game) async => coordinator,
        role: RemoteRole.host,
      );

      coordinator.emit(
        const RemoteTakeBackApprovalRequested(
          'takeback-own-turn-request',
          2,
          scope: RemoteTakeBackScope.requesterTurnOnly,
        ),
      );
      await tester.pump();

      final BuildContext dialogContext = tester.element(
        find.byType(AlertDialog),
      );
      expect(
        find.text(S.of(dialogContext).opponentRequestsTakeBackTurnAccept),
        findsOneWidget,
      );
      expect(
        find.text(
          S.of(dialogContext).opponentRequestsTakeBackTurnAndReplyAccept,
        ),
        findsNothing,
      );
      await tester.tap(find.text(S.of(dialogContext).no));
      await tester.pumpAndSettle();

      expect(
        coordinator.respondedTakeBackRequestId,
        'takeback-own-turn-request',
      );
      expect(coordinator.respondedTakeBackSteps, 2);
      expect(coordinator.respondedTakeBackAccepted, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('shows a readable incoming board transformation request', (
      WidgetTester tester,
    ) async {
      final GameController controller = GameController();
      final GameMode previousMode = controller.gameInstance.gameMode;
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: _HistoryRulesPort(),
      );
      final _ResignOnlyRemoteController coordinator =
          _ResignOnlyRemoteController();

      controller.bindActiveSession(session);
      addTearDown(() async {
        if (identical(controller.remoteCoordinator, coordinator)) {
          await controller.disposeRemoteMatch();
        }
        controller.unbindActiveSession(session);
        controller.gameInstance.gameMode = previousMode;
        session.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: currentNavigatorKey,
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      await controller.createCloudRemoteController<_ResignOnlyRemoteController>(
        (RemoteGameAdapter game) async => coordinator,
        role: RemoteRole.host,
      );
      coordinator.emit(
        RemoteBoardTransformApprovalRequested(
          'transform-request',
          TransformationType.rotate180.name,
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('remote_board_transform_request_dialog')),
        findsOneWidget,
      );
      final BuildContext dialogContext = tester.element(
        find.byKey(const Key('remote_board_transform_request_dialog')),
      );
      final String requestText = S
          .of(dialogContext)
          .opponentRequestsBoardTransform(
            S.of(dialogContext).boardTransformRotateDegrees(180),
          );
      final Text content = tester.widget<Text>(find.text(requestText));
      expect(content.style?.fontSize, greaterThanOrEqualTo(16));

      await tester.tap(find.byKey(const Key('remote_board_transform_accept')));
      await tester.pumpAndSettle();

      expect(coordinator.respondedBoardTransformRequestId, 'transform-request');
      expect(
        coordinator.respondedBoardTransformation,
        TransformationType.rotate180.name,
      );
      expect(coordinator.respondedBoardTransformAccepted, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('GameController.leaveRemoteMatch', () {
    test('leaves and disposes the active remote coordinator', () async {
      final GameController controller = GameController();
      final RemoteMatchController? previousCoordinator =
          controller.remoteCoordinator;
      final _ResignOnlyRemoteController coordinator =
          _ResignOnlyRemoteController();
      controller.remoteCoordinator = coordinator;
      addTearDown(() => controller.remoteCoordinator = previousCoordinator);

      await controller.leaveRemoteMatch();

      expect(coordinator.leaveCalls, 1);
      expect(coordinator.disposeCalls, 1);
      expect(controller.remoteCoordinator, isNull);
    });
  });
}

class _HistoryRulesPort implements NativeMillRulesPort {
  _HistoryRulesPort({PlayerSeat activeSeat = PlayerSeat.second})
    : _snapshot = GameStateSnapshot(
        gameId: GameId.mill,
        activeSeat: activeSeat,
        outcome: const GameOutcome.ongoing(),
        phase: 'placing',
      );

  GameStateSnapshot _snapshot;
  int undoCalls = 0;

  @override
  RuleSettings get ruleSettings => const RuleSettings();

  @override
  GameStateSnapshot get snapshot => _snapshot;

  @override
  int get undoDepth => 1 - undoCalls;

  @override
  int get redoDepth => undoCalls;

  @override
  GameStateSnapshot undo() {
    undoCalls += 1;
    _snapshot = const GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: PlayerSeat.first,
      outcome: GameOutcome.ongoing(),
      phase: 'placing',
    );
    return _snapshot;
  }

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ResignOnlyRemoteController
    implements RemoteMatchController, RemoteBoardTransformController {
  int resignCalls = 0;
  bool resignResult = true;
  int leaveCalls = 0;
  int disposeCalls = 0;
  int restartCalls = 0;
  final List<int> takeBackRequests = <int>[];
  Completer<bool>? takeBackResult;
  Completer<bool>? restartResult;
  Completer<bool>? boardTransformResult;
  String? requestedBoardTransformation;
  final StreamController<RemoteMatchEvent> _events =
      StreamController<RemoteMatchEvent>.broadcast();
  String? respondedTakeBackRequestId;
  int? respondedTakeBackSteps;
  bool? respondedTakeBackAccepted;
  String? respondedBoardTransformRequestId;
  String? respondedBoardTransformation;
  bool? respondedBoardTransformAccepted;

  @override
  final ValueNotifier<RemoteConnectionState> stateNotifier =
      ValueNotifier<RemoteConnectionState>(RemoteConnectionState.ready);

  @override
  Stream<RemoteMatchEvent> get events => _events.stream;

  @override
  RemoteConnectionState get state => stateNotifier.value;

  @override
  bool get isConnected => true;

  @override
  Map<String, Object?> get diagnosticSnapshot => const <String, Object?>{};

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await _events.close();
    stateNotifier.dispose();
  }

  void emit(RemoteMatchEvent event) {
    _events.add(event);
  }

  @override
  Future<void> leave() async {
    leaveCalls += 1;
  }

  @override
  Future<bool> requestTakeBack(int steps) {
    takeBackRequests.add(steps);
    final Completer<bool> result = Completer<bool>();
    takeBackResult = result;
    return result.future;
  }

  @override
  Future<void> respondToTakeBack({
    required String requestId,
    required int steps,
    required bool accepted,
  }) async {
    respondedTakeBackRequestId = requestId;
    respondedTakeBackSteps = steps;
    respondedTakeBackAccepted = accepted;
  }

  @override
  Future<bool> requestBoardTransform(String transformation) async {
    requestedBoardTransformation = transformation;
    final Completer<bool> result = Completer<bool>();
    boardTransformResult = result;
    return result.future;
  }

  @override
  Future<void> respondToBoardTransform({
    required String requestId,
    required String transformation,
    required bool accepted,
  }) async {
    respondedBoardTransformRequestId = requestId;
    respondedBoardTransformation = transformation;
    respondedBoardTransformAccepted = accepted;
  }

  @override
  Future<bool> resign() async {
    resignCalls += 1;
    return resignResult;
  }

  @override
  Future<bool> requestRestart() {
    restartCalls += 1;
    final Completer<bool> result = Completer<bool>();
    restartResult = result;
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
