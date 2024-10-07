import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../shared/services/logger.dart';
import 'game_bluetooth_service.dart';

enum RoomAction { create, join }

class GameBluetoothPage extends StatefulWidget {
  const GameBluetoothPage({super.key});

  @override
  GameBluetoothPageState createState() => GameBluetoothPageState();
}

class GameBluetoothPageState extends State<GameBluetoothPage> {
  final GameBluetoothService _bluetoothService = GameBluetoothService.instance;
  StreamSubscription<String>? _bluetoothMoveSubscription;
  bool _isBluetoothConnected = false;
  String _bluetoothStatus = "Disconnected";
  String? _currentRoomId;
  List<ScanResult> _availableDevices = <ScanResult>[];
  ScanResult? _selectedDevice; // Changed to not be late, as it may be null
  BluetoothDevice? _connectedDevice;
  Timer? _advertisingTimer;
  int _advertisingTimeout = 60; // Advertising timeout in seconds

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showRoomSelectionDialog();
    });

    // Subscribe to connection changes from the Bluetooth service
    _bluetoothService.onDeviceConnected.listen((BluetoothDevice device) {
      // Update the UI when a device connects
      setState(() {
        _isBluetoothConnected = true;
        _connectedDevice = device;
        _bluetoothStatus =
            "Connected to ${device.platformName.isNotEmpty ? device.platformName : 'Unknown Device'}";
      });

      // Stop advertising when a device connects
      _bluetoothService.stopAdvertising();
      _advertisingTimer?.cancel();

      // Show a dialog to notify the user that a device has connected
      _showDeviceConnectedDialog(device);
    });
  }

  @override
  void dispose() {
    _bluetoothMoveSubscription?.cancel();
    _bluetoothService.disconnect();
    _bluetoothService.dispose();
    _advertisingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Bluetooth Room"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(_bluetoothStatus),
            if (_isBluetoothConnected && _connectedDevice != null)
              Text(
                "Connected to: ${_connectedDevice!.platformName.isNotEmpty ? _connectedDevice!.platformName : "Unknown"}",
                style: const TextStyle(color: Colors.green, fontSize: 16),
              ),
            if (!_isBluetoothConnected &&
                _bluetoothStatus.contains("Advertising"))
              Text(
                "Advertising... Remaining time: $_advertisingTimeout s",
                style: const TextStyle(color: Colors.blue, fontSize: 16),
              ),
            if (!_isBluetoothConnected && _selectedDevice != null)
              Text(
                "Selected Device: ${_selectedDevice!.device.platformName} (${_selectedDevice!.device.remoteId})",
                style: const TextStyle(color: Colors.blue, fontSize: 16),
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await _showRoomSelectionDialog();
              },
              child: const Text("Select Room Action"),
            ),
            if (_isBluetoothConnected)
              ElevatedButton(
                onPressed: _disconnect,
                child: const Text("Disconnect"),
              ),
          ],
        ),
      ),
    );
  }

  /// Disconnects from the current Bluetooth device
  Future<void> _disconnect() async {
    await _bluetoothService.disconnect();
    setState(() {
      _isBluetoothConnected = false;
      _bluetoothStatus = "Disconnected";
      _selectedDevice = null;
      _connectedDevice = null;
    });
  }

  Future<void> _showRoomSelectionDialog() async {
    final RoomAction? selectedAction = await showDialog<RoomAction>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Mill Game"),
          content: const Text(
              "Would you like to create a new room or join an existing one?"),
          actions: <Widget>[
            TextButton(
              child: const Text("Create Room"),
              onPressed: () => Navigator.of(context).pop(RoomAction.create),
            ),
            TextButton(
              child: const Text("Join Room"),
              onPressed: () => Navigator.of(context).pop(RoomAction.join),
            ),
          ],
        );
      },
    );

    if (selectedAction == RoomAction.create) {
      await _handleCreateRoom();
    } else if (selectedAction == RoomAction.join) {
      await _handleJoinRoom();
    } else {
      _showErrorDialog("No action selected. Please try again.");
    }
  }

  Future<void> _handleCreateRoom() async {
    try {
      _currentRoomId = DateTime.now().millisecondsSinceEpoch.toString();

      if (!mounted) {
        return;
      }

      // Display the room created dialog
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text("Create Room"),
            content: Text(
                "Your Room ID: $_currentRoomId\n\nCreating room and waiting for opponent to connect..."),
            actions: <Widget>[
              TextButton(
                child: const Text("Continue"),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );

      // Update the UI to show the new status before advertising
      setState(() {
        _bluetoothStatus = "Room created. Waiting for opponent to connect.";
      });

      // Start advertising to allow other devices to discover
      await _bluetoothService.startAdvertising();

      // Start the advertising timeout timer
      _startAdvertisingTimer();
    } catch (e) {
      logger.e("Error creating room: $e");
      _showErrorDialog("Failed to create room. Please try again.");
    }
  }

  void _startAdvertisingTimer() {
    _advertisingTimeout = 60; // Reset timeout
    _advertisingTimer?.cancel();
    _advertisingTimer =
        Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (_advertisingTimeout == 0) {
        timer.cancel();
        _bluetoothService.stopAdvertising();
        setState(() {
          _bluetoothStatus = "Advertising timed out. No opponent connected.";
        });
      } else {
        setState(() {
          _advertisingTimeout--;
        });
      }
    });
  }

  Future<void> _handleJoinRoom() async {
    try {
      await _bluetoothService.requestBluetoothPermissions();
      await _bluetoothService.enableBluetooth();

      await _startDeviceDiscovery();

      if (_availableDevices.isEmpty) {
        _showErrorDialog("No available rooms found.");
        return;
      }

      final ScanResult? selectedDevice =
          await _showDeviceSelectionDialog(_availableDevices);

      if (selectedDevice == null) {
        _showErrorDialog("No device selected.");
        return;
      }

      setState(() {
        _selectedDevice = selectedDevice; // Store the selected device
      });

      await _connectToDevice(selectedDevice.device);
    } catch (e) {
      logger.e("Error joining room: $e");
      _showErrorDialog("Failed to join room. Please try again.");
    }
  }

  Future<void> _startDeviceDiscovery() async {
    _showDiscoveringDialog();

    StreamSubscription<ScanResult>? discoveryStream;
    _availableDevices = <ScanResult>[];

    discoveryStream = _bluetoothService.startScan().listen((ScanResult result) {
      if (_availableDevices.every((ScanResult element) =>
          element.device.remoteId != result.device.remoteId)) {
        setState(() {
          _availableDevices.add(result);
        });
      }
    });

    await Future<void>.delayed(const Duration(seconds: 10));
    await discoveryStream.cancel();

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<ScanResult?> _showDeviceSelectionDialog(
      List<ScanResult> devices) async {
    return showDialog<ScanResult>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Select a Room"),
          content: SingleChildScrollView(
            child: Column(
              children: devices.map((ScanResult result) {
                final String deviceName = result.device.platformName.isNotEmpty
                    ? result.device.platformName
                    : 'Unknown device';
                return ListTile(
                  title: Text('$deviceName (${result.device.remoteId})'),
                  subtitle: Text('MAC: ${result.device.remoteId}'),
                  onTap: () {
                    Navigator.pop(context, result);
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      setState(() {
        _bluetoothStatus = "Connecting to ${device.platformName}...";
      });

      await _bluetoothService.connect(device);

      if (!mounted) {
        return;
      }

      setState(() {
        _isBluetoothConnected = true;
        _bluetoothStatus = "Connected to ${device.platformName}";
        _connectedDevice = device;
      });

      // Show a dialog to notify the user that the connection is successful
      _showDeviceConnectedDialog(device);

      // Navigate to the game page or continue with the game logic here
    } catch (e) {
      logger.e("Failed to connect to device: $e");
      _showErrorDialog("Failed to connect to device: $e");
      setState(() {
        _bluetoothStatus = "Connection failed";
      });
    }
  }

  Future<void> _showDeviceConnectedDialog(BluetoothDevice device) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Device Connected"),
          content: Text(
              "Successfully connected to ${device.platformName.isNotEmpty ? device.platformName : 'Unknown Device'}."),
          actions: <Widget>[
            TextButton(
              child: const Text("OK"),
              onPressed: () {
                Navigator.of(context).pop();
                // Proceed to the game or next step
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showErrorDialog(String message) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Error"),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: const Text("OK"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showDiscoveringDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          title: Text("Discovering devices..."),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text("Searching for nearby Bluetooth devices..."),
            ],
          ),
        );
      },
    );
  }
}
