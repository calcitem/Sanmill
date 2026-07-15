// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import 'bluetooth_adapter.dart';

class UniversalBluetoothAdapter implements BluetoothAdapter {
  UniversalBluetoothAdapter() {
    UniversalBle.onConnectionChange = _onCentralConnectionChanged;
  }

  final StreamController<BluetoothConnectionEvent>
  _centralConnectionController =
      StreamController<BluetoothConnectionEvent>.broadcast(sync: true);

  @override
  bool get supportsPeripheralHosting =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.linux;

  @override
  Stream<BluetoothScanResult> get scanResults => UniversalBle.scanStream.map(
    (BleDevice device) => BluetoothScanResult(
      deviceId: device.deviceId,
      name: (device.name?.isNotEmpty ?? false) ? device.name! : device.deviceId,
      rssi: device.rssi,
    ),
  );

  @override
  Stream<BluetoothAvailability> get availabilityChanges =>
      UniversalBle.availabilityStream.map(_centralAvailability);

  @override
  Stream<BluetoothConnectionEvent> get centralConnectionChanges =>
      _centralConnectionController.stream;

  @override
  Stream<BluetoothConnectionEvent> get peripheralConnectionChanges =>
      UniversalBlePeripheral.connectionStateStream.map(
        (BlePeripheralConnectionStateChanged event) => BluetoothConnectionEvent(
          deviceId: event.deviceId,
          connected: event.connected,
        ),
      );

  @override
  Stream<BluetoothSubscriptionEvent> get peripheralSubscriptionChanges =>
      UniversalBlePeripheral.characteristicSubscriptionStream.map(
        (BlePeripheralCharacteristicSubscriptionChanged event) =>
            BluetoothSubscriptionEvent(
              deviceId: event.deviceId,
              characteristicId: event.characteristicId,
              subscribed: event.isSubscribed,
            ),
      );

  @override
  Stream<BluetoothMtuEvent> get peripheralMtuChanges =>
      UniversalBlePeripheral.mtuChangedStream.map(
        (BlePeripheralMtuChanged event) =>
            BluetoothMtuEvent(deviceId: event.deviceId, mtu: event.mtu),
      );

  @override
  Future<BluetoothAvailability> getAvailability() async {
    return _centralAvailability(
      await UniversalBle.getBluetoothAvailabilityState(),
    );
  }

  @override
  Future<bool> hasPermissions() => UniversalBle.hasPermissions();

  @override
  Future<void> requestPermissions() => UniversalBle.requestPermissions();

  @override
  Future<void> startScan({required String serviceId}) {
    return UniversalBle.startScan(
      scanFilter: ScanFilter(withServices: <String>[serviceId]),
    );
  }

  @override
  Future<void> stopScan() => UniversalBle.stopScan();

  @override
  Future<void> connect(String deviceId) {
    return UniversalBle.connect(
      deviceId,
      timeout: const Duration(seconds: 15),
      autoConnect: false,
    );
  }

  @override
  Future<void> disconnect(String deviceId) {
    return UniversalBle.disconnect(
      deviceId,
      timeout: const Duration(seconds: 10),
    );
  }

