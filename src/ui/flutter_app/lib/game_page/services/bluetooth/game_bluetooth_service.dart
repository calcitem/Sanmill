// game_bluetooth_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../shared/services/logger.dart';

/// GameBluetoothService handles Bluetooth connectivity, permissions, sending, and receiving data.
/// Utilizes flutter_blue_plus for Bluetooth Low Energy (BLE) functionalities.
class GameBluetoothService {
  // Singleton pattern to ensure only one instance of BluetoothService exists.
  GameBluetoothService._privateConstructor();
  static const String _logTag = "[BluetoothService]";
  static final GameBluetoothService instance =
      GameBluetoothService._privateConstructor();

  // Currently connected Bluetooth device.
  BluetoothDevice? _connectedDevice;

  // Currently connected characteristic for communication.
  BluetoothCharacteristic? _writeCharacteristic;

  // Stream controller for incoming moves, using a broadcast stream for multiple listeners.
  final StreamController<String> _moveController =
      StreamController<String>.broadcast();
  Stream<String> get moveStream => _moveController.stream;

  /// Enables Bluetooth if not already enabled.
  Future<void> enableBluetooth() async {
    final bool isOn = await FlutterBluePlus.isSupported;
    if (!isOn) {
      try {
        await FlutterBluePlus.turnOn(timeout: 120);
        logger.i("$_logTag Bluetooth has been enabled.");
      } catch (e) {
        logger.e("$_logTag Failed to enable Bluetooth: $e");
        rethrow;
      }
    } else {
      logger.i("$_logTag Bluetooth is already enabled.");
    }
  }

  /// Starts scanning for nearby Bluetooth Low Energy devices.
  Stream<ScanResult> startScan() {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
    return FlutterBluePlus.scanResults.expand((List<ScanResult> results) {
      for (final ScanResult result in results) {
        final String deviceName = result.device.platformName.isNotEmpty
            ? result.device.platformName
            : 'Unknown device';
        logger.i(
            "Discovered ${result.device.remoteId} ($deviceName) with RSSI ${result.rssi}");
      }
      return results;
    });
  }

  /// Stops an ongoing Bluetooth scan.
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    logger.i("$_logTag Stopped scanning for Bluetooth devices.");
  }

  /// Gets the connection state of a specific Bluetooth device.
  Future<BluetoothConnectionState> getDeviceState(
      BluetoothDevice device) async {
    return device.connectionState.first;
  }

  /// Attempts to connect to a Bluetooth device and logs additional device information.
  Future<void> connect(BluetoothDevice device) async {
    try {
      logger.i(
          "$_logTag Connecting to ${device.platformName} (${device.remoteId})");

      // Establish connection to the Bluetooth device.
      await device.connect(timeout: const Duration(seconds: 15));
      _connectedDevice = device;
      logger.i("$_logTag Connected to ${device.platformName}");

      // Log additional device information.
      logger.i("$_logTag Device Advertised Name: ${device.advName}");
      logger.i("$_logTag Device ID: ${device.remoteId}");
      logger.i(
          "$_logTag Is Device AutoConnect Enabled: ${device.isAutoConnectEnabled}");
      logger.i("$_logTag Current MTU Size: ${device.mtuNow}");
      if (device.isConnected) {
        logger.i("$_logTag Device is currently connected.");
      } else {
        logger.w("$_logTag Device is not connected.");
      }

      // Discover services after connection.
      await _discoverServices(device);
    } catch (e) {
      logger.e("$_logTag Error connecting to device: $e");
      rethrow;
    }
  }

  /// Discovers services and characteristics for the connected device.
  Future<void> _discoverServices(BluetoothDevice device) async {
    try {
      final List<BluetoothService> services = await device.discoverServices();
      for (final BluetoothService service in services) {
        logger.i("$_logTag Found service with UUID: ${service.uuid}");
        for (final BluetoothCharacteristic characteristic
            in service.characteristics) {
          logger.i(
              "$_logTag Found characteristic with UUID: ${characteristic.uuid}");

          // Replace 'YOUR_CHARACTERISTIC_UUID' with the actual UUID.
          if (characteristic.uuid.toString() ==
              '12345678-1234-5678-1234-567812345678') {
            _writeCharacteristic = characteristic;

            // Enable notifications for the characteristic.
            await characteristic.setNotifyValue(true);
            characteristic.lastValueStream.listen(_onDataReceived);
            logger.i(
                "$_logTag Subscribed to characteristic ${characteristic.uuid}");
          }
        }
      }

      if (_writeCharacteristic == null) {
        logger.w("$_logTag Desired characteristic not found on device.");
      }
    } catch (e) {
      logger.e("$_logTag Error discovering services: $e");
      rethrow;
    }
  }

  /// Handles incoming data from the Bluetooth characteristic.
  void _onDataReceived(List<int> data) {
    try {
      final String received = utf8.decode(data);
      logger.t("$_logTag Data received: $received");

      // Assuming moves are sent as strings, process the incoming move.
      final String move = received.trim();
      _moveController.add(move);
    } catch (e) {
      logger.e("$_logTag Error processing received data: $e");
    }
  }

  /// Sends a move over the Bluetooth connection.
  Future<void> sendMove(String moveStr) async {
    if (_writeCharacteristic != null) {
      try {
        // Encode the move and send it via the characteristic.
        await _writeCharacteristic!
            .write(utf8.encode("$moveStr\n"), withoutResponse: true);
        logger.i("$_logTag Sent move: $moveStr");
      } catch (e) {
        logger.e("$_logTag Error sending move: $e");
      }
    } else {
      logger.w("$_logTag Write characteristic is not available.");
    }
  }

  /// Disconnects from the currently connected Bluetooth device.
  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
        logger
            .i("$_logTag Disconnected from ${_connectedDevice!.platformName}");
        _connectedDevice = null;
        _writeCharacteristic = null;
      } catch (e) {
        logger.e("$_logTag Error disconnecting Bluetooth: $e");
      }
    } else {
      logger.w("$_logTag No Bluetooth device is currently connected.");
    }
  }

  /// Requests the necessary Bluetooth permissions for Android.
  Future<void> requestBluetoothPermissions() async {
    // Request relevant permissions for Bluetooth operations.
    await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.location,
    ].request();
  }

  /// Disposes the Bluetooth service by closing the stream controller and disconnecting Bluetooth.
  void dispose() {
    _moveController.close();
    disconnect();
    logger.i("$_logTag BluetoothService disposed.");
  }
}

