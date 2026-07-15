// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/remote_play/bluetooth_adapter.dart';
import 'package:sanmill/remote_play/bluetooth_transport.dart';
import 'package:sanmill/remote_play/remote_models.dart';
import 'package:sanmill/remote_play/remote_transport.dart';

void main() {
  group('BluetoothTransport join role', () {
    test('deduplicates scan results by device id', () async {
      final FakeBluetoothAdapter adapter = FakeBluetoothAdapter()
        ..scanResultsOnStart = <BluetoothScanResult>[
          const BluetoothScanResult(
            deviceId: 'device-a',
            name: 'Sanmill A',
            rssi: -70,
          ),
          const BluetoothScanResult(
            deviceId: 'device-a',
            name: 'Sanmill A updated',
            rssi: -40,
          ),
        ];
      final BluetoothTransport transport = BluetoothTransport(
        role: RemoteRole.join,
        adapter: adapter,
      );

      final List<RemoteEndpoint> endpoints = await transport.discover(
        timeout: const Duration(milliseconds: 5),
      );

      expect(endpoints, hasLength(1));
      expect(endpoints.single.id, 'device-a');
      expect(endpoints.single.label, 'Sanmill A updated');
      expect(endpoints.single.metadata['rssi'], -40);
      expect(adapter.startScanCount, 1);
      expect(adapter.stopScanCount, 1);
      await transport.close();
    });

    test('surfaces permission denial and powered-off adapter', () async {
      final FakeBluetoothAdapter denied = FakeBluetoothAdapter()
        ..permissionsGranted = false
        ..permissionError = StateError('denied');
      final BluetoothTransport deniedTransport = BluetoothTransport(
        role: RemoteRole.join,
        adapter: denied,
      );
      await expectLater(
        deniedTransport.discover(timeout: Duration.zero),
        throwsA(isA<StateError>()),
      );
      await deniedTransport.close();

      final FakeBluetoothAdapter poweredOff = FakeBluetoothAdapter()
        ..availability = BluetoothAvailability.poweredOff;
      final BluetoothTransport poweredOffTransport = BluetoothTransport(
        role: RemoteRole.join,
        adapter: poweredOff,
      );
      await expectLater(
        poweredOffTransport.discover(timeout: Duration.zero),
        throwsA(
          isA<BluetoothUnavailableException>().having(
            (BluetoothUnavailableException error) => error.availability,
            'availability',
            BluetoothAvailability.poweredOff,
          ),
        ),
      );
      await poweredOffTransport.close();
    });

    test('uses safe 20 byte chunks then honors negotiated MTU', () async {
      final FakeBluetoothAdapter safeAdapter = FakeBluetoothAdapter()
        ..requestedMtu = 23;
      final BluetoothTransport safeTransport = BluetoothTransport(
        role: RemoteRole.join,
        adapter: safeAdapter,
      );
      await safeTransport.join(
        const RemoteEndpoint(id: 'safe', label: 'Safe device'),
      );
      await safeTransport.send(
        Uint8List.fromList(List<int>.generate(45, (int i) => i)),
      );
      expect(safeTransport.payloadLength, 20);
      expect(safeAdapter.writes.map((Uint8List value) => value.length), <int>[
        20,
        20,
        5,
      ]);
      await safeTransport.close();

      final FakeBluetoothAdapter mtuAdapter = FakeBluetoothAdapter()
        ..requestedMtu = 103;
      final BluetoothTransport mtuTransport = BluetoothTransport(
        role: RemoteRole.join,
        adapter: mtuAdapter,
      );
      await mtuTransport.join(
        const RemoteEndpoint(id: 'mtu', label: 'MTU device'),
      );
      await mtuTransport.send(
        Uint8List.fromList(List<int>.generate(205, (int i) => i & 0xff)),
      );
      expect(mtuTransport.payloadLength, 100);
      expect(mtuAdapter.writes.map((Uint8List value) => value.length), <int>[
        100,
        100,
        5,
      ]);
      await mtuTransport.close();
    });

    test('forwards notifications and reconnects after link loss', () async {
      final FakeBluetoothAdapter adapter = FakeBluetoothAdapter();
      final BluetoothTransport transport = BluetoothTransport(
        role: RemoteRole.join,
        adapter: adapter,
      );
      final List<RemoteTransportEvent> events = <RemoteTransportEvent>[];
      final StreamSubscription<RemoteTransportEvent> subscription = transport
          .events
          .listen(events.add);
      await transport.join(const RemoteEndpoint(id: 'peer', label: 'Peer'));

      adapter.emitNotification('peer', Uint8List.fromList(<int>[1, 2, 3]));
      await pumpEventQueue();
      expect(events.whereType<RemoteTransportData>().single.bytes, <int>[
        1,
        2,
        3,
      ]);

      adapter.centralConnections.add(
        const BluetoothConnectionEvent(deviceId: 'peer', connected: false),
      );
      await pumpEventQueue();
      expect(transport.state, RemoteConnectionState.reconnecting);
      await transport.reconnect();
      expect(adapter.connectCount, 2);
      expect(transport.isConnected, isTrue);
      await subscription.cancel();
      await transport.close();
    });
  });

  group('BluetoothTransport host role', () {
    test('waits for subscription and fragments notifications', () async {
      final FakeBluetoothAdapter adapter = FakeBluetoothAdapter()
        ..maximumNotificationLength = 20;
      final BluetoothTransport transport = BluetoothTransport(
        role: RemoteRole.host,
        adapter: adapter,
      );
      final List<RemoteTransportEvent> events = <RemoteTransportEvent>[];
      final StreamSubscription<RemoteTransportEvent> subscription = transport
          .events
          .listen(events.add);
      await transport.startHost(
        const RemoteHostOptions(advertisedLabel: 'Sanmill test'),
      );
      expect(transport.isConnected, isFalse);

      adapter.peripheralConnections.add(
        const BluetoothConnectionEvent(deviceId: 'central', connected: true),
      );
      adapter.peripheralSubscriptions.add(
        const BluetoothSubscriptionEvent(
          deviceId: 'central',
          characteristicId: BluetoothTransport.notifyCharacteristicId,
          subscribed: true,
        ),
      );
      await pumpEventQueue();
      expect(transport.isConnected, isTrue);

      await transport.send(
        Uint8List.fromList(List<int>.generate(45, (int i) => i)),
      );
      expect(
        adapter.notificationsSent.map((Uint8List value) => value.length),
        <int>[20, 20, 5],
      );

      adapter.emitPeripheralWrite('central', Uint8List.fromList(<int>[7, 8]));
      await pumpEventQueue();
      expect(events.whereType<RemoteTransportData>().single.bytes, <int>[7, 8]);
      await subscription.cancel();
      await transport.close();
      expect(adapter.writeHandler, isNull);
    });

    test(
      'reports notification failures without stalling later sends',
      () async {
        final FakeBluetoothAdapter adapter = FakeBluetoothAdapter();
        final BluetoothTransport transport = BluetoothTransport(
          role: RemoteRole.host,
          adapter: adapter,
        );
        final List<RemoteTransportFailure> failures =
            <RemoteTransportFailure>[];
        final StreamSubscription<RemoteTransportEvent> subscription = transport
            .events
            .where(
              (RemoteTransportEvent event) => event is RemoteTransportFailure,
            )
            .listen((RemoteTransportEvent event) {
              failures.add(event as RemoteTransportFailure);
            });
        await transport.startHost(const RemoteHostOptions());
        adapter.peripheralConnections.add(
          const BluetoothConnectionEvent(deviceId: 'central', connected: true),
        );
        adapter.peripheralSubscriptions.add(
          const BluetoothSubscriptionEvent(
            deviceId: 'central',
            characteristicId: BluetoothTransport.notifyCharacteristicId,
            subscribed: true,
          ),
        );
        await pumpEventQueue();

        adapter.notificationError = StateError('notify failed');
        await expectLater(
          transport.send(Uint8List.fromList(<int>[1])),
          throwsA(isA<StateError>()),
        );
        expect(failures, hasLength(1));
        adapter.notificationError = null;
        await transport.send(Uint8List.fromList(<int>[2]));
        expect(adapter.notificationsSent.last, <int>[2]);
        await subscription.cancel();
        await transport.close();
      },
    );
  });
}

