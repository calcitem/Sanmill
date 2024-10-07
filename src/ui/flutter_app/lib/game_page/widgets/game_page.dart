// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:hive/hive.dart';

import '../../appearance_settings/models/display_settings.dart';
import '../../custom_drawer/custom_drawer.dart';
import '../../game_page/services/mill.dart';
import '../../general_settings/models/general_settings.dart';
import '../../generated/intl/l10n.dart';
import '../../main.dart';
import '../../rule_settings/widgets/rule_settings_page.dart';
import '../../shared/config/constants.dart';
import '../../shared/database/database.dart';
import '../../shared/services/environment_config.dart';
import '../../shared/services/logger.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/themes/ui_colors.dart';
import '../../shared/utils/helpers/string_helpers/string_buffer_helper.dart';
import '../../shared/widgets/custom_spacer.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../services/animation/animation_manager.dart';
import '../services/bluetooth/bluetooth_service.dart';
import '../services/painters/painters.dart';
import 'play_area.dart';
import 'toolbars/game_toolbar.dart';
import 'vignette_overlay.dart';

part 'board_semantics.dart';
part 'dialogs/game_result_alert_dialog.dart';
part 'dialogs/info_dialog.dart';
part 'dialogs/move_list_dialog.dart';
part 'game_board.dart';
part 'game_header.dart';
part 'game_page_action_sheet.dart';
part 'modals/move_options_modal.dart';

// Enum to represent room actions
enum RoomAction { create, join }

// Modify GamePage to be a StatefulWidget to manage Bluetooth state
class GamePage extends StatefulWidget {
  const GamePage(this.gameMode, {super.key});

  final GameMode gameMode;

  @override
  GamePageState createState() => GamePageState();
}

class GamePageState extends State<GamePage> {
  final GameController controller = GameController();
  final BluetoothService _bluetoothService = BluetoothService.instance;
  StreamSubscription<String>? _bluetoothMoveSubscription;
  bool _isBluetoothConnected = false;
  String _bluetoothStatus = "Disconnected";

  // Variables for Room management
  String? _currentRoomId;
  List<BluetoothDiscoveryResult> _availableDevices =
      <BluetoothDiscoveryResult>[];

