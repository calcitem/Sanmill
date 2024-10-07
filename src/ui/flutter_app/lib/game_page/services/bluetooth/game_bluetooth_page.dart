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
  bool _isBluetoothConnected = false; // Used to track connection status
  String _bluetoothStatus = "Disconnected";
  String? _currentRoomId;
  List<ScanResult> _availableDevices =
      <ScanResult>[]; // Update type to ScanResult
  late ScanResult? _selectedDevice; // Used to store selected device for pairing

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showRoomSelectionDialog();
    });
  }

  @override
  void dispose() {
    _bluetoothMoveSubscription?.cancel();
    _bluetoothService.disconnect();
    _bluetoothService.dispose();
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
            if (_isBluetoothConnected && _selectedDevice != null)
              Text(
                "Connected to: ${_selectedDevice!.device.platformName.isNotEmpty ? _selectedDevice!.device.platformName : "Unknown"}",
                style: const TextStyle(color: Colors.green, fontSize: 16),
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

      await showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text("Room Created"),
            content: Text(
                "Your Room ID: $_currentRoomId\n\nWaiting for opponent to connect..."),
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

      setState(() {
        _bluetoothStatus = "Room created. Waiting for opponent to connect.";
      });
    } catch (e) {
      logger.e("Error creating room: $e");
      _showErrorDialog("Failed to create room. Please try again.");
    }
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

      _selectedDevice = selectedDevice;
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
      });

      Navigator.of(context).pop(true);
    } catch (e) {
      logger.e("Failed to connect to device: $e");
      _showErrorDialog("Failed to connect to device: $e");
      setState(() {
        _bluetoothStatus = "Connection failed";
      });
    }
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
