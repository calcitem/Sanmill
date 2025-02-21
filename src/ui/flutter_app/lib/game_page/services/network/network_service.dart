// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// network_service.dart

part of '../mill.dart';

/// NetworkService handles LAN hosting, client connection, discovery, and heartbeat functionality.
class NetworkService {
  static const String _logTag = "[Network]";

  /// Current protocol version for client-server communication.
  static const String protocolVersion = "1.0";

  ServerSocket? serverSocket;
  Socket? clientSocket;
  bool isHost = false;
  String? opponentAddress;

  /// Callback for disconnection events.
  VoidCallback? onDisconnected;

  /// Callback for when a client connects, providing client IP and port.
  void Function(String clientIp, int clientPort)? onClientConnected;

  /// Callback for protocol mismatch events.
  void Function(String message)? onProtocolMismatch;

  // Queue for processing incoming messages sequentially.
  final Queue<String> _messageQueue = Queue<String>();
  bool _isProcessing = false;

  // UDP socket for discovery.
  RawDatagramSocket? discoverySocket;

  // Heartbeat timers and tracking variables.
  Timer? _heartbeatTimer;
  Timer? _heartbeatCheckTimer;
  DateTime _lastHeartbeatReceived = DateTime.now();

  /// Completer to synchronize protocol handshake
  Completer<bool>? _protocolHandshakeCompleter;