  @override
  void initState() {
    super.initState();
    controller.gameInstance.gameMode = widget.gameMode;

    // If the game mode is Bluetooth, initialize Bluetooth-specific setup
    if (widget.gameMode == GameMode.humanVsHumanBluetooth) {
      // Show the Room selection dialog after the first frame is rendered
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showRoomSelectionDialog();
      });
    }
  }

  /// Displays a dialog allowing the user to create or join a room
  Future<void> _showRoomSelectionDialog() async {
    // Show a dialog with options to Create or Join a Room
    final RoomAction? selectedAction = await showDialog<RoomAction>(
      context: context,
      barrierDismissible:
          false, // Prevent dismissing the dialog by tapping outside
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Mill Game"),
          content: const Text(
              "Would you like to create a new room or join an existing one?"),
          actions: <Widget>[
            TextButton(
              child: const Text("Create Room"),
              onPressed: () {
                Navigator.of(context).pop(RoomAction.create);
              },
            ),
            TextButton(
              child: const Text("Join Room"),
              onPressed: () {
                Navigator.of(context).pop(RoomAction.join);
              },
            ),
          ],
        );
      },
    );

    // Handle the user's selection
    if (selectedAction == RoomAction.create) {
      await _handleCreateRoom();
    } else if (selectedAction == RoomAction.join) {
      await _handleJoinRoom();
    } else {
      // If no action was selected, show an error dialog
      _showErrorDialog("No action selected. Please try again.");
    }
  }

  /// Handles the creation of a new room
  Future<void> _handleCreateRoom() async {
    try {
      // Generate a unique Room ID (you might want to use a more robust method)
      _currentRoomId = DateTime.now().millisecondsSinceEpoch.toString();

      // Display the Room ID to the user so they can share it with others
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text("Room Created"),
            content: Text(
                "Your Room ID is:\n$_currentRoomId\n\nShare this ID with your opponent to join."),
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

      // Since `flutter_bluetooth_serial` doesn't support server sockets directly,
      // you can prompt the user to wait for the opponent to connect manually.
      // Alternatively, implement a custom pairing mechanism based on Room ID.

      // Update Bluetooth status
      setState(() {
        _bluetoothStatus = "Room created. Waiting for opponent to connect.";
      });

      // Optionally, implement a mechanism to wait for an incoming connection.
      // This might involve manual pairing using the Room ID as a reference.

      // Note: Due to limitations in the `flutter_bluetooth_serial` package,
      // implementing server-side listening for connections isn't straightforward.
      // Consider using platform-specific code or alternative packages if necessary.
    } catch (e) {
      logger.e("Error creating room: $e");
      _showErrorDialog("Failed to create room. Please try again.");
    }
  }

  /// Handles joining an existing room
  Future<void> _handleJoinRoom() async {
    try {
      // Request necessary Bluetooth permissions
      await _bluetoothService.requestBluetoothPermissions();

      // Enable Bluetooth if not already enabled
      await _bluetoothService.enableBluetooth();

      // Start device discovery
      await _startDeviceDiscovery();

      if (_availableDevices.isEmpty) {
        _showErrorDialog("No available rooms found.");
        return;
      }

      // Show device selection dialog
      final BluetoothDiscoveryResult? selectedDevice =
          await _showDeviceSelectionDialog(_availableDevices);

      if (selectedDevice == null) {
        _showErrorDialog("No device selected.");
        return;
      }

      // Proceed with connecting to the selected device
      await _connectToDevice(selectedDevice.device);
    } catch (e) {
      logger.e("Error joining room: $e");
      _showErrorDialog("Failed to join room. Please try again.");
    }
  }

  /// Starts Bluetooth device discovery
  Future<void> _startDeviceDiscovery() async {
    // Show discovery in progress dialog
    _showDiscoveringDialog();

    // Start discovery
    StreamSubscription<BluetoothDiscoveryResult>? discoveryStream;
    _availableDevices = <BluetoothDiscoveryResult>[];

    discoveryStream = FlutterBluetoothSerial.instance
        .startDiscovery()
        .listen((BluetoothDiscoveryResult result) {
      // Avoid duplicates and exclude self
      if (_availableDevices.every((BluetoothDiscoveryResult element) =>
              element.device.address != result.device.address) &&
          result.device.address != _bluetoothService.getLocalAddress()) {
        setState(() {
          _availableDevices.add(result);
        });
      }
    });

    // Wait for discovery to complete (e.g., 10 seconds)
    await Future.delayed(const Duration(seconds: 10));

    // Cancel discovery
    await discoveryStream.cancel();

    // Dismiss the discovering dialog
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  /// Shows a dialog for selecting a discovered device.
  Future<BluetoothDiscoveryResult?> _showDeviceSelectionDialog(
      List<BluetoothDiscoveryResult> devices) async {
    return showDialog<BluetoothDiscoveryResult>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Select a Room"),
          content: SingleChildScrollView(
            child: Column(
              children: devices.map((BluetoothDiscoveryResult result) {
                final String deviceName =
                    result.device.name ?? 'Unknown device';
                return ListTile(
                  title: Text('$deviceName (${result.device.address})'),
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

  /// Connects to the selected Bluetooth device
  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      setState(() {
        _bluetoothStatus = "Connecting to ${device.name}...";
      });

      await _bluetoothService.connect(device);

      setState(() {
        _isBluetoothConnected = true;
        _bluetoothStatus = "Connected to ${device.name}";
      });

      // Listen for incoming moves
      _bluetoothMoveSubscription =
          _bluetoothService.moveStream.listen((String moveStr) {
        if (moveStr.isNotEmpty) {
          logger.i("Received move from opponent: $moveStr");
          // Apply opponent's move
          controller.applyOpponentMove(moveStr);
        } else {
          logger.w("Received invalid move data: $moveStr");
        }
      });
    } catch (e) {
      logger.e("Failed to connect to device: $e");
      _showErrorDialog("Failed to connect to device: $e");
      setState(() {
        _bluetoothStatus = "Connection failed";
      });
    }
  }

  /// Displays an error dialog with the provided message
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

  /// Shows the "Discovering devices..." dialog without awaiting
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

  /// Sends a move to the opponent via Bluetooth
  void _sendMove(String move) {
    if (_isBluetoothConnected) {
      _bluetoothService.sendMove(move);
    } else {
      _showErrorDialog("Not connected to any opponent.");
    }
  }

  @override
  void dispose() {
    // Dispose Bluetooth resources
    _bluetoothMoveSubscription?.cancel();
    _bluetoothService.disconnect();
    _bluetoothService.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Build the game UI as usual
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: <Widget>[
          // Background image or color
          _buildBackground(),

          // Game board
          _buildGameBoard(context, controller),

          // Drawer icon
          Align(
            alignment: AlignmentDirectional.topStart,
            child: SafeArea(
              child: CustomDrawerIcon.of(context)!.drawerIcon,
            ),
          ),

          // Vignette overlay
          if (DB().displaySettings.vignetteEffectEnabled)
            const VignetteOverlay(gameBoardRect: Rect.zero), // Adjust as needed

          // Bluetooth status widget
          Positioned(
            top: 50,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                _isBluetoothConnected ? "Connected" : _bluetoothStatus,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the background for the game page
  Widget _buildBackground() {
    if (DB().displaySettings.backgroundImagePath.isEmpty) {
      return Container(
        color: DB().colorSettings.darkBackgroundColor,
      );
    } else {
      return Image.asset(
        DB().displaySettings.backgroundImagePath,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder:
            (BuildContext context, Object error, StackTrace? stackTrace) {
          return Container(
            color: DB().colorSettings.darkBackgroundColor,
          );
        },
      );
    }
  }

  /// Builds the game board widget
  Widget _buildGameBoard(BuildContext context, GameController controller) {
    return OrientationBuilder(
      builder: (BuildContext context, Orientation orientation) {
        final bool isLandscape = orientation == Orientation.landscape;

        return Align(
          alignment: isLandscape ? Alignment.center : Alignment.topCenter,
          child: FutureBuilder<void>(
            future: controller.startController(),
            builder: (BuildContext context, AsyncSnapshot<Object?> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center();
              }

              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.boardMargin),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double toolbarHeight =
                        _calculateToolbarHeight(context);

                    // Constraints of the game board but applied to the entire child
                    final double maxWidth = constraints.maxWidth;
                    final double maxHeight =
                        constraints.maxHeight - toolbarHeight;
                    final BoxConstraints constraint = BoxConstraints(
                      maxWidth: (maxHeight > 0 && maxHeight < maxWidth)
                          ? maxHeight
                          : maxWidth,
                    );

                    return ConstrainedBox(
                      constraints: constraint,
                      // Use ValueListenableBuilder to listen to DisplaySettings changes
                      child: ValueListenableBuilder<Box<DisplaySettings>>(
                        valueListenable: DB().listenDisplaySettings,
                        builder: (BuildContext context,
                            Box<DisplaySettings> box, Widget? child) {
                          final DisplaySettings displaySettings = box.get(
                            DB.displaySettingsKey,
                            defaultValue: const DisplaySettings(),
                          )!;

                          // Retrieve the selected board image path
                          final String boardImagePath =
                              displaySettings.boardImagePath;

                          return PlayArea(
                            // Pass the board image path to PlayArea
                            boardImagePath: boardImagePath,
                            //onMoveMade: _sendMove, // TODO(BT): Callback to send move
                          );
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// Calculates the height of the toolbar based on settings
  double _calculateToolbarHeight(BuildContext context) {
    double toolbarHeight =
        GamePageToolbar.height + ButtonTheme.of(context).height;
    if (DB().displaySettings.isHistoryNavigationToolbarShown) {
      toolbarHeight *= 2;
    } else if (DB().displaySettings.isAnalysisToolbarShown) {
      toolbarHeight *= 3;
    }
    return toolbarHeight;
  }
}
