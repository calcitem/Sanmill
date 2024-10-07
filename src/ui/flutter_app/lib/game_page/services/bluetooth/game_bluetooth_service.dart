// game_bluetooth_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../shared/services/logger.dart';

/// Enum to define the role of the device - Advertiser or Connector
enum DeviceRole { advertiser, connector }

/// GameBluetoothService handles Bluetooth connectivity, permissions, sending, receiving data, and advertising.
/// Utilizes flutter_blue_plus for Bluetooth Low Energy (BLE) functionalities and native Android code for advertising.
class GameBluetoothService {
  // Singleton pattern with role
  GameBluetoothService._privateConstructor(this.role) {
    _listenToAdvertiseEvents(); // Start listening to native events
  }

  static GameBluetoothService? _instance;

  /// Method to get a single instance of GameBluetoothService, ensuring role-based initialization
  static GameBluetoothService getInstance(DeviceRole role) {
    if (_instance == null || _instance!.role != role) {
      _instance = GameBluetoothService._privateConstructor(role);
    }
    return _instance!;
  }

  static const String _logTag = "[BluetoothService]";
  static const MethodChannel _advertiseChannel =
      MethodChannel('com.calcitem.sanmill/advertise');

  // Event channel to receive events from native code
  static const EventChannel _advertiseEventChannel =
      EventChannel('com.calcitem.sanmill/advertise_events');

  static const String serviceUuid = '123e4567-e89b-12d3-a456-426614174000';
  static const String characteristicUuid =
      '123e4567-e89b-12d3-a456-426614174001';
  static const String cccdUuid = '00002902-0000-1000-8000-00805f9b34fb';

  // The role of the device (advertiser or connector)
  final DeviceRole role;

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;

  // Stream controllers for moves and device connection events
  final StreamController<String> _moveController =
      StreamController<String>.broadcast();
  Stream<String> get moveStream => _moveController.stream;

  // StreamController for device connection events
  final StreamController<BluetoothDevice> _deviceConnectedController =
      StreamController<BluetoothDevice>.broadcast();

  Stream<BluetoothDevice> get onDeviceConnected =>
      _deviceConnectedController.stream;

  // Flag to track if advertising is active
  bool _isAdvertising = false;
  Timer? _advertisingTimeoutTimer;