  @override
  Future<void> subscribe({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) async {
    final List<BleService> services = await UniversalBle.discoverServices(
      deviceId,
    );
    final BleService service = services.firstWhere(
      (BleService value) => value.uuid.toLowerCase() == serviceId.toLowerCase(),
      orElse: () => throw StateError('Sanmill BLE service was not found.'),
    );
    service.characteristics.firstWhere(
      (BleCharacteristic value) =>
          value.uuid.toLowerCase() == characteristicId.toLowerCase(),
      orElse: () => throw StateError(
        'Sanmill BLE notification characteristic was not found.',
      ),
    );
    await UniversalBle.subscribeNotifications(
      deviceId,
      serviceId,
      characteristicId,
    );
  }

  @override
  Stream<Uint8List> notifications({
    required String deviceId,
    required String characteristicId,
  }) {
    return UniversalBle.characteristicValueStream(deviceId, characteristicId);
  }

  @override
  Future<int> requestMtu(String deviceId, int preferredMtu) {
    return UniversalBle.requestMtu(deviceId, preferredMtu);
  }

  @override
  Future<void> write({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
    required Uint8List value,
  }) {
    return UniversalBle.write(
      deviceId,
      serviceId,
      characteristicId,
      value,
      withoutResponse: false,
    );
  }

  @override
  Future<void> preparePeripheral({
    required String serviceId,
    required String writeCharacteristicId,
    required String notifyCharacteristicId,
    required void Function(String deviceId, Uint8List value) onWrite,
  }) async {
    final BlePeripheralCapabilities capabilities =
        await UniversalBlePeripheral.getCapabilities();
    if (!capabilities.supportsPeripheralMode) {
      throw UnsupportedError('BLE peripheral mode is unavailable.');
    }
    final PeripheralReadinessState readiness =
        await UniversalBlePeripheral.getAvailabilityState();
    if (readiness != PeripheralReadinessState.ready) {
      throw StateError('BLE peripheral is not ready: ${readiness.name}.');
    }
    await UniversalBlePeripheral.clearServices();
    UniversalBlePeripheral.setWriteRequestHandlers((
      String deviceId,
      String characteristicId,
      int _,
      Uint8List? value,
    ) {
      if (characteristicId.toLowerCase() ==
              writeCharacteristicId.toLowerCase() &&
          value != null) {
        onWrite(deviceId, Uint8List.fromList(value));
      }
      return PeripheralWriteRequestResult();
    });
    await UniversalBlePeripheral.addService(
      BlePeripheralService(
        uuid: serviceId,
        characteristics: <BlePeripheralCharacteristic>[
          BlePeripheralCharacteristic(
            uuid: writeCharacteristicId,
            properties: <CharacteristicProperty>[
              CharacteristicProperty.write,
              CharacteristicProperty.writeWithoutResponse,
            ],
            permissions: <PeripheralAttributePermission>[
              PeripheralAttributePermission.writeable,
            ],
          ),
          BlePeripheralCharacteristic(
            uuid: notifyCharacteristicId,
            properties: <CharacteristicProperty>[CharacteristicProperty.notify],
            permissions: <PeripheralAttributePermission>[
              PeripheralAttributePermission.readable,
            ],
          ),
        ],
      ),
    );
  }

  @override
  Future<void> startAdvertising({
    required String serviceId,
    required String localName,
  }) {
    return UniversalBlePeripheral.startAdvertising(
      services: <String>[serviceId],
      localName: defaultTargetPlatform == TargetPlatform.windows
          ? null
          : localName,
    );
  }

  @override
  Future<void> stopAdvertising() => UniversalBlePeripheral.stopAdvertising();

  @override
  Future<void> clearPeripheralServices() =>
      UniversalBlePeripheral.clearServices();

  @override
  Future<int?> maximumNotifyLength(String deviceId) =>
      UniversalBlePeripheral.getMaximumNotifyLength(deviceId);

  @override
  Future<void> notify({
    required String deviceId,
    required String characteristicId,
    required Uint8List value,
  }) {
    return UniversalBlePeripheral.updateCharacteristicValue(
      characteristicId: characteristicId,
      value: value,
      deviceId: deviceId,
    );
  }

  @override
  void clearPeripheralWriteHandler() {
    UniversalBlePeripheral.setWriteRequestHandlers(null);
  }

  void _onCentralConnectionChanged(
    String deviceId,
    bool connected,
    String? error,
  ) {
    if (!_centralConnectionController.isClosed) {
      _centralConnectionController.add(
        BluetoothConnectionEvent(
          deviceId: deviceId,
          connected: connected,
          error: error,
        ),
      );
    }
  }

  BluetoothAvailability _centralAvailability(AvailabilityState state) {
    return switch (state) {
      AvailabilityState.poweredOn => BluetoothAvailability.ready,
      AvailabilityState.poweredOff ||
      AvailabilityState.resetting => BluetoothAvailability.poweredOff,
      AvailabilityState.unauthorized => BluetoothAvailability.unauthorized,
      AvailabilityState.unsupported => BluetoothAvailability.unsupported,
      AvailabilityState.unknown => BluetoothAvailability.unknown,
    };
  }

  @override
  Future<void> dispose() async {
    UniversalBle.onConnectionChange = null;
    await _centralConnectionController.close();
  }
}
