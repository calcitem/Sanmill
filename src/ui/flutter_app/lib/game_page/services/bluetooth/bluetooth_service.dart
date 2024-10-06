import 'dart:async';
import 'dart:convert';

import 'package:flutter_nearby_connections/flutter_nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../shared/services/logger.dart';

/// BluetoothService handles Bluetooth connectivity, permissions, sending, and receiving data using flutter_nearby_connections.
class BluetoothService {
  // Singleton pattern to ensure only one instance of BluetoothService exists.
  BluetoothService._privateConstructor();
  static const String _logTag = "[BluetoothService]";
  static final BluetoothService instance =
      BluetoothService._privateConstructor();

  // NearbyService instance from flutter_nearby_connections
  final NearbyService _nearbyService = NearbyService();

  // Public getter for _nearbyService
  NearbyService get nearbyService => _nearbyService;

  // Stream controller for incoming moves, using a broadcast stream for multiple listeners.
  final StreamController<String> _moveController =
      StreamController<String>.broadcast();
  Stream<String> get moveStream => _moveController.stream;

  // Subscription for state changes
  StreamSubscription<dynamic>? _stateChangedSubscription;

  // Subscription for data received
  StreamSubscription<dynamic>? _dataReceivedSubscription;

  // Device ID of the connected peer
  String? _connectedDeviceId;

  // Flag to indicate if this device is the advertiser (master)
  bool _isAdvertiser = false;

  /// Initializes the NearbyService and sets up listeners.
  Future<void> initNearbyService() async {
    logger.i("$_logTag Initializing NearbyService...");

    // Request necessary permissions
    await _requestNearbyPermissions();

    bool _isNearbyServiceRunning = false;

    final permissionStatus = await Permission.bluetoothScan.status;
    logger.i("Bluetooth Scan Permission: $permissionStatus");

    // Initialize NearbyService
    await _nearbyService.init(
      serviceType: "mill_game", // Must be <=15 chars
      strategy: Strategy.P2P_POINT_TO_POINT,
      deviceName:
          "Mill_${DateTime.now().millisecondsSinceEpoch}", // Unique device name
      callback: (bool isRunning) {
        logger.i("NearbyService callback triggered: isRunning = $isRunning");
        _isNearbyServiceRunning = isRunning;
        if (isRunning) {
          logger.i("NearbyService started successfully.");
        } else {
          logger.e("NearbyService failed to start.");
        }
      },
    );

    // Listen to state changes
    _stateChangedSubscription = _nearbyService.stateChangedSubscription(
      callback: (dynamic devices) {
        // Handle the devices list as List<Device>
        _onStateChanged(devices as List<Device>);
      },
    );

    // Listen to data received
    _dataReceivedSubscription = _nearbyService.dataReceivedSubscription(
      callback: (dynamic data) {
        _onDataReceived(data);
      },
    );

    // Start advertising and browsing
    try {
      logger.i("Attempting to start advertising peer...");
      if (_isNearbyServiceRunning) {
        await Future.delayed(const Duration(seconds: 20));
        await await _nearbyService.startAdvertisingPeer();
        logger.i("Started advertising peer successfully.");
      } else {
        logger.e("NearbyService failed to start, aborting advertising/browsing.");
      }
    } catch (e) {
      logger.e("Error starting advertising peer: $e");
    }

    try {
      await Future.delayed(const Duration(seconds: 20));
      logger.i("Attempting to start browsing for peers...");
      await _nearbyService.startBrowsingForPeers();
      logger.i("Started browsing for peers successfully.");
    } catch (e) {
      logger.e("Error starting browsing for peers: $e");
    }

  }

