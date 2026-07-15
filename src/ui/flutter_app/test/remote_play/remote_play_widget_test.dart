// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/widgets/dialogs/bluetooth_config_dialog.dart';
import 'package:sanmill/game_page/widgets/dialogs/lan_config_dialog.dart';
import 'package:sanmill/game_page/widgets/game_page.dart';
import 'package:sanmill/game_platform/game_menu.dart';
import 'package:sanmill/games/mill/mill_game_module.dart';
import 'package:sanmill/games/mill/mill_route_ids.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/remote_play/remote_models.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/locale_helper.dart';
import '../helpers/mocks/mock_database.dart';
import '../helpers/test_native_library.dart';

final String? _nativeLibrarySkipReason = nativeLibrarySkipReason();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (_nativeLibrarySkipReason == null) {
      await initRustLibForTests();
    }
  });

  tearDownAll(disposeRustLibForTests);

  testWidgets('LAN and Bluetooth are independent play-mode entries', (
    WidgetTester tester,
  ) async {
    late List<GameModeEntry> entries;
    await tester.pumpWidget(
      makeTestableWidget(
        Builder(
          builder: (BuildContext context) {
            entries = MillGameModule().playModes(context);
            final Iterable<GameModeEntry> remoteEntries = entries.where(
              (GameModeEntry entry) =>
                  entry.id == MillRouteIds.humanVsLan ||
                  entry.id == MillRouteIds.humanVsBluetooth,
            );
            return Column(
              children: remoteEntries
                  .map(
                    (GameModeEntry entry) =>
                        Text(entry.label, key: entry.menuKey),
                  )
                  .toList(growable: false),
            );
          },
        ),
      ),
    );

    expect(find.byKey(const Key('drawer_item_human_vs_lan')), findsOneWidget);
    expect(
      find.byKey(const Key('drawer_item_human_vs_bluetooth')),
      findsOneWidget,
    );
    expect(MillRouteIds.humanVsLan, isNot(MillRouteIds.humanVsBluetooth));
  });

  testWidgets('Bluetooth role tabs keep the dialog size stable', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(makeTestableWidget(const BluetoothConfigDialog()));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('bluetooth_dialog_content'))).width,
      320,
    );
    final Size hostSize = tester.getSize(find.byType(AlertDialog));

    await tester.tap(find.byIcon(Icons.bluetooth_searching));
    await tester.pumpAndSettle();
    final Size joinSize = tester.getSize(find.byType(AlertDialog));

    expect(joinSize, hostSize);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('LAN role tabs and feedback keep the dialog size stable', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(makeTestableWidget(const LanConfigDialog()));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('lan_dialog_content'))).width,
      320,
    );
    final Size hostSize = tester.getSize(find.byType(AlertDialog));

    await tester.tap(find.byIcon(Icons.wifi_find));
    await tester.pumpAndSettle();
    final Size joinSize = tester.getSize(find.byType(AlertDialog));

    expect(joinSize, hostSize);

    await tester.enterText(
      find.byKey(const Key('lan_address_field')),
      'invalid-address',
    );
    await tester.tap(find.byKey(const Key('lan_join_button')));
    await tester.pump();

    expect(find.byKey(const Key('remote_status_text')), findsOneWidget);
    expect(tester.getSize(find.byType(AlertDialog)), hostSize);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'LAN hosting locks dismissal until the service is stopped',
    (WidgetTester tester) async {
      const MethodChannel deviceInfoChannel = MethodChannel(
        'dev.fluttercommunity.plus/device_info',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            deviceInfoChannel,
            (MethodCall call) async => <String, Object?>{
              'computerName': 'Widget Test Mac',
              'hostName': 'widget-test.local',
              'arch': 'arm64',
              'model': 'WidgetTest1,1',
              'modelName': 'Widget Test Mac',
              'kernelVersion': 'test',
              'osRelease': 'test',
              'majorVersion': 1,
              'minorVersion': 0,
              'patchVersion': 0,
              'activeCPUs': 1,
              'memorySize': 1,
              'cpuFrequency': 1,
              'systemGUID': 'widget-test',
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(deviceInfoChannel, null),
      );
      PackageInfo.setMockInitialValues(
        appName: 'Sanmill',
        packageName: 'com.calcitem.sanmill',
        version: 'test',
        buildNumber: '1',
        buildSignature: '',
      );

      final Database? previousDatabase = Database.instance;
      DB.instance = MockDB();
      addTearDown(() => DB.instance = previousDatabase);

      final GameController controller = GameController();
      final GameMode previousMode = controller.gameInstance.gameMode;
      final NativeMillGameSession session = NativeMillGameSession();
      controller.bindActiveSession(session);
      addTearDown(() async {
        await controller.disposeRemoteMatch();
        controller.unbindActiveSession(session);
        controller.gameInstance.gameMode = previousMode;
        session.dispose();
      });

      final int port = (await tester.runAsync(() async {
        final ServerSocket probe = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final int availablePort = probe.port;
        await probe.close();
        return availablePort;
      }))!;

      await tester.pumpWidget(
        makeTestableWidget(
          Builder(
            builder: (BuildContext context) => FilledButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => const LanConfigDialog(),
              ),
              child: const Text('Open LAN'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open LAN'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('lan_port_field')), '$port');

      await tester.tap(find.byKey(const Key('lan_host_button')));
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('lan_stop_host_button')),
      );

      expect(find.text('Stop Hosting'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Close'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<SegmentedButton<RemoteRole>>(
              find.byKey(const Key('lan_role_selector')),
            )
            .onSelectionChanged,
        isNull,
      );
      expect(
        tester.widget<PopScope<dynamic>>(find.byType(PopScope)).canPop,
        isFalse,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(LanConfigDialog), findsOneWidget);

      await tester.tap(find.byKey(const Key('lan_stop_host_button')));
      await _pumpUntilFound(tester, find.byKey(const Key('lan_host_button')));

      expect(find.text('Start Hosting'), findsOneWidget);
      expect(find.text('Server is stopped.'), findsOneWidget);
      expect(controller.remoteCoordinator, isNull);
      expect(controller.gameInstance.gameMode, previousMode);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Close'))
            .onPressed,
        isNotNull,
      );
      expect(
        tester.widget<PopScope<dynamic>>(find.byType(PopScope)).canPop,
        isTrue,
      );

      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      expect(find.byType(LanConfigDialog), findsNothing);
    },
    skip: !Platform.isMacOS || _nativeLibrarySkipReason != null,
  );

  testWidgets('Linux Bluetooth dialog exposes join only', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    await tester.pumpWidget(makeTestableWidget(const BluetoothConfigDialog()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bluetooth_host_unsupported')), findsOneWidget);
    expect(find.byKey(const Key('bluetooth_join_button')), findsOneWidget);
    expect(find.byKey(const Key('bluetooth_host_button')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('reconnect state displays a board-locking overlay', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<RemoteConnectionState> state =
        ValueNotifier<RemoteConnectionState>(RemoteConnectionState.ready);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      makeTestableWidget(
        Stack(
          children: <Widget>[RemoteConnectionOverlay(stateListenable: state)],
        ),
      ),
    );
    expect(find.byKey(const Key('remote_reconnecting_overlay')), findsNothing);

    state.value = RemoteConnectionState.reconnecting;
    await tester.pump();
    expect(
      find.byKey(const Key('remote_reconnecting_overlay')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('remote_reconnecting_overlay')),
        matching: find.byType(AbsorbPointer),
      ),
      findsOneWidget,
    );
  });
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (int attempt = 0; attempt < 50 && finder.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
  expect(finder, findsOneWidget);
}
