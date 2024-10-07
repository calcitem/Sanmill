// bluetoolth_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../shared/services/logger.dart';

/// BluetoothService handles Bluetooth connectivity, permissions, sending, and receiving data.
class BluetoothService {
  // Singleton pattern to ensure only one instance of BluetoothService exists.
  BluetoothService._privateConstructor();
  static const String _logTag = "[BluetoothService]";
  static final BluetoothService instance =
      BluetoothService._privateConstructor();

  // Bluetooth connection object.
  BluetoothConnection? _connection;

  // Stream controller for incoming moves, using a broadcast stream for multiple listeners.
  final StreamController<String> _moveController =
      StreamController<String>.broadcast();
  Stream<String> get moveStream => _moveController.stream;

  /// Enables Bluetooth if not already enabled.
  Future<void> enableBluetooth() async {
    final bool? isBluetoothEnabled =
        await FlutterBluetoothSerial.instance.isEnabled;
    if (isBluetoothEnabled == false) {
      await FlutterBluetoothSerial.instance.requestEnable();
    }
  }

  /// Starts discovery for nearby Bluetooth devices, including their names if available.
  Stream<BluetoothDiscoveryResult> startDiscovery() {
    return FlutterBluetoothSerial.instance
        .startDiscovery()
        .map((BluetoothDiscoveryResult result) {
      // Log the discovered device's address and name (if available)
      final String deviceName = result.device.name ?? 'Unknown device';
      logger.i("Discovered ${result.device.address} ($deviceName)");
      return result; // Return the result as is
    });
  }

  /// Cancels an ongoing Bluetooth discovery.
  Future<void> cancelDiscovery() async {
    await FlutterBluetoothSerial.instance.cancelDiscovery();
  }

  /// Gets the bond state of a specific Bluetooth device.
  Future<BluetoothBondState> getBondState(BluetoothDevice device) async {
    return FlutterBluetoothSerial.instance
        .getBondStateForAddress(device.address);
  }

  /// Attempts to pair with a Bluetooth device.
  Future<bool> pairDevice(BluetoothDevice device) async {
    final bool? bonded = await FlutterBluetoothSerial.instance
        .bondDeviceAtAddress(device.address);
    return bonded ?? false;
  }

  /// Connects to a Bluetooth device.
  Future<void> connect(BluetoothDevice device) async {
    try {
      // Establish connection to the Bluetooth device.
      _connection = await BluetoothConnection.toAddress(device.address);
      logger.i("$_logTag Connected to ${device.name}");

      // Listen for incoming data from the Bluetooth device.
      _connection!.input!.listen(_onDataReceived).onDone(() {
        logger.i("$_logTag Disconnected by remote device.");
        _moveController.close();
      });
    } catch (e) {
      logger.e("$_logTag Error connecting to device: $e");
    }
  }

  /// Handles incoming data from the Bluetooth connection.
  void _onDataReceived(Uint8List data) {
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
    if (_connection != null && _connection!.isConnected) {
      try {
        // Encode the move and send it via Bluetooth.
        _connection!.output.add(utf8.encode("$moveStr\n"));
        await _connection!.output.allSent;
        logger.i("$_logTag Sent move: $moveStr");
      } catch (e) {
        logger.e("$_logTag Error sending move: $e");
      }
    } else {
      logger.w("$_logTag Not connected to any Bluetooth device.");
    }
  }

  /// Disconnects the Bluetooth connection.
  Future<void> disconnect() async {
    try {
      await _connection?.close();
      logger.i("$_logTag Bluetooth connection closed.");
    } catch (e) {
      logger.e("$_logTag Error disconnecting Bluetooth: $e");
    }
  }

  /// Requests the necessary Bluetooth permissions for Android 12+.
  Future<void> requestBluetoothPermissions() async {
    // Request the BLUETOOTH_SCAN permission, required for discovering nearby Bluetooth devices.
    if (await Permission.bluetoothScan.isDenied) {
      await Permission.bluetoothScan.request();
    }

    // Request the BLUETOOTH_CONNECT permission, required for connecting to Bluetooth devices.
    if (await Permission.bluetoothConnect.isDenied) {
      await Permission.bluetoothConnect.request();
    }

    // Request the BLUETOOTH_ADVERTISE permission, required for advertising Bluetooth services (if applicable).
    if (await Permission.bluetoothAdvertise.isDenied) {
      await Permission.bluetoothAdvertise.request();
    }

    // Request the location permission, required for Bluetooth scanning on Android 10 and above.
    if (await Permission.location.isDenied) {
      await Permission.location.request();
    }

    // Optionally, check if permissions are permanently denied and handle by navigating to the app settings.
    if (await Permission.bluetoothScan.isPermanentlyDenied) {
      openAppSettings();
    }
  }

  /// Retrieves the local Bluetooth address.
  Future<String?> getLocalAddress() async {
    return FlutterBluetoothSerial.instance.address;
  }

  /// Disposes the Bluetooth service by closing the stream controller and disconnecting Bluetooth.
  void dispose() {
    _moveController.close();
    disconnect();
  }
}