  /// Requests the necessary permissions for NearbyService.
  Future<void> _requestNearbyPermissions() async {
    // Request Bluetooth permissions
    if (await Permission.bluetoothScan.isDenied) {
      await Permission.bluetoothScan.request();
    } else {
      logger.i("Bluetooth scan permission granted.");
    }

    if (await Permission.bluetoothConnect.isDenied) {
      await Permission.bluetoothConnect.request();
    } else {
      logger.i("Bluetooth connect permission granted.");
    }

    if (await Permission.bluetoothAdvertise.isDenied) {
      await Permission.bluetoothAdvertise.request();
    } else {
      logger.i("Bluetooth advertise permission granted.");
    }

    // Request location permission, required for Bluetooth scanning on Android 10 and above
    if (await Permission.location.isDenied) {
      await Permission.location.request();
    } else {
      logger.i("Location permission granted.");
    }

    // Optionally, check if permissions are permanently denied and handle by navigating to the app settings.
    if (await Permission.bluetoothScan.isPermanentlyDenied ||
        await Permission.bluetoothConnect.isPermanentlyDenied ||
        await Permission.bluetoothAdvertise.isPermanentlyDenied ||
        await Permission.location.isPermanentlyDenied) {
      openAppSettings();
    } else {
      logger.i("Permissions granted.");
    }
  }

  /// Handles state changes from NearbyService.
  void _onStateChanged(List<Device> devices) {
    for (final Device device in devices) {
      if (device.state == SessionState.connected &&
          _connectedDeviceId == null) {
        // Device connected
        logger.i(
            "$_logTag Connected to ${device.deviceName} (${device.deviceId})");
        _connectedDeviceId = device.deviceId;

        // Determine role based on device's initial state
        _isAdvertiser = devices.any((Device device) =>
        device.state == SessionState.connected &&
            device.deviceName.contains("Mill_"));

        logger
            .i("$_logTag Role assigned: ${_isAdvertiser ? 'Master' : 'Slave'}");

        // Set up game state if needed
      } else if (device.state == SessionState.notConnected &&
          _connectedDeviceId == device.deviceId) {
        // Device disconnected
        logger.i(
            "$_logTag Disconnected from ${device.deviceName} (${device.deviceId})");
        _connectedDeviceId = null;
        _isAdvertiser = false;
      } else if (device.state == SessionState.connecting) {
        // Found a device, send an invitation
        logger.i(
            "$_logTag Found device: ${device.deviceName} (${device.deviceId}), inviting...");
        _nearbyService.invitePeer(
            deviceID: device.deviceId, deviceName: device.deviceName);
      } else if (device.state == SessionState.connected) {
        logger.i(
            "$_logTag Connecting to ${device.deviceName} (${device.deviceId})");
      }
    }
  }

  /// Handles incoming data from NearbyService.
  void _onDataReceived(dynamic data) {
    try {
      // Cast the dynamic data to a String
      final String receivedData = data as String;

      // Decode the received String as a JSON object
      final Map<String, dynamic> decoded =
          jsonDecode(receivedData) as Map<String, dynamic>;

      // Check if the move key exists and process the move
      if (decoded.containsKey('move')) {
        final String move = decoded['move'].toString().trim();
        logger.t("$_logTag Data received: $move");
        _moveController.add(move);
      }
    } catch (e) {
      logger.e("$_logTag Error processing received data: $e");
    }
  }

  /// Sends a move to the connected peer.
  Future<void> sendMove(String moveStr) async {
    if (_connectedDeviceId != null) {
      try {
        final Map<String, String> message = <String, String>{'move': moveStr};
        final String encoded = jsonEncode(message);
        await _nearbyService.sendMessage(_connectedDeviceId!, encoded);
        logger.i("$_logTag Sent move: $moveStr");
      } catch (e) {
        logger.e("$_logTag Error sending move: $e");
      }
    } else {
      logger.w("$_logTag No connected device to send move.");
    }
  }

  /// Disconnects from the connected peer.
  Future<void> disconnect() async {
    if (_connectedDeviceId != null) {
      await _nearbyService.disconnectPeer(deviceID: _connectedDeviceId);
      logger.i("$_logTag Disconnected from $_connectedDeviceId");
      _connectedDeviceId = null;
      _isAdvertiser = false;
    }
  }

  /// Cleans up resources.
  Future<void> dispose() async {
    return;  // TODO(BT): Remove it?
    try {
      await _moveController.close();
      await _nearbyService.stopAdvertisingPeer();
      await _nearbyService.stopBrowsingForPeers();
      await _stateChangedSubscription?.cancel();
      await _dataReceivedSubscription?.cancel();
      await disconnect();
    } catch (e) {
      logger.e("$_logTag Error disposing resources: $e");
    }
  }
}