  /// Enables Bluetooth if not already enabled.
  Future<void> enableBluetooth() async {
    final bool isSupported = await FlutterBluePlus.isSupported;

    // Use the adapterState stream to check if Bluetooth is on
    final BluetoothAdapterState currentState =
        await FlutterBluePlus.adapterState.first;

    if (isSupported && currentState != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn(timeout: 120);
        logger.i("$_logTag Bluetooth has been enabled.");
      } catch (e) {
        logger.e("$_logTag Failed to enable Bluetooth: $e");
        rethrow;
      }
    } else if (!isSupported) {
      logger.e("$_logTag Bluetooth is not supported on this device.");
    } else {
      logger.i("$_logTag Bluetooth is already enabled.");
    }
  }

  /// Starts scanning for nearby Bluetooth Low Energy devices, only if role is Connector.
  Stream<ScanResult> startScan() {
    if (role != DeviceRole.connector) {
      logger.w("$_logTag This device is not set as connector.");
      return const Stream<ScanResult>.empty();
    }
    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 5),
      withServices: <Guid>[Guid(serviceUuid)],
    );
    return FlutterBluePlus.scanResults.expand((List<ScanResult> results) {
      for (final ScanResult result in results) {
        final String deviceName = result.device.platformName.isNotEmpty
            ? result.device.platformName
            : 'Unknown device';
        logger.i(
            "Discovered ${result.device.remoteId} ($deviceName) with RSSI ${result.rssi}");
        logger.i('发现设备: ${result.device.platformName}');
        logger.i('服务UUIDs: ${result.advertisementData.serviceUuids}');
        // 检查设备是否广播所需的服务UUID
        if (result.advertisementData.serviceUuids.contains(Guid(serviceUuid))) {
          logger.i('设备 ${result.device.platformName} 具有服务 UUID！');
          // 继续连接或执行其他操作
        }
      }
      return results;
    });
  }

  /// Stops an ongoing Bluetooth scan.
  Future<void> stopScan() async {
    if (role != DeviceRole.connector) {
      logger.w("$_logTag This device is not set as connector.");
      return;
    }
    await FlutterBluePlus.stopScan();
    logger.i("$_logTag Stopped scanning for Bluetooth devices.");
  }

  /// Gets the connection state of a specific Bluetooth device.
  Future<BluetoothConnectionState> getDeviceState(
      BluetoothDevice device) async {
    return device.connectionState.first;
  }

  /// Connects to a Bluetooth device if the role is Connector and logs additional device information.
  Future<void> connect(BluetoothDevice device) async {
    if (role != DeviceRole.connector) {
      logger.w("$_logTag This device is not set as connector.");
      return;
    }

    try {
      logger.i(
          "$_logTag Connecting to ${device.platformName} (${device.remoteId})");

      // Stop advertising before attempting to connect to avoid conflicts
      if (_isAdvertising) {
        await stopAdvertising();
      }

      // Establish connection to the Bluetooth device.
      await device.connect(timeout: const Duration(seconds: 15));
      _connectedDevice = device;
      logger.i("$_logTag Connected to ${device.platformName}");

      // Listen for connection state changes to monitor disconnects.
      device.connectionState.listen((BluetoothConnectionState state) {
        logger.i("Connection state changed: $state");
        if (state == BluetoothConnectionState.disconnected) {
          logger.w("Device disconnected during operation.");
          // Perform any necessary cleanup or reconnection here
          _connectedDevice = null;
          _writeCharacteristic = null;
          // Optionally, you could attempt to reconnect automatically
          // Uncomment the following line if you want auto-reconnect
          // connect(device);
        }
      });

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

      // Notify listeners of the connection
      _deviceConnectedController.add(device);

      // Optional delay to allow connection to stabilize before discovering services
      await Future<void>.delayed(const Duration(seconds: 2));

      // Discover services after connection.
      await _discoverServices(device);
    } catch (e) {
      logger.e("$_logTag Error connecting to device: $e");
      rethrow;
    }
  }

  /// Discovers services and characteristics for the connected device, enabling notifications
  /// on specific characteristics and listening for data updates.
  Future<void> _discoverServices(BluetoothDevice device) async {
    try {
      // Delay slightly to ensure the connection is stable before discovering services
      await Future<void>.delayed(const Duration(seconds: 1));

      // Discover available services on the connected device
      final List<BluetoothService> services = await device.discoverServices();

      // List to hold futures for enabling notifications on multiple characteristics simultaneously
      final List<Future> notificationFutures = <Future>[];

      for (final BluetoothService service in services) {
        logger.i("$_logTag Found service with UUID: ${service.uuid}");

        for (final BluetoothCharacteristic characteristic
            in service.characteristics) {
          logger.i(
              "$_logTag Found characteristic with UUID: ${characteristic.uuid}");

          if (characteristic.uuid.toString() == characteristicUuid) {
            _writeCharacteristic = characteristic;

            // Check if the characteristic supports notifications or indications
            final CharacteristicProperties properties =
                characteristic.properties;
            if (properties.notify || properties.indicate) {
              try {
                // Look for CCCD (Client Characteristic Configuration Descriptor)
                BluetoothDescriptor? cccdDescriptor;
                for (final BluetoothDescriptor descriptor
                    in characteristic.descriptors) {
                  if (descriptor.uuid.toString() == cccdUuid) {
                    cccdDescriptor = descriptor;
                    break;
                  }
                }

                if (cccdDescriptor != null) {
                  // Enable notifications by writing to the CCCD descriptor
                  await cccdDescriptor.write(<int>[0x01, 0x00]);

                  // Enable notifications on the characteristic
                  await characteristic.setNotifyValue(true);

                  // Check if notifications were successfully enabled
                  if (characteristic.isNotifying) {
                    // Listen for incoming data
                    characteristic.lastValueStream.listen(
                      _onDataReceived,
                      onError: (error) {
                        logger.e("$_logTag Error in receiving data: $error");
                      },
                    );
                    logger.i(
                        "$_logTag Notifications enabled for characteristic ${characteristic.uuid}");
                  } else {
                    logger.e(
                        "$_logTag Failed to enable notifications for characteristic ${characteristic.uuid}");
                  }
                } else {
                  logger.e(
                      "$_logTag CCCD not found for characteristic ${characteristic.uuid}");
                }
              } catch (e) {
                logger.e(
                    "$_logTag Exception when enabling notifications for ${characteristic.uuid}: $e");
              }
            } else {
              logger.w(
                  "$_logTag Characteristic ${characteristic.uuid} does not support notifications or indications.");
            }
          }
        }
      }

      // Check if the write characteristic was successfully found and set
      if (_writeCharacteristic == null) {
        logger.w("$_logTag Desired characteristic not found on device.");
      }
    } catch (e) {
      // Handle cases where the device disconnects before service discovery completes
      if (e.toString().contains("device is disconnected")) {
        logger.w(
            "$_logTag Device disconnected before service discovery. Reconnecting...");
        try {
          // Reconnect to the device after a short delay
          await Future.delayed(const Duration(seconds: 2));
          await device.connect();
          await _discoverServices(device); // Retry discovering services
        } catch (reconnectError) {
          logger.e("$_logTag Reconnection failed: $reconnectError");
          rethrow;
        }
      } else {
        logger.e("$_logTag Error discovering services: $e");
        rethrow;
      }
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
    try {
      final result = await _advertiseChannel
          .invokeMethod('sendMove', <String, String>{"move": moveStr});
      logger.i("Move sent successfully: $result");
    } catch (e) {
      logger.e("Error sending move: $e");
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

  /// Starts BLE advertising with timeout handling
  Future<void> startAdvertising() async {
    if (role != DeviceRole.advertiser) {
      logger.w("$_logTag This device is not set as advertiser.");
      return;
    }

    if (_isAdvertising) {
      logger.w("$_logTag Advertising is already active.");
      return;
    }
    try {
      await _advertiseChannel.invokeMethod('startAdvertising');
      _isAdvertising = true;
      logger.i("$_logTag Advertising started.");

      // Set up a timeout to stop advertising automatically if no connection is made.
      _advertisingTimeoutTimer?.cancel();
      _advertisingTimeoutTimer = Timer(const Duration(seconds: 60), () {
        if (_isAdvertising) {
          stopAdvertising();
          logger.i("$_logTag Advertising stopped due to timeout.");
        }
      });
    } on PlatformException catch (e) {
      _isAdvertising = false;
      logger.e("$_logTag Failed to start advertising: ${e.message}");
    }
  }

  /// Stops BLE advertising by invoking a native Android method.
  Future<void> stopAdvertising() async {
    if (!_isAdvertising) {
      logger.w("$_logTag Advertising is not active.");
      return;
    }
    try {
      await _advertiseChannel.invokeMethod('stopAdvertising');
      _isAdvertising = false;
      _advertisingTimeoutTimer?.cancel(); // Cancel any active timeout timer
      logger.i("$_logTag Advertising stopped.");
    } on PlatformException catch (e) {
      logger.e("$_logTag Failed to stop advertising: ${e.message}");
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

  /// Listens to events from the native Android code via EventChannel
  void _listenToAdvertiseEvents() {
    _advertiseEventChannel.receiveBroadcastStream().listen((event) {
      logger.i("$_logTag Advertise event received: $event");
      // If the event contains data, process it with _onDataReceived
      if (event is String && event.startsWith("Received data:")) {
        final String data = event.replaceFirst("Received data: ", "");
        _onDataReceived(utf8.encode(data));
      }
      if (event.toString().startsWith("Device connected:")) {
        // Extract the device address from the event
        final String deviceAddress =
            event.toString().substring("Device connected: ".length);
        logger.i("$_logTag Device connected: $deviceAddress");

        // Create a BluetoothDevice instance from the address
        final BluetoothDevice device = BluetoothDevice.fromId(deviceAddress);

        // Emit the device connected event so UI can listen and respond
        _deviceConnectedController.add(device);
      }
    }, onError: (error) {
      logger.e("$_logTag Advertise error received: $error");
    });
  }

  /// Disposes the Bluetooth service by closing the stream controller, stopping advertising, and disconnecting Bluetooth.
  void dispose() {
    stopAdvertising();
    _advertisingTimeoutTimer?.cancel();
    _moveController.close();
    _deviceConnectedController.close();
    disconnect();
    logger.i("$_logTag BluetoothService disposed.");
  }
}
