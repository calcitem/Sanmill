// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../../generated/intl/l10n.dart';
import '../../../shared/database/database.dart';
import '../../services/mill.dart';

class LanConfigDialog extends StatefulWidget {
  const LanConfigDialog({super.key});

  @override
  LanConfigDialogState createState() => LanConfigDialogState();
}

class LanConfigDialogState extends State<LanConfigDialog>
    with SingleTickerProviderStateMixin {
  /// Whether acting as host or joining a host.
  bool isHost = true;

  /// Tracks if the server is running (Host mode).
  bool _serverRunning = false;

  /// Tracks if discovery is in progress (Join mode).
  bool _isDiscovering = false;

  /// Tracks if a connection attempt is in progress (Join mode).
  bool _isConnecting = false;

  /// Whether a host was discovered successfully (Join mode).
  bool _discoverySuccess = false;

  /// Current connection attempt count (Join mode).
  int _currentAttempt = 0;

  /// Maximum connection attempts allowed (Join mode).
  final int _maxAttempt = 3;

  /// Message to display when a protocol mismatch occurs.
  String? _protocolMismatchMessage;

  /// Controls the rotating icon in Host mode.
  late AnimationController _iconController;

  /// Controller for server IP input (Join mode).
  late TextEditingController _ipController;

  /// Controller for server port input (Join mode).
  late TextEditingController _portController;

  /// Error message for invalid IP input.
  String? _ipError;

  /// Error message for invalid port input.
  String? _portError;

  /// Timer used for discovery countdown (Join mode).
  Timer? _discoveryTimer;

  /// Elapsed seconds during discovery (Join mode).
  int _discoverySeconds = 0;

  /// Local instance of the network service.
  late NetworkService _networkService;

  /// String to hold the host IP and port info for display.
  String _hostInfo = "";

  /// Whether the Host wants to play White or Black.
  ///
  /// * `true` means the Host will be White (moving first).
  /// * `false` means the Host will be Black (moving second).
  ///
  /// We store it locally here, and also write it to `GameController().lanHostPlaysWhite`.
  bool _hostPlaysWhite = true;

  @override
  void initState() {
    super.initState();

    // Reuse global network service if already hosting.
    if (GameController().networkService != null &&
        GameController().networkService!.isHost) {
      _networkService = GameController().networkService!;
      _serverRunning = true;
    } else {
      _networkService = NetworkService();
    }

    // If the GameController already has a chosen color for the host, reuse it.
    // Otherwise default to true (white).
    _hostPlaysWhite = GameController().lanHostPlaysWhite ?? true;

    // Initialize animation and text controllers.
    _iconController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..stop();

    _ipController = TextEditingController(text: "192.168.1.100");
    _portController = TextEditingController(text: "33333");

    // Setup network service callbacks.
    _networkService.onDisconnected = () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              S.of(context).connectionLostDueToHeartbeatTimeoutPleaseReconnect,
              softWrap: true, // Allow multiline wrapping in Snackbar
            ),
          ),
        );
      }
    };

    _networkService.onProtocolMismatch = (String message) {
      if (mounted) {
        setState(() {
          _protocolMismatchMessage = message;
          _isConnecting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              message,
              softWrap: true, // Allow multiline wrapping in Snackbar
            ),
          ),
        );
      }
    };
  }

  @override
  void dispose() {
    _iconController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _discoveryTimer?.cancel();

    // Clear host info when disposing.
    _hostInfo = "";

    // Dispose network service if not assigned globally.
    if (GameController().networkService == null) {
      _networkService.dispose();
    }
    super.dispose();
  }

  /// Starts hosting the LAN game as a server.
  Future<void> _startHosting() async {
    if (!mounted) {
      return;
    }

    // Check if a global network service is already hosting.
    final NetworkService? existingService = GameController().networkService;
    if (existingService != null &&
        existingService.isHost &&
        existingService.serverSocket != null) {
      // Already hosting; update UI.
      setState(() {
        _serverRunning = true;
      });
      return;
    }

    // Assign current instance to the global network service.
    GameController().networkService = _networkService;

    // Save the user's color choice to GameController.
    GameController().lanHostPlaysWhite = _hostPlaysWhite;

    // Update state to indicate that hosting is starting.
    setState(() {
      _serverRunning = true;
    });
    _iconController.repeat(); // Start rotation animation.

    final int port = int.tryParse(_portController.text) ?? 33333;
    try {
      // Start hosting and assign the network service when a client connects.
      await _networkService.startHost(
        port,
        onClientConnected: (String clientIp, int clientPort) {
          GameController().networkService = _networkService;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  S
                      .of(context)
                      .clientConnected(clientIp, clientPort.toString()),
                  softWrap: true, // Allow multiline wrapping in Snackbar
                ),
              ),
            );
            Navigator.pop(context, true);
          }
        },
      );

      // Retrieve local IP addresses for display.
      final List<String> localIps = await NetworkService.getLocalIpAddresses();
      if (mounted) {
        setState(() {
          _hostInfo = localIps.isNotEmpty
              ? localIps.map((String ip) => "$ip:$port").join("\n")
              : "Unknown:$port";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _serverRunning = false;
        });
        _iconController.stop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              S.of(context).failedToStartHosting(e.toString()),
              softWrap: true,
            ),
          ),
        );
      }
    }
  }

  /// Stops hosting and cleans up resources.
  Future<void> _stopHosting() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _serverRunning = false;
      _hostInfo = ""; // Clear host info.
    });
    _iconController.stop();
    _networkService.dispose();
    GameController().networkService = null;

    // Directly update the UI to show that the server has stopped.
    GameController().headerTipNotifier.showTip(S.of(context).serverIsStopped);
    GameController().headerIconsNotifier.showIcons();

    // Create a new NetworkService instance to restart the service when needed.
    _networkService = NetworkService();
  }

  /// Starts the discovery process to find a host on the LAN.
  Future<void> _startDiscovery() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _isDiscovering = true;
      _discoverySeconds = 0;
      _discoverySuccess = false;
    });
    _discoveryTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (mounted) {
        setState(() {
          _discoverySeconds++;
        });
      }
    });

    // Broadcast a discovery message and wait for a host to reply.
    final String? discovered = await NetworkService.discoverHost();
    _cancelDiscovery(); // Stop the discovery timer.

    if (mounted) {
      if (discovered != null) {
        // Update IP and Port fields with discovered host data.
        final List<String> parts = discovered.split(':');
        if (parts.length == 2) {
          setState(() {
            _ipController.text = parts[0];
            _portController.text = parts[1];
            _discoverySuccess = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                S.of(context).hostDiscovered(parts[0], parts[1]),
                softWrap: true,
              ),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              S.of(context).noHostDiscovered,
              softWrap: true,
            ),
          ),
        );
      }
    }
  }

  /// Cancels the discovery process.
  void _cancelDiscovery() {
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
    if (mounted) {
      setState(() {
        _isDiscovering = false;
      });
    }
  }

  /// Attempts to connect to the host with retry logic.
  Future<void> _onConnect() async {
    if (!mounted) {
      return;
    }
    // Regex for validating IPv4 addresses.
    final RegExp ipRegex = RegExp(
        r'^((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$');
    final bool ipValid = ipRegex.hasMatch(_ipController.text);
    final int? port = int.tryParse(_portController.text);
    final bool portValid = port != null && port > 0 && port <= 65535;

    setState(() {
      _ipError = ipValid ? null : S.of(context).invalidIpAddress;
      _portError = portValid ? null : S.of(context).invalidPort;
    });

    if (!ipValid || !portValid) {
      return;
    }

    setState(() {
      _isConnecting = true;
      _currentAttempt = 0;
      _discoverySuccess = false;
    });

    bool connected = false;
    while (_currentAttempt < _maxAttempt && !connected && mounted) {
      setState(() {
        _currentAttempt++;
      });

      await Future<void>.delayed(const Duration(milliseconds: 100));

      try {
        // Attempt to connect to the host.
        await _networkService.connectToHost(_ipController.text, port);
        connected = true;
        GameController().networkService = _networkService;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                S.of(context).connectedToHostSuccessfully,
                softWrap: true,
              ),
            ),
          );
          Navigator.pop(context, true);
        }
        return;
      } catch (e) {
        if (_currentAttempt >= _maxAttempt && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                S.of(context).failedToConnect(e.toString()),
                softWrap: true,
              ),
            ),
          );
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    if (mounted) {
      setState(() {
        _isConnecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color baseColor = Theme.of(context).dialogBackgroundColor;
    final Size screenSize = MediaQuery.of(context).size;

    return AlertDialog(
      backgroundColor: baseColor,
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      // Fixed width and height for the dialog.
      content: SizedBox(
        width: screenSize.width * 0.8,
        height: screenSize.height * 0.4,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Top and center sections scroll if content is too tall.
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // -- Top section: title, role selection, status messages --
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          S.of(context).localNetworkSettings,
                          style: Theme.of(context).textTheme.titleLarge,
                          softWrap:
                              true, // Allows multiline in case of long text
                          overflow: TextOverflow
                              .visible, // Ensure text is not cut off
                        ),
                        const SizedBox(height: 4),

                        // Role selection (Host or Join)
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: RadioListTile<bool>(
                                contentPadding: EdgeInsets.zero,
                                value: true,
                                groupValue: isHost,
                                onChanged: (bool? val) {
                                  setState(() {
                                    isHost = true;
                                    _isDiscovering = false;
                                    _isConnecting = false;
                                    _discoverySuccess = false;
                                    _protocolMismatchMessage = null;
                                  });
                                },
                                title: Wrap(
                                  // Use Wrap instead of Row for flexibility
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 4,
                                  children: <Widget>[
                                    const Icon(FluentIcons.desktop_24_regular,
                                        size: 20),
                                    Text(S.of(context).host),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              child: RadioListTile<bool>(
                                contentPadding: EdgeInsets.zero,
                                value: false,
                                groupValue: isHost,
                                onChanged: (bool? val) {
                                  setState(() {
                                    isHost = false;
                                    _serverRunning = false;
                                    _iconController.stop();
                                    _protocolMismatchMessage = null;
                                  });
                                },
                                title: Wrap(
                                  // Use Wrap instead of Row for flexibility
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 4,
                                  children: <Widget>[
                                    const Icon(
                                        FluentIcons.plug_connected_24_regular,
                                        size: 20),
                                    Text(S.of(context).join),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // Display network status based on mode.
                        if (isHost)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Wrap(
                                // Use Wrap instead of Row
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 4,
                                children: <Widget>[
                                  if (_serverRunning)
                                    RotationTransition(
                                      turns: _iconController,
                                      child: Icon(
                                        FluentIcons.arrow_clockwise_24_regular,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .secondary,
                                        size: 20,
                                      ),
                                    )
                                  else
                                    const Icon(
                                      FluentIcons.arrow_clockwise_24_regular,
                                      color: Colors.grey,
                                      size: 20,
                                    ),
                                  Text(
                                    _serverRunning
                                        ? S.of(context).waitingAClientConnection
                                        : S.of(context).serverIsStopped,
                                    style: const TextStyle(fontSize: 14.0),
                                    softWrap: true, // Enable multiline wrapping
                                    overflow: TextOverflow
                                        .visible, // Ensure text is not cut off
                                  ),
                                ],
                              ),
                              if (_serverRunning)
                                const SizedBox(height: 20)
                              else
                                const SizedBox(height: 4),
                            ],
                          )
                        else
                          Wrap(
                            // Use Wrap instead of Row
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 4,
                            children: <Widget>[
                              if (_isDiscovering || _isConnecting)
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color:
                                        Theme.of(context).colorScheme.secondary,
                                  ),
                                )
                              else
                                const Icon(
                                  FluentIcons.warning_24_regular,
                                  size: 20,
                                  color: Colors.red,
                                ),
                              Text(
                                _isDiscovering
                                    ? S
                                        .of(context)
                                        .discoveringSeconds(_discoverySeconds)
                                    : _isConnecting
                                        ? S.of(context).connectingAttempt(
                                            _currentAttempt, _maxAttempt)
                                        : _discoverySuccess
                                            ? S
                                                .of(context)
                                                .discoverySuccessfulAwaitingConnection
                                            : S
                                                .of(context)
                                                .networkStatusDisconnected,
                                style: const TextStyle(fontSize: 14.0),
                                softWrap: true,
                                overflow: TextOverflow
                                    .visible, // Ensure text is not cut off
                              ),
                            ],
                          ),

                        // Display protocol mismatch message if exists.
                        if (_protocolMismatchMessage != null) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            _protocolMismatchMessage!,
                            style: const TextStyle(
                              fontSize: 14.0,
                              color: Colors.red,
                            ),
                            softWrap: true, // Allow multiline wrapping
                            overflow: TextOverflow
                                .visible, // Ensure text is not cut off
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),

                    // -- Middle section: Show host info if hosting --
                    if (isHost && _serverRunning && _hostInfo.isNotEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            _hostInfo,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                            softWrap: true, // Allow multiline wrapping
                            overflow: TextOverflow
                                .visible, // Ensure text is not cut off
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 0),
                  ],
                ),
              ),
            ),

            // -- Bottom section: Host or Join UI --
            if (isHost)
              Container(
                height: 160.0, // Increased height to fit the new radio row
                padding: const EdgeInsets.only(top: 4.0),
                child: _buildHostUI(),
              )
            else
              Container(
                padding: const EdgeInsets.only(top: 4.0),
                child: _buildJoinUI(),
              ),
          ],
        ),
      ),
    );
  }

  /// Builds the UI for Host mode.
  Widget _buildHostUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        // --- Host color selection (White or Black) ---
        // Disabled if the server is already running.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Radio<bool>(
              value: true,
              groupValue: _hostPlaysWhite,
              onChanged: _serverRunning
                  ? null // Disable changes once server is running
                  : (bool? val) {
                      setState(() {
                        _hostPlaysWhite = val ?? true;
                      });
                    },
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: DB().colorSettings.whitePieceColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey),
              ),
            ),
            const SizedBox(width: 40),
            Radio<bool>(
              value: false,
              groupValue: _hostPlaysWhite,
              onChanged: _serverRunning
                  ? null
                  : (bool? val) {
                      setState(() {
                        _hostPlaysWhite = val ?? false;
                      });
                    },
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: DB().colorSettings.blackPieceColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // --- Start/Stop hosting button ---
        Center(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Theme.of(context).colorScheme.secondary,
            ),
            icon: Icon(
              _serverRunning
                  ? FluentIcons.stop_24_regular
                  : FluentIcons.play_24_filled,
              size: 20,
            ),
            label: Text(
              _serverRunning
                  ? S.of(context).stopHosting
                  : S.of(context).startHosting,
              softWrap: true,
              overflow: TextOverflow.visible,
            ),
            onPressed: () async {
              if (_serverRunning) {
                await _stopHosting();
              } else {
                await _startHosting();
              }
            },
          ),
        ),
      ],
    );
  }

  /// Builds the UI for Join mode with vertically centered content.
  Widget _buildJoinUI() {
    return Column(
      // Center the entire content vertically within the available space
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        // Server IP and Port input fields
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _ipController,
                decoration: InputDecoration(
                  labelText: S.of(context).serverIp,
                  errorText: _ipError,
                  // Allow error text to wrap
                  errorMaxLines: 3,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _portController,
                decoration: InputDecoration(
                  labelText: S.of(context).port,
                  errorText: _portError,
                  // Allow error text to wrap
                  errorMaxLines: 3,
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Buttons for discovery and connecting
        Row(
          mainAxisAlignment:
              MainAxisAlignment.spaceBetween, // Ensure proper spacing
          children: <Widget>[
            // Use ConstrainedBox instead of Flexible for buttons
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 100),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                ),
                onPressed: () async {
                  if (_isDiscovering) {
                    _cancelDiscovery();
                  } else {
                    await _startDiscovery();
                  }
                },
                child: Text(
                  _isDiscovering ? S.of(context).stop : S.of(context).discover,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                ),
              ),
            ),
            const SizedBox(width: 8), // Fixed space between buttons
            // Use ConstrainedBox instead of Flexible for buttons
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 100),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                ),
                onPressed: _onConnect,
                child: Text(
                  S.of(context).connect,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
