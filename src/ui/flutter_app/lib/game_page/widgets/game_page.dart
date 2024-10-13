import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../services/lan/game_lan_page.dart';
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

class GamePage extends StatefulWidget {
  const GamePage(this.gameMode, {super.key});

  final GameMode gameMode;

  @override
  GamePageState createState() => GamePageState();
}

class GamePageState extends State<GamePage> {
  final GameController controller = GameController();
  bool _isBluetoothConnected = false;

  @override
  void initState() {
    super.initState();
    controller.gameInstance.gameMode = widget.gameMode;

    // Navigate to BluetoothPage if the game mode is Bluetooth and not yet connected
    if (widget.gameMode == GameMode.humanVsHumanBluetooth) {
      _navigateToBluetoothPage();
    }
  }

  /// Navigates to BluetoothPage for device pairing
  Future<void> _navigateToBluetoothPage() async {
    // Wait for the result from BluetoothPage, indicating if pairing was successful
    final bool? bluetoothResult = await Navigator.push<bool?>(
      context,
      MaterialPageRoute<bool?>(
        builder: (BuildContext context) => const GameLANPage(),
      ),
    );

    // Update the Bluetooth connection status
    if (bluetoothResult != null && bluetoothResult == true) {
      setState(() {
        _isBluetoothConnected = true;
        logger.i("Bluetooth pairing successful. Game can start.");
      });
    } else {
      logger.w("Bluetooth pairing failed or was canceled.");
      // Optionally, handle pairing failure or cancellation if needed
    }
  }

  @override
  void dispose() {
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
          if (_isBluetoothConnected)
            _buildGameBoard(context, controller)
          else
            Center(
              child: ElevatedButton(
                onPressed: _navigateToBluetoothPage,
                child: const Text(
                  "Connect to Bluetooth",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

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
