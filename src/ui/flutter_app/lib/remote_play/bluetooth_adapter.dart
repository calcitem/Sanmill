// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:typed_data';

enum BluetoothAvailability {
  unknown,
  ready,
  poweredOff,
  unauthorized,
  unsupported,
}

class BluetoothScanResult {
  const BluetoothScanResult({
    required this.deviceId,
    required this.name,
    required this.rssi,
  });

  final String deviceId;
  final String name;
  final int? rssi;
}

class BluetoothConnectionEvent {
  const BluetoothConnectionEvent({
    required this.deviceId,
    required this.connected,
    this.error,
  });

  final String deviceId;
  final bool connected;
  final String? error;
}

class BluetoothSubscriptionEvent {
  const BluetoothSubscriptionEvent({
    required this.deviceId,
    required this.characteristicId,
    required this.subscribed,
  });

  final String deviceId;
  final String characteristicId;
  final bool subscribed;
}

class BluetoothMtuEvent {
  const BluetoothMtuEvent({required this.deviceId, required this.mtu});

  final String deviceId;
  final int mtu;
}

/// Small, injectable surface around the BLE plugin.
///
/// The transport depends on this interface rather than static plugin callbacks,
/// which keeps protocol and lifecycle tests deterministic and hardware-free.
abstract interface class BluetoothAdapter {
  bool get supportsPeripheralHosting;

  Stream<BluetoothScanResult> get scanResults;

  Stream<BluetoothAvailability> get availabilityChanges;

  Stream<BluetoothConnectionEvent> get centralConnectionChanges;

  Stream<BluetoothConnectionEvent> get peripheralConnectionChanges;

  Stream<BluetoothSubscriptionEvent> get peripheralSubscriptionChanges;

  Stream<BluetoothMtuEvent> get peripheralMtuChanges;

  Future<BluetoothAvailability> getAvailability();

  Future<bool> hasPermissions();

  Future<void> requestPermissions();

  Future<void> startScan({required String serviceId});

  Future<void> stopScan();

  Future<void> connect(String deviceId);

  Future<void> disconnect(String deviceId);

  Future<void> subscribe({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  });

  Stream<Uint8List> notifications({
    required String deviceId,
    required String characteristicId,
  });

  Future<int> requestMtu(String deviceId, int preferredMtu);

  Future<void> write({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
    required Uint8List value,
  });

  Future<void> preparePeripheral({
    required String serviceId,
    required String writeCharacteristicId,
    required String notifyCharacteristicId,
    required void Function(String deviceId, Uint8List value) onWrite,
  });

  Future<void> startAdvertising({
    required String serviceId,
    required String localName,
  });

  Future<void> stopAdvertising();

  Future<void> clearPeripheralServices();

  Future<int?> maximumNotifyLength(String deviceId);

  Future<void> notify({
    required String deviceId,
    required String characteristicId,
    required Uint8List value,
  });

  void clearPeripheralWriteHandler();

  Future<void> dispose();
}