  /// Retrieves all local non-loopback IPv4 addresses.
  static Future<List<String>> getLocalIpAddresses() async {
    final List<String> ips = <String>[];
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final NetworkInfo info = NetworkInfo();
        final String? wifiIP = await info.getWifiIP();
        if (wifiIP != null && wifiIP.isNotEmpty) {
          ips.add(wifiIP);
        } else {
          logger.w("$_logTag No Wi‑Fi IP found on mobile platform");
        }
      } else {
        final List<NetworkInterface> interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        );
        for (final NetworkInterface interface in interfaces) {
          for (final InternetAddress addr in interface.addresses) {
            if (!addr.isLoopback) {
              ips.add(addr.address);
            }
          }
        }
        if (ips.isEmpty) {
          logger.w("$_logTag No non-loopback IPv4 addresses found");
        }
      }
    } catch (e) {
      logger.e("$_logTag Failed to get local IP addresses: $e");
    }
    return ips;
  }

  /// Starts hosting (server mode) on the specified TCP port.
  Future<void> startHost(int port,
      {void Function(String, int)? onClientConnected}) async {
    this.onClientConnected = onClientConnected;
    try {
      serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      isHost = true;
      logger.i("$_logTag Hosting LAN game on port $port");

      // Accept incoming client connections.
      serverSocket!.listen(
        (Socket socket) {
          clientSocket = socket;
          opponentAddress = socket.remoteAddress.address;
          logger.i(
              "$_logTag Accepted new client at $opponentAddress:${socket.remotePort}");

          // Notify any UI or callback.
          onClientConnected?.call(opponentAddress!, socket.remotePort);

          // Start listening for data on this socket.
          _listenToSocket(socket);

          // IMPORTANT:
          // Only the host actively starts sending heartbeats;
          // the client will simply respond when it receives one.
          _startHeartbeat();
        },
        onError: (Object error, [StackTrace? stackTrace]) {
          logger.e("$_logTag Server socket error: $error");
          _handleDisconnection();
        },
      );

      // Start UDP listener for discovery requests.
      await _startDiscoveryListener(port);
    } catch (e) {
      logger.e("$_logTag Failed to start host: $e");
      throw Exception("Failed to start host: $e");
    }
  }

  /// Sets up a UDP listener on port 33334 to reply to discovery messages.
  Future<void> _startDiscoveryListener(int serverPort) async {
    discoverySocket =
        await RawDatagramSocket.bind(InternetAddress.anyIPv4, 33334);
    logger.i("$_logTag Discovery socket bound to port 33334");

    discoverySocket!.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final Datagram? datagram = discoverySocket!.receive();
        if (datagram != null) {
          final String message = utf8.decode(datagram.data).trim();
          if (message == 'Discovery?') {
            // Retrieve the local IP address and reply with server info.
            getLocalIpAddress().then((String? localIp) {
              if (localIp != null) {
                final String reply = 'Sanmill:$localIp:$serverPort';
                final Uint8List replyData = utf8.encode(reply);
                discoverySocket!
                    .send(replyData, datagram.address, datagram.port);
                logger.i(
                    "$_logTag Replied to discovery request from ${datagram.address.address}:${datagram.port} with $reply");
              }
            });
          }
        }
      }
    });
  }

  /// Connects to a host (client mode) with a retry mechanism and protocol check
  Future<void> connectToHost(String host, int port,
      {int retryCount = 3}) async {
    for (int i = 0; i < retryCount; i++) {
      try {
        clientSocket = await Socket.connect(host, port);
        opponentAddress = host;
        isHost = false; // This side is client
        logger.i("$_logTag Connected to host at $host:$port");

        // Set up socket listener
        _listenToSocket(clientSocket!);

        // Initialize protocol handshake
        _protocolHandshakeCompleter = Completer<bool>();
        sendMove("protocol:$protocolVersion");

        // Wait for protocol handshake to complete (timeout after 5 seconds)
        final bool protocolSuccess =
            await _protocolHandshakeCompleter!.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            logger.e("$_logTag Protocol handshake timed out");
            return false;
          },
        );

        if (!protocolSuccess) {
          throw Exception("Protocol handshake failed or mismatched");
        }

        // Only proceed if protocol matches
        logger.i(
            "$_logTag Protocol handshake successful, requesting aiMovesFirst");
        sendMove("request:aiMovesFirst");
        return;
      } catch (e) {
        logger.e("$_logTag Attempt ${i + 1} failed: $e");
        _handleDisconnection(); // Clean up on failure
        if (i == retryCount - 1) {
          throw Exception("Failed to connect after $retryCount attempts: $e");
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  /// Retrieves the first available local non-loopback IPv4 address.
  static Future<String?> getLocalIpAddress() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final NetworkInfo info = NetworkInfo();
        final String? wifiIP = await info.getWifiIP();
        if (wifiIP != null && wifiIP.isNotEmpty) {
          return wifiIP;
        } else {
          logger.w("$_logTag No Wi‑Fi IP found on mobile platform");
          return null;
        }
      } else {
        final List<NetworkInterface> interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        );
        for (final NetworkInterface interface in interfaces) {
          for (final InternetAddress addr in interface.addresses) {
            if (!addr.isLoopback) {
              return addr.address;
            }
          }
        }
        logger.w("$_logTag No non-loopback IPv4 address found");
        return null;
      }
    } catch (e) {
      logger.e("$_logTag Failed to get local IP: $e");
      return null;
    }
  }

  /// Discovers a host by broadcasting a UDP message and waiting for a response.
  static Future<String?> discoverHost(
      {Duration timeout = const Duration(seconds: 10)}) async {
    final Completer<String?> completer = Completer<String?>();
    final Uint8List discoveryMsg = utf8.encode('Discovery?');
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;

    try {
      // Bind to 0.0.0.0 to use all available interfaces.
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      // Listen for responses.
      subscription = socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final Datagram? datagram = socket?.receive();
          if (datagram != null) {
            final String message = utf8.decode(datagram.data).trim();
            if (message.startsWith('Sanmill:')) {
              final List<String> parts = message.split(':');
              if (parts.length == 3) {
                // Complete with host IP and port.
                completer.complete('${parts[1]}:${parts[2]}');
                subscription
                    ?.cancel(); // Stop listening after first valid response.
              }
            }
          }
        }
      });

      // Send broadcast message.
      socket.send(discoveryMsg, InternetAddress("255.255.255.255"), 33334);

      // Wait for response or timeout.
      return await completer.future.timeout(timeout, onTimeout: () {
        subscription?.cancel(); // Cancel subscription on timeout.
        return null;
      });
    } catch (e) {
      logger.e("$_logTag Error during host discovery: $e");
      return null;
    } finally {
      subscription?.cancel(); // Ensure subscription is canceled.
      socket?.close(); // Ensure socket is closed.
    }
  }

  /// Listens for incoming messages on the provided socket.
  void _listenToSocket(Socket socket) {
    clientSocket = socket;
    opponentAddress = socket.remoteAddress.address;

    logger
        .i("$_logTag Client connected: $opponentAddress:${socket.remotePort}");

    /*
     * Explanation for the heartbeat logic:
     * - The HOST will periodically send "heartbeat" messages (see _startHeartbeat).
     * - The CLIENT, upon receiving "heartbeat", will update the timestamp and reply with "heartbeatAck".
     * - The HOST receives "heartbeatAck" and updates its own timestamp.
     * - This avoids infinite loops of echoing the same string.
     *
     * Alternatively, you could do a fully symmetric approach (both sides ping),
     * but you must ensure you differentiate ping vs. pong messages to avoid echo loops.
     */

    socket.listen(
      (List<int> data) async {
        if (socket.isClosed) {
          logger.w("$_logTag Socket closed before processing data");
          return;
        }
        final int remotePort = socket.remotePort;
        final String message = utf8.decode(data).trim();

        logger
            .t("$_logTag Received from $opponentAddress:$remotePort: $message");

        // 1) Protocol handshake checks
        if (message.startsWith("protocol:")) {
          final String receivedProtocol = message.split(":")[1];
          if (isHost) {
            // Server side: reply with protocol version.
            sendMove("protocol:$protocolVersion");
            if (receivedProtocol != protocolVersion) {
              logger.w(
                  "$_logTag Protocol mismatch: client $receivedProtocol, server $protocolVersion");
              onProtocolMismatch?.call(
                  "Protocol mismatch detected: Server=$protocolVersion, Client=$receivedProtocol. Please upgrade the client.");
            }
          } else {
            // Client side: compare the protocol version.
            if (receivedProtocol != protocolVersion) {
              logger.w(
                  "$_logTag Protocol mismatch: client $protocolVersion, server $receivedProtocol");
              onProtocolMismatch?.call(
                  "Protocol mismatch detected: Client=$protocolVersion, Server=$receivedProtocol. Please upgrade your software.");
              _handleDisconnection();
              _protocolHandshakeCompleter?.complete(false);
            } else {
              logger.i("$_logTag Protocol version matches: $protocolVersion");
              _protocolHandshakeCompleter?.complete(true);
            }
          }
          return;
        }

        // 2) Host->Client "heartbeat", Client->Host "heartbeatAck"
        if (message == "heartbeat") {
          /*
           * This means the client side just received a heartbeat from the host.
           * The client should mark lastReceived time and respond with "heartbeatAck".
           */
          if (!isHost) {
            _lastHeartbeatReceived = DateTime.now();
            logger.t(
                "$_logTag [Client] Received heartbeat, replying with 'heartbeatAck'");
            clientSocket?.write("heartbeatAck\n");
          }
          return;
        } else if (message == "heartbeatAck") {
          /*
           * This means the host side just received an ACK from the client.
           * The host updates the timestamp to avoid disconnect.
           */
          if (isHost) {
            _lastHeartbeatReceived = DateTime.now();
            logger.t("$_logTag [Host] Received heartbeatAck from client");
          }
          return;
        }

        // 3) For other content or moves, queue them up for further processing
        _messageQueue.add(message);
        await _processMessages();
      },
      onError: (Object error, [StackTrace? stackTrace]) {
        logger.e(
            "$_logTag Socket error: $error${stackTrace != null ? '\n$stackTrace' : ''}");
        _handleDisconnection();
        _protocolHandshakeCompleter?.complete(false);
      },
      onDone: () {
        logger.i(
            "$_logTag Socket closed by opponent at $opponentAddress:${socket.remotePort}");
        _handleDisconnection();
        _protocolHandshakeCompleter?.complete(false);
      },
    );

    // Note:
    // Only call _startHeartbeat() if we are the HOST.
    // If isHost == false, this side will simply wait for "heartbeat" and respond with "heartbeatAck".
    // If you want both sides to send heartbeat, you must adopt a different scheme with separate "ping"/"pong" to avoid infinite loops.
    if (isHost) {
      // Heartbeat from the host side
      // The client will not run this, so no infinite echo occurs.
      // The client simply responds to "heartbeat" with "heartbeatAck".
      _lastHeartbeatReceived = DateTime.now();
      // We may already call _startHeartbeat() after accepting in startHost(),
      // but calling it here is also safe if you want to ensure it's started per-socket basis.
      // Just ensure you don't double-start timers.
      // _startHeartbeat(); // <--- If you want to start here instead,
      //                    // remove the call in startHost().
    }

    GameController().boardSemanticsNotifier.updateSemantics();
  }

  /// Starts heartbeat timers to send heartbeat messages and check for responses.
  void _startHeartbeat() {
    // Host side only:
    _lastHeartbeatReceived = DateTime.now();
    _heartbeatTimer?.cancel();
    _heartbeatCheckTimer?.cancel();

    /*
     * Explanation:
     * - Every second, host sends "heartbeat" to the client.
     * - The client is expected to respond with "heartbeatAck".
     * - On the host side, receiving "heartbeatAck" updates _lastHeartbeatReceived.
     * - If we haven't heard back from the client in >5 seconds, we assume disconnection.
     */
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isHost && clientSocket != null && !clientSocket!.isClosed) {
        clientSocket!.write("heartbeat\n");
        logger.t("$_logTag [Host] Sent heartbeat to $opponentAddress");
      }
    });

    _heartbeatCheckTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (DateTime.now().difference(_lastHeartbeatReceived) >
          const Duration(seconds: 5)) {
        logger.e(
            "$_logTag Heartbeat timeout. No heartbeatAck received for 5 seconds.");
        _handleDisconnection();
      }
    });
    logger.i("$_logTag Heartbeat timers started (Host mode).");
  }

  /// Sends a move or message to the opponent
  void sendMove(String move) {
    if (clientSocket != null && !clientSocket!.isClosed) {
      clientSocket!.write("$move\n");
      logger.t("$_logTag Sent move to $opponentAddress: $move");
    } else {
      logger.w("$_logTag Cannot send move: no active connection");
      throw Exception("No active connection");
    }
  }

  /// Handles incoming network messages.
  void _handleNetworkMessage(String message) {
    // 1) Check if it's a "restart:" scenario
    if (message.startsWith("restart:")) {
      final String command = message.split(":")[1];
      if (command == "request") {
        logger.i("$_logTag Received restart request");
        GameController().handleRestartRequest();
        return;
      } else if (command == "accepted") {
        logger.i("$_logTag Opponent accepted restart request");
        GameController().reset(lanRestart: true);
        GameController().headerTipNotifier.showTip("Game restarted");
        return;
      } else if (command == "rejected") {
        logger.i("$_logTag Opponent rejected restart request");
        GameController().headerTipNotifier.showTip("Restart request rejected");
        return;
      }
    }

    // 2) Check other known message types...
    if (message.startsWith("take back:")) {
      final List<String> parts = message.split(':');
      // e.g. ["take back", "1", "accepted"]
      if (parts.length < 3) {
        // Malformed
        return;
      }
      final String stepCountStr = parts[1]; // "1"
      final String command = parts[2]; // "request" / "accepted" / "rejected"
      final int steps = int.tryParse(stepCountStr) ?? 1;

      if (command == "request") {
        // The remote side is *requesting* a take-back.
        // Show a confirm popup => user can accept or reject.
        GameController().handleTakeBackRequest(steps);
      } else if (command == "accepted") {
        // The remote side accepted our request => do local rollback
        NetworkService._performLanTakeBack(steps);

        // And complete the local pendingTakeBackCompleter => true
        GameController().pendingTakeBackCompleter?.complete(true);
        GameController().pendingTakeBackCompleter = null;

        GameController().headerTipNotifier.showTip("Take back accepted.");
      } else if (command == "rejected") {
        // The remote side rejected => do nothing except notify user
        // Also let our request future know the result
        GameController().pendingTakeBackCompleter?.complete(false);
        GameController().pendingTakeBackCompleter = null;

        GameController()
            .headerTipNotifier
            .showTip("Take back rejected by opponent.");
      }
      return;
    } else if (message.startsWith("resign:")) {
      logger.i("$_logTag Received resign request: $message");
    } else if (message.startsWith("response:aiMovesFirst:")) {
      final String valueStr = message.split("response:aiMovesFirst:")[1];
      final bool hostAiMovesFirst = valueStr.toLowerCase() == "true";
      _handleAiMovesFirstResponse(hostAiMovesFirst);
    } else {
      // 3) Pass everything else to handleLanMove
      GameController().handleLanMove(message);
    }
  }

  static void _performLanTakeBack(int steps) {
    // or: HistoryNavigator.doEachMove(HistoryNavMode.takeBack, steps);
    HistoryNavigator.doEachMove(HistoryNavMode.takeBack, steps);
    // Possibly also update isLanOpponentTurn if needed
    final PieceColor localColor = GameController().getLocalColor();
    GameController().isLanOpponentTurn =
        GameController().position.sideToMove != localColor;
  }

  /// Processes queued network messages sequentially.
  Future<void> _processMessages() async {
    if (_isProcessing) {
      return;
    }
    _isProcessing = true;
    while (_messageQueue.isNotEmpty) {
      final String message = _messageQueue.removeFirst();
      _handleNetworkMessage(message);
      await Future<void>.delayed(Duration.zero);
    }
    _isProcessing = false;
  }

  /// Processes the Host's aiMovesFirst response and updates client settings.
  void _handleAiMovesFirstResponse(bool hostAiMovesFirst) {
    // Host picks aiMovesFirst => client is the opposite
    final bool clientAiMovesFirst = !hostAiMovesFirst;
    DB().generalSettings =
        DB().generalSettings.copyWith(aiMovesFirst: clientAiMovesFirst);
    logger.i(
        "$_logTag Set Client aiMovesFirst to $clientAiMovesFirst (opposite of Host: $hostAiMovesFirst)");

    GameController().headerIconsNotifier.showIcons();
    GameController().boardSemanticsNotifier.updateSemantics();
  }

  /// Handles disconnection events and updates game state
  void _handleDisconnection() {
    // Cancel heartbeat timers
    _heartbeatTimer?.cancel();
    _heartbeatCheckTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatCheckTimer = null;

    logger.i("$_logTag Opponent disconnected from $opponentAddress");
    GameController().headerTipNotifier.showTip("Opponent disconnected");

    dispose();

    GameController().isLanOpponentTurn = false;
    if (GameController().position.phase != Phase.gameOver) {
      GameController()
          .position
          ._setGameOver(PieceColor.draw, GameOverReason.drawStalemateCondition);
      GameController()
          .headerTipNotifier
          .showTip("Game Over due to disconnection.");
    }
    onDisconnected?.call();
  }

  /// Cleans up network resources and resets the state.
  void dispose() {
    clientSocket?.destroy();
    serverSocket?.close();
    discoverySocket?.close();
    _heartbeatTimer?.cancel();
    _heartbeatCheckTimer?.cancel();

    clientSocket = null;
    serverSocket = null;
    discoverySocket = null;
    opponentAddress = null;
    isHost = false;
    onDisconnected = null;
    onClientConnected = null;
    onProtocolMismatch = null;
    _protocolHandshakeCompleter = null;
    _messageQueue.clear();
    _isProcessing = false;

    logger.i("$_logTag Network resources cleaned up");
  }

  /// Returns true if the connection is active.
  bool get isConnected {
    if (isHost) {
      return serverSocket != null &&
          clientSocket != null &&
          !clientSocket!.isClosed;
    }
    return clientSocket != null && !clientSocket!.isClosed;
  }
}

/// Extension to check if a socket is closed more reliably.
extension SocketExtension on Socket {
  bool get isClosed {
    try {
      // If remotePort is 0, this usually indicates it's closed
      return remotePort == 0;
    } catch (e) {
      return true;
    }
  }
}
