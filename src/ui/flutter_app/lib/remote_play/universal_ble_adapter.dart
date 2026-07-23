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
  Future<void> connect(String deviceId) async {
    // Android 15+ surfaces GATT_CONNECTION_TIMEOUT as status 147. A single
    // retry after releasing the GATT client clears most transient failures.
    Object? lastError;
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        await UniversalBle.connect(
          deviceId,
          timeout: const Duration(seconds: 20),
          autoConnect: false,
        );
        return;
      } on Object catch (error) {
        lastError = error;
        if (!_isTransientBleConnectError(error) || attempt == 1) {
          rethrow;
        }
        try {
          await UniversalBle.disconnect(
            deviceId,
            timeout: const Duration(seconds: 5),
          );
        } on Object {
          // Best-effort cleanup before retry.
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    throw lastError ?? StateError('BLE connect failed without an error.');
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
      orElse: () => throw StateError('Bluetooth game service was not found.'),
    );
    service.characteristics.firstWhere(
      (BleCharacteristic value) =>
          value.uuid.toLowerCase() == characteristicId.toLowerCase(),
      orElse: () => throw StateError(
        'Bluetooth game notification characteristic was not found.',
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
  }) async {
    final String? advertisedName =
        defaultTargetPlatform == TargetPlatform.windows ? null : localName;
    // Android legacy ADV/scan-response packets are each capped at 31 bytes.
    // A 128-bit service UUID (18 bytes) plus a device name overflows the
    // primary packet (observed: 37 bytes → ADVERTISE_FAILED_DATA_TOO_LARGE).
    // Put service UUIDs in the scan response so name+flags fit in ADV.
    final bool servicesInScanResponse =
        defaultTargetPlatform == TargetPlatform.android &&
        advertisedName != null;
    final PeripheralPlatformConfig? platformConfig = servicesInScanResponse
        ? PeripheralPlatformConfig(
            android: PeripheralAndroidOptions(addServicesInScanResponse: true),
          )
        : null;

    // Clear a leftover advertiser from a previous host attempt. Android returns
    // ADVERTISE_FAILED_ALREADY_STARTED (surfaced as state=error) otherwise.
    try {
      await UniversalBlePeripheral.stopAdvertising();
    } on Object {
      // Ignore stop failures when nothing is advertising.
    }

    Object? lastError;
    for (int attempt = 0; attempt < 2; attempt++) {
      final Completer<({PeripheralAdvertisingState state, String? error})>
      advertisingReady =
          Completer<({PeripheralAdvertisingState state, String? error})>();
      final StreamSubscription<BlePeripheralAdvertisingStateChanged>
      stateSubscription = UniversalBlePeripheral.advertisingStateStream.listen((
        BlePeripheralAdvertisingStateChanged event,
      ) {
        if (event.state == PeripheralAdvertisingState.advertising ||
            event.state == PeripheralAdvertisingState.error) {
          if (!advertisingReady.isCompleted) {
            advertisingReady.complete((state: event.state, error: event.error));
          }
        }
      });
      try {
        await UniversalBlePeripheral.startAdvertising(
          services: <String>[serviceId],
          localName: advertisedName,
          platformConfig: platformConfig,
        );
        final ({PeripheralAdvertisingState state, String? error}) result =
            await advertisingReady.future.timeout(const Duration(seconds: 5));
        if (result.state == PeripheralAdvertisingState.advertising) {
          return;
        }
        lastError = result.error ?? result.state.name;
        final bool alreadyStarted = (result.error ?? '').toLowerCase().contains(
          'already',
        );
        if (!alreadyStarted || attempt == 1) {
          break;
        }
        try {
          await UniversalBlePeripheral.stopAdvertising();
        } on Object {
          // Retry after a best-effort stop.
        }
      } finally {
        await stateSubscription.cancel();
      }
    }
    throw StateError('BLE advertising failed to start: $lastError');
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

bool _isTransientBleConnectError(Object error) {
  final String text = error.toString().toLowerCase();
  // 147 = BluetoothGatt.GATT_CONNECTION_TIMEOUT (Android 15+).
  // 133 = legacy GATT_ERROR often used for the same timeout case.
  return text.contains('147') ||
      text.contains('133') ||
      text.contains('timeout') ||
      text.contains('gatt_connection_timeout') ||
      text.contains('gatt_error');
}
