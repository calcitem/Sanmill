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
import 'package:flutter_nearby_connections/flutter_nearby_connections.dart';
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
// Import the updated BluetoothService
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

  // Subscription for NearbyService connection events
  StreamSubscription<List<Device>>? _nearbyStateSubscription;

  @override
  void initState() {
    super.initState();
    controller.gameInstance.gameMode = widget.gameMode;

    // If the game mode is Bluetooth, initialize Bluetooth-specific setup
    if (widget.gameMode == GameMode.humanVsHumanBluetooth) {
      _initializeBluetoothGame();
    }
  }

  /// Initializes Bluetooth-specific setup for the game
  Future<void> _initializeBluetoothGame() async {
    logger.i("Initializing Bluetooth game...");

    // Initialize NearbyService
    await _bluetoothService.initNearbyService();

    // Listen for connection state changes
    // Listen for connection state changes
    _nearbyStateSubscription =
        _bluetoothService.nearbyService.stateChangedSubscription(
      callback: (dynamic devices) async {
        // Cast the dynamic data to List<Device>
        final List<Device> deviceList = devices as List<Device>;
        for (final Device device in deviceList) {
          if (device.state == SessionState.connected) {
            if (!_isBluetoothConnected) {
              // New device connected
              setState(() {
                _isBluetoothConnected = true;
                _bluetoothStatus = "Connected to ${device.deviceName}";
              });

              // Show pairing confirmation dialog
              await _showPairingConfirmationDialog(device);

              // Listen for incoming moves
              _bluetoothMoveSubscription =
                  _bluetoothService.moveStream.listen((String moveStr) {
                // Handle received move
                if (moveStr.isNotEmpty) {
                  logger.i("Received move from opponent: $moveStr");
                  // Apply opponent's move
                  GameController().applyOpponentMove(moveStr);
                } else {
                  logger.w("Received invalid move data: $moveStr");
                }
              });
            }
          } else if (device.state == SessionState.notConnected) {
            // Device disconnected
            setState(() {
              _isBluetoothConnected = false;
              _bluetoothStatus = "Disconnected";
            });

            // Cancel move subscription
            await _bluetoothMoveSubscription?.cancel();
            _bluetoothMoveSubscription = null;
          }
        }
      },
    ) as StreamSubscription<List<Device>>?;

    // Optionally, you can automatically connect to the first available device
    // Or handle multiple connections if needed
  }

  /// Shows a pairing confirmation dialog when a device connects
  Future<void> _showPairingConfirmationDialog(Device device) async {
    if (!mounted) {
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Confirm Pairing"),
          content: Text("Pair with ${device.deviceName}?"),
          actions: <Widget>[
            TextButton(
              child: const Text("Cancel"),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              child: const Text("Confirm"),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );

    if (confirm != null && confirm == true) {
      logger.i("Pairing confirmed with ${device.deviceName}");
      // You can send a confirmation message or set up the game here if needed
      // For example, designate roles based on advertiser flag
      // Or send initial game state
    } else {
      logger.i("Pairing canceled with ${device.deviceName}");
      // Disconnect if user cancels pairing
      await _bluetoothService.disconnect();
      setState(() {
        _bluetoothStatus = "Pairing canceled";
      });
    }
  }

  @override
  void dispose() {
    // Dispose Bluetooth resources
    _bluetoothMoveSubscription?.cancel();
    _nearbyStateSubscription?.cancel();
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