class FakeBluetoothAdapter implements BluetoothAdapter {
  bool permissionsGranted = true;
  Error? permissionError;
  BluetoothAvailability availability = BluetoothAvailability.ready;
  bool peripheralHostingSupported = true;
  int requestedMtu = 23;
  int? maximumNotificationLength;
  Error? notificationError;
  List<BluetoothScanResult> scanResultsOnStart = <BluetoothScanResult>[];
  int startScanCount = 0;
  int stopScanCount = 0;
  int connectCount = 0;
  int disconnectCount = 0;
  void Function(String deviceId, Uint8List value)? writeHandler;
  final List<Uint8List> writes = <Uint8List>[];
  final List<Uint8List> notificationsSent = <Uint8List>[];

  final StreamController<BluetoothScanResult> scans =
      StreamController<BluetoothScanResult>.broadcast(sync: true);
  final StreamController<BluetoothAvailability> availabilities =
      StreamController<BluetoothAvailability>.broadcast(sync: true);
  final StreamController<BluetoothConnectionEvent> centralConnections =
      StreamController<BluetoothConnectionEvent>.broadcast(sync: true);
  final StreamController<BluetoothConnectionEvent> peripheralConnections =
      StreamController<BluetoothConnectionEvent>.broadcast(sync: true);
  final StreamController<BluetoothSubscriptionEvent> peripheralSubscriptions =
      StreamController<BluetoothSubscriptionEvent>.broadcast(sync: true);
  final StreamController<BluetoothMtuEvent> peripheralMtus =
      StreamController<BluetoothMtuEvent>.broadcast(sync: true);
  final Map<String, StreamController<Uint8List>> _notificationControllers =
      <String, StreamController<Uint8List>>{};