class GameBluetoothAdvertiser {
  static const String serviceUuidString = 'abcd1234-5678-90ab-cdef12345678';
  static const String characteristicUuidString =
      '12345678-1234-5678-1234-567812345678';

  late BluetoothCharacteristic _characteristic;
  BluetoothDevice? _connectedDevice;

  final StreamController<String> _dataStreamController =
      StreamController<String>.broadcast();
  Stream<String> get dataStream => _dataStreamController.stream;

  /// Initializes the Bluetooth characteristic for advertising.
  Future<void> initializeService(DeviceIdentifier remoteId) async {
    final Guid serviceUuid = Guid(serviceUuidString);
    final Guid characteristicUuid = Guid(characteristicUuidString);

    // Initialize characteristic based on the BluetoothCharacteristic definition
    _characteristic = BluetoothCharacteristic(
      remoteId: remoteId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
    );
  }

  /// Starts advertising the Bluetooth characteristic, making it discoverable to other devices.
  Future<void> startAdvertising() async {
    try {
      // Ensure Bluetooth permissions are granted
      await requestBluetoothPermissions();

      // Currently, FlutterBluePlus does not directly support service advertisement
      // due to platform limitations, so you may need platform-specific code
      logger.i(
          "[Advertiser] Started advertising service with UUID: $serviceUuidString");

      // Listen for incoming data
      _characteristic.lastValueStream.listen((List<int> data) {
        _onDataReceived(data);
      });
    } catch (e) {
      logger.e("[Advertiser] Error starting advertisement: $e");
    }
  }

  /// Stops advertising the Bluetooth characteristic.
  Future<void> stopAdvertising() async {
    try {
      // The `stopAdvertising` API isn't directly available in flutter_blue_plus.
      logger.i("[Advertiser] Stopped advertising service.");
    } catch (e) {
      logger.e("[Advertiser] Error stopping advertisement: $e");
    }
  }

  /// Handles incoming data from the connected device.
  void _onDataReceived(List<int> data) {
    try {
      final String received = utf8.decode(data);
      logger.i("[Advertiser] Data received: $received");
      _dataStreamController.add(received);
    } catch (e) {
      logger.e("[Advertiser] Error processing received data: $e");
    }
  }

  /// Sends data to the connected device.
  Future<void> sendData(String message) async {
    if (_connectedDevice != null) {
      try {
        final List<int> encodedData = utf8.encode(message);
        await _characteristic.write(encodedData, withoutResponse: true);
        logger.i("[Advertiser] Sent data: $message");
      } catch (e) {
        logger.e("[Advertiser] Error sending data: $e");
      }
    } else {
      logger.w("[Advertiser] No connected device available.");
    }
  }

  /// Requests the necessary Bluetooth permissions for Android.
  Future<void> requestBluetoothPermissions() async {
    await <Permission>[
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();
  }

  /// Disposes the Bluetooth service by stopping advertising and closing the stream controller.
  void dispose() {
    stopAdvertising();
    _dataStreamController.close();
    logger.i("[Advertiser] Bluetooth Advertiser disposed.");
  }
}
