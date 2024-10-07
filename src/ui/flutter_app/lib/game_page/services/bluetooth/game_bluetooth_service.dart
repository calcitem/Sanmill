// game_bluetooth_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../shared/services/logger.dart';

/// GameBluetoothService handles Bluetooth connectivity, permissions, sending, receiving data, and advertising.
/// Utilizes flutter_blue_plus for Bluetooth Low Energy (BLE) functionalities and native Android code for advertising.
class GameBluetoothService {
  // Singleton pattern to ensure only one instance of BluetoothService exists.
  GameBluetoothService._privateConstructor();
  static const String _logTag = "[BluetoothService]";
  static final GameBluetoothService instance =
      GameBluetoothService._privateConstructor();

  // Native channel for calling Android methods
  static const MethodChannel _advertiseChannel =
      MethodChannel('com.calcitem.sanmill/advertise');

  // Currently connected Bluetooth device.
  BluetoothDevice? _connectedDevice;

  // Currently connected characteristic for communication.
  BluetoothCharacteristic? _writeCharacteristic;

  // Stream controller for incoming moves, using a broadcast stream for multiple listeners.
  final StreamController<String> _moveController =
      StreamController<String>.broadcast();
  Stream<String> get moveStream => _moveController.stream;

  // StreamController for device connection events
  final StreamController<BluetoothDevice> _deviceConnectedController =
      StreamController<BluetoothDevice>.broadcast();
  Stream<BluetoothDevice> get onDeviceConnected =>
      _deviceConnectedController.stream;

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

      _deviceConnectedController
          .add(device); // Notify listeners of the connection

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
              '123e4567-e89b-12d3-a456-426614174000') {
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

  /// Starts BLE advertising by invoking a native Android method.
  Future<void> startAdvertising() async {
    try {
      await _advertiseChannel.invokeMethod('startAdvertising');
      logger.i("$_logTag Advertising started.");
    } on PlatformException catch (e) {
      logger.e("$_logTag Failed to start advertising: ${e.message}");
    }
  }

  /// Stops BLE advertising by invoking a native Android method.
  Future<void> stopAdvertising() async {
    try {
      await _advertiseChannel.invokeMethod('stopAdvertising');
      logger.i("$_logTag Advertising stopped.");
    } on PlatformException catch (e) {
      logger.e("$_logTag Failed to stop advertising: ${e.message}");
    }
  }

  /// Disposes the Bluetooth service by closing the stream controller and disconnecting Bluetooth.
  void dispose() {
    stopAdvertising();
    _moveController.close();
    _deviceConnectedController.close();
    disconnect();
    logger.i("$_logTag BluetoothService disposed.");
  }
}