  @override
  bool get supportsPeripheralHosting => peripheralHostingSupported;

  @override
  Stream<BluetoothScanResult> get scanResults => scans.stream;

  @override
  Stream<BluetoothAvailability> get availabilityChanges =>
      availabilities.stream;

  @override
  Stream<BluetoothConnectionEvent> get centralConnectionChanges =>
      centralConnections.stream;

  @override
  Stream<BluetoothConnectionEvent> get peripheralConnectionChanges =>
      peripheralConnections.stream;

  @override
  Stream<BluetoothSubscriptionEvent> get peripheralSubscriptionChanges =>
      peripheralSubscriptions.stream;

  @override
  Stream<BluetoothMtuEvent> get peripheralMtuChanges => peripheralMtus.stream;

  @override
  Future<BluetoothAvailability> getAvailability() async => availability;

  @override
  Future<bool> hasPermissions() async => permissionsGranted;

  @override
  Future<void> requestPermissions() async {
    final Error? error = permissionError;
    if (error != null) {
      throw error;
    }
    permissionsGranted = true;
  }

  @override
  Future<void> startScan({required String serviceId}) async {
    startScanCount++;
    for (final BluetoothScanResult result in scanResultsOnStart) {
      scans.add(result);
    }
  }

  @override
  Future<void> stopScan() async {
    stopScanCount++;
  }

  @override
  Future<void> connect(String deviceId) async {
    connectCount++;
  }

  @override
  Future<void> disconnect(String deviceId) async {
    disconnectCount++;
  }

  @override
  Future<void> subscribe({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) async {}

  @override
  Stream<Uint8List> notifications({
    required String deviceId,
    required String characteristicId,
  }) {
    return _notificationControllers
        .putIfAbsent(
          deviceId,
          () => StreamController<Uint8List>.broadcast(sync: true),
        )
        .stream;
  }

  void emitNotification(String deviceId, Uint8List bytes) {
    _notificationControllers[deviceId]!.add(bytes);
  }

  @override
  Future<int> requestMtu(String deviceId, int preferredMtu) async =>
      requestedMtu;

  @override
  Future<void> write({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
    required Uint8List value,
  }) async {
    writes.add(Uint8List.fromList(value));
  }

  @override
  Future<void> preparePeripheral({
    required String serviceId,
    required String writeCharacteristicId,
    required String notifyCharacteristicId,
    required void Function(String deviceId, Uint8List value) onWrite,
  }) async {
    if (!peripheralHostingSupported) {
      throw UnsupportedError('Peripheral mode unavailable.');
    }
    writeHandler = onWrite;
  }

  void emitPeripheralWrite(String deviceId, Uint8List bytes) {
    writeHandler!(deviceId, bytes);
  }

  @override
  Future<void> startAdvertising({
    required String serviceId,
    required String localName,
  }) async {}

  @override
  Future<void> stopAdvertising() async {}

  @override
  Future<void> clearPeripheralServices() async {}

  @override
  Future<int?> maximumNotifyLength(String deviceId) async =>
      maximumNotificationLength;

  @override
  Future<void> notify({
    required String deviceId,
    required String characteristicId,
    required Uint8List value,
  }) async {
    final Error? error = notificationError;
    if (error != null) {
      throw error;
    }
    notificationsSent.add(Uint8List.fromList(value));
  }

  @override
  void clearPeripheralWriteHandler() {
    writeHandler = null;
  }

  @override
  Future<void> dispose() async {
    await scans.close();
    await availabilities.close();
    await centralConnections.close();
    await peripheralConnections.close();
    await peripheralSubscriptions.close();
    await peripheralMtus.close();
    for (final StreamController<Uint8List> controller
        in _notificationControllers.values) {
      await controller.close();
    }
  }
}
