// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// network_service.dart

// ignore_for_file: always_specify_types

part of '../mill.dart';

/// NetworkService handles LAN hosting, client connections, discovery, and heartbeat checks.
/// It also supports special commands such as "restart:", "take back:", "resign:",
/// and "response:aiMovesFirst:" to coordinate with the GameController.
class NetworkService {
  static const String _logTag = "[Network]";
  static const String protocolVersion = "1.0";

  ServerSocket? _serverSocket;
  Socket? _clientSocket;
  bool isHost = false;
  String? _opponentAddress;

  /// Called when the remote side disconnects or any fatal error occurs.
  VoidCallback? onDisconnected;

  /// Called whenever a client connects (on the Host side).
  void Function(String clientIp, int clientPort)? onClientConnected;

  /// Called when we detect a protocol mismatch between client and server.
  void Function(String message)? onProtocolMismatch;

  /// Whether this service has been disposed; prevents double-disposal or late callbacks.
  bool _disposed = false;

  /// Whether we have started the host’s heartbeat.
  bool _heartbeatStarted = false;

  /// Queue of incoming message lines to process in sequence.
  final Queue<String> _messageQueue = Queue<String>();

  /// Prevent re-entrancy when processing the message queue.
  bool _isProcessingMessages = false;

  /// Discovery socket for responding to LAN "Discovery?" broadcasts.
  RawDatagramSocket? _discoverySocket;

  /// Heartbeat timers for the host side (ping and ping-check).
  Timer? _heartbeatTimer;
  Timer? _heartbeatCheckTimer;

  /// Tracks the last time we received a heartbeat or heartbeatAck.
  DateTime _lastHeartbeatReceived = DateTime.now();

  /// A [Completer] for the client's initial handshake (client->host).
  Completer<bool>? _protocolHandshakeCompleter;

  /// Public getter for the underlying server socket,
  /// needed by external code to check if we're hosting.
  ServerSocket? get serverSocket => _serverSocket;

  /// Returns true if we are currently connected (as host or client).
  bool get isConnected {
    if (_disposed) {
      return false;
    }
    if (isHost) {
      return _serverSocket != null &&
          _clientSocket != null &&
          !_clientSocket!.isClosed;
    }
    // For the client, just check if the socket is not closed.
    return _clientSocket != null && !_clientSocket!.isClosed;
  }

  /// Starts hosting on the specified [port], allowing exactly one client,
  /// and begins listening for LAN discovery requests on port 33334.
  Future<void> startHost(int port,
      {void Function(String, int)? onClientConnected}) async {
    if (_disposed) {
      throw Exception("NetworkService has been disposed; cannot start host.");
    }
    this.onClientConnected = onClientConnected;
    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      isHost = true;
      logger.i("$_logTag Hosting LAN game on port $port");

      // Accept only the first incoming client connection;
      // subsequent connections are closed.
      _serverSocket!.listen(
        (Socket socket) {
          if (_clientSocket != null && !_clientSocket!.isClosed) {
            logger.w(
                "$_logTag Another client attempted to connect; rejecting it.");
            socket.destroy();
            return;
          }
          // Accept this new client
          _handleNewClient(socket);
        },
        onError: (Object error, [StackTrace? st]) {
          logger.e("$_logTag Server socket error: $error");
          _handleDisconnection();
        },
        onDone: () {
          logger.i("$_logTag Server socket closed.");
        },
      );

      // Listen for "Discovery?" broadcasts on 33334
      await _startDiscoveryListener(port);
    } catch (e) {
      logger.e("$_logTag Failed to start host: $e");
      throw Exception("Failed to start host: $e");
    }
  }

  /// Internal helper to finalize a newly connected client in host mode.
  void _handleNewClient(Socket socket) {
    _clientSocket = socket;
    _opponentAddress = socket.remoteAddress.address;
    logger.i(
        "$_logTag Accepted client at $_opponentAddress:${socket.remotePort}");

    // Notify any callback/UI
    onClientConnected?.call(_opponentAddress!, socket.remotePort);

    // Start reading line-by-line from the client
    _listenToSocket(socket);

    // If host, begin heartbeat if not already started
    if (isHost && !_heartbeatStarted) {
      _startHeartbeat();
    }
  }

  /// Connect as a client to [host]:[port], retrying up to [retryCount] times.
  Future<void> connectToHost(String host, int port,
      {int retryCount = 3}) async {
    if (_disposed) {
      throw Exception("NetworkService is disposed; cannot connect as client.");
    }
    isHost = false;
    for (int attempt = 0; attempt < retryCount; attempt++) {
      if (_disposed) {
        break;
      }
      try {
        final socket = await Socket.connect(host, port);
        if (_disposed) {
          // If we became disposed during connect, close and exit
          socket.destroy();
          return;
        }
        _clientSocket = socket;
        _opponentAddress = host;
        logger.i("$_logTag Connected to host at $host:$port");

        // Start reading line-by-line
        _listenToSocket(socket);

        // Initiate the protocol handshake for the client side.
        _protocolHandshakeCompleter = Completer<bool>();
        sendMove("protocol:$protocolVersion");

        // Wait up to 5s for handshake
        final success = await _protocolHandshakeCompleter!.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            logger.e("$_logTag Protocol handshake timed out");
            return false;
          },
        );
        if (!success) {
          throw Exception("Protocol handshake failed or mismatched.");
        }

        // Optionally ask host about AI moves first
        sendMove("request:aiMovesFirst");
        return; // Connected and handshake done
      } catch (e) {
        logger.e("$_logTag Connect attempt ${attempt + 1} failed: $e");
        _handleDisconnection();
        if (attempt == retryCount - 1) {
          throw Exception("Failed after $retryCount attempts: $e");
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  /// Binds to port 33334 to respond to "Discovery?" messages with "Sanmill:IP:port".
  Future<void> _startDiscoveryListener(int serverPort) async {
    if (_disposed) {
      return;
    }
    try {
      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        33334,
      );
      logger.i("$_logTag Discovery listener on port 33334 started.");

      _discoverySocket!.listen((RawSocketEvent event) {
        if (_disposed) {
          return;
        }
        if (event == RawSocketEvent.read) {
          final dg = _discoverySocket!.receive();
          if (dg != null) {
            final message = utf8.decode(dg.data).trim();
            if (message == 'Discovery?') {
              _respondToDiscovery(dg, serverPort);
            }
          }
        }
      });
    } catch (e) {
      logger.e("$_logTag Could not bind discovery socket on port 33334: $e");
    }
  }

  /// Replies to a "Discovery?" message with "Sanmill:localIp:serverPort".
  Future<void> _respondToDiscovery(Datagram datagram, int serverPort) async {
    final localIp = await getLocalIpAddress();
    if (localIp != null && !_disposed) {
      final reply = 'Sanmill:$localIp:$serverPort';
      final replyData = utf8.encode(reply);
      _discoverySocket?.send(replyData, datagram.address, datagram.port);
      logger.i("$_logTag Replied to discovery request with $reply");
    }
  }

  /// Listens line-by-line from [socket]. If we are the client, we only respond to the host’s heartbeats.
  void _listenToSocket(Socket socket) {
    socket
        .cast<List<int>>() // treat as Stream<List<int>>
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (String line) {
        if (_disposed) {
          return;
        }
        final remotePort = socket.remotePort;
        final trimmed = line.trim();
        logger.t(
            "$_logTag Received from $_opponentAddress:$remotePort => $trimmed");

        // 1) Protocol handshake
        if (trimmed.startsWith("protocol:")) {
          _handleProtocol(trimmed);
          return;
        }
        // 2) Heartbeat logic
        if (trimmed == "heartbeat") {
          // If we are client, respond with "heartbeatAck"
          if (!isHost) {
            _lastHeartbeatReceived = DateTime.now();
            _clientSocket?.write("heartbeatAck\n");
            logger
                .t("$_logTag [Client] Received heartbeat -> sent heartbeatAck");
          }
          return;
        }
        if (trimmed == "heartbeatAck") {
          // If we are host, update last heartbeat time
          if (isHost) {
            _lastHeartbeatReceived = DateTime.now();
            logger.t("$_logTag [Host] Received heartbeatAck");
          }
          return;
        }

        // 3) Normal or control messages
        _messageQueue.add(trimmed);
        _processMessageQueue();
      },
      onError: (error, st) {
        if (!_disposed) {
          logger.e("$_logTag Socket error: $error");
          _handleDisconnection();
        }
      },
      onDone: () {
        if (!_disposed) {
          logger.i("$_logTag Remote socket closed by $_opponentAddress");
          _handleDisconnection();
        }
      },
    );
  }

  /// Processes queued messages in FIFO order, to avoid concurrency issues.
  Future<void> _processMessageQueue() async {
    if (_isProcessingMessages || _disposed) {
      return;
    }
    _isProcessingMessages = true;

    while (_messageQueue.isNotEmpty && !_disposed) {
      final message = _messageQueue.removeFirst();
      _handleNetworkMessage(message);
      await Future<void>.delayed(Duration.zero);
    }
    _isProcessingMessages = false;
  }

  /// Internal method to handle protocol handshake lines.
  void _handleProtocol(String line) {
    final parts = line.split(":");
    if (parts.length < 2) {
      return;
    }
    final theirProtocol = parts[1];

    if (isHost) {
      // Host responds
      sendMove("protocol:$protocolVersion");
      if (theirProtocol != protocolVersion) {
        final msg =
            "Protocol mismatch: server=$protocolVersion, client=$theirProtocol";
        logger.w("$_logTag $msg");
        onProtocolMismatch?.call(msg);
        // Optionally disconnect here if needed
      }
    } else {
      // Client verifies server's version
      if (theirProtocol != protocolVersion) {
        final msg =
            "Protocol mismatch: client=$protocolVersion, server=$theirProtocol";
        logger.w("$_logTag $msg");
        onProtocolMismatch?.call(msg);
        _handleDisconnection();
        _protocolHandshakeCompleter?.complete(false);
      } else {
        logger.i("$_logTag Protocol handshake successful");
        _protocolHandshakeCompleter?.complete(true);
      }
    }
  }

  /// Sends a message (moves/commands) to the other side.
  void sendMove(String move) {
    if (_disposed) {
      throw Exception("NetworkService is disposed; cannot send message.");
    }
    if (_clientSocket != null && !_clientSocket!.isClosed) {
      _clientSocket!.write("$move\n");
      logger.t("$_logTag Sent => $move");
    } else {
      logger.w("$_logTag Attempted to send but no valid client socket.");
      throw Exception("No active connection to send data.");
    }
  }

  /// Launch a periodic heartbeat (host side only), checking for heartbeatAck.
  void _startHeartbeat() {
    if (_heartbeatStarted || !isHost || _disposed) {
      return;
    }
    _heartbeatStarted = true;
    _lastHeartbeatReceived = DateTime.now();

    // Send heartbeat every second
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || !isHost) {
        return;
      }
      if (_clientSocket == null || _clientSocket!.isClosed) {
        return;
      }

      _clientSocket!.write("heartbeat\n");
      logger.t("$_logTag [Host] => heartbeat");
    });

    // Check for ACK every second
    _heartbeatCheckTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) {
        return;
      }
      final diff = DateTime.now().difference(_lastHeartbeatReceived);
      if (diff > const Duration(seconds: 5) && !_disposed) {
        logger.e("$_logTag Heartbeat timeout (>5s). Disconnecting...");
        _handleDisconnection();
      }
    });
  }

  /// Handles incoming game-control or normal messages (excluding heartbeat/protocol).
  void _handleNetworkMessage(String message) {
    if (_disposed) {
      return;
    }

    // Handle "restart:" commands
    if (message.startsWith("restart:")) {
      final command = message.split(":")[1];
      if (command == "request") {
        logger.i("$_logTag Received restart request");
        GameController().handleRestartRequest();
      } else if (command == "accepted") {
        logger.i("$_logTag Opponent accepted restart request");
        GameController().reset(lanRestart: true);
        GameController().headerTipNotifier.showTip("Game restarted");
      } else if (command == "rejected") {
        logger.i("$_logTag Opponent rejected restart request");
        GameController().headerTipNotifier.showTip("Restart request rejected");
      }
      return;
    }

    // Handle "take back:" commands
    if (message.startsWith("take back:")) {
      final parts =
          message.split(':'); // ["take back", "1", "request/accepted..."]
      if (parts.length < 3) {
        return; // Malformed
      }
      final stepCountStr = parts[1];
      final command = parts[2];
      final steps = int.tryParse(stepCountStr) ?? 1;

      if (command == "request") {
        // Opponent requests a take-back
        GameController().handleTakeBackRequest(steps);
      } else if (command == "accepted") {
        // Opponent accepted our request
        _performLanTakeBack(steps);
        GameController().pendingTakeBackCompleter?.complete(true);
        GameController().pendingTakeBackCompleter = null;
        GameController().headerTipNotifier.showTip("Take back accepted.");
      } else if (command == "rejected") {
        // Opponent rejected
        GameController().pendingTakeBackCompleter?.complete(false);
        GameController().pendingTakeBackCompleter = null;
        GameController().headerTipNotifier.showTip("Take back rejected.");
      }
      return;
    }

    // Handle "resign:"
    if (message.startsWith("resign:")) {
      logger.i("$_logTag Received resign request: $message");
      // You might handle it in GameController, e.g. GameController().handleResignation(...)
      return;
    }

    // Handle "response:aiMovesFirst:"
    if (message.startsWith("response:aiMovesFirst:")) {
      final valueStr = message.split("response:aiMovesFirst:")[1];
      final bool hostAiMovesFirst = valueStr.toLowerCase() == "true";
      _handleAiMovesFirstResponse(hostAiMovesFirst);
      return;
    }

    // Otherwise, pass to the game logic
    logger.i("$_logTag Normal message => $message");
    GameController().handleLanMove(message);
  }

  /// Executes the local take-back by rolling back moves, then updates turn for LAN logic.
  static void _performLanTakeBack(int steps) {
    // For example, use the HistoryNavigator or direct logic:
    HistoryNavigator.doEachMove(HistoryNavMode.takeBack, steps);
    // Possibly update the local turn
    final localColor = GameController().getLocalColor();
    GameController().isLanOpponentTurn =
        GameController().position.sideToMove != localColor;
  }

  /// Processes "response:aiMovesFirst:true/false" from the host.
  void _handleAiMovesFirstResponse(bool hostAiMovesFirst) {
    // If the host picks true => client is the opposite (false), etc.
    final bool clientAiMovesFirst = !hostAiMovesFirst;
    DB().generalSettings =
        DB().generalSettings.copyWith(aiMovesFirst: clientAiMovesFirst);
    logger.i(
        "$_logTag Updated client aiMovesFirst=$clientAiMovesFirst (host=$hostAiMovesFirst)");

    // Update UI if needed
    GameController().headerIconsNotifier.showIcons();
    GameController().boardSemanticsNotifier.updateSemantics();
  }

  /// Handles disconnection from either side, cleaning up and notifying the GameController.
  void _handleDisconnection() {
    if (_disposed) {
      return; // Already disposed
    }
    // Show a tip or mark the game as disconnected
    logger.i("$_logTag Opponent disconnected from $_opponentAddress");
    GameController().headerTipNotifier.showTip("Opponent disconnected");

    // If the game is still running, declare a draw or other outcome
    GameController().isLanOpponentTurn = false;
    if (GameController().position.phase != Phase.gameOver) {
      GameController().position._setGameOver(
            PieceColor.draw,
            GameOverReason.drawStalemateCondition,
          );
      GameController()
          .headerTipNotifier
          .showTip("Game Over due to disconnection.");
    }

    // Dispose local resources
    _disposeInternals();
    onDisconnected?.call();
  }

  /// Public method for external callers to dispose this service.
  void dispose() {
    if (_disposed) {
      return;
    }
    logger.i("$_logTag dispose() called by user");
    _disposeInternals();
  }

  /// Internal method that releases all network resources, cancels timers, and clears queues.
  void _disposeInternals() {
    if (_disposed) {
      return;
    }
    _disposed = true;

    try {
      _clientSocket?.destroy();
    } catch (_) {}
    try {
      _serverSocket?.close();
    } catch (_) {}
    try {
      _discoverySocket?.close();
    } catch (_) {}

    _clientSocket = null;
    _serverSocket = null;
    _discoverySocket = null;

    _heartbeatTimer?.cancel();
    _heartbeatCheckTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatCheckTimer = null;

    _messageQueue.clear();
    _isProcessingMessages = false;
    _protocolHandshakeCompleter = null;

    logger.i("$_logTag Network resources fully disposed");
  }

  /// Retrieves the first non-loopback IPv4 address from local device (mobile or desktop).
  static Future<String?> getLocalIpAddress() async {
    try {
      if (kIsWeb) {
        // No direct local IP on web
        return null;
      }
      if (Platform.isAndroid || Platform.isIOS) {
        final info = NetworkInfo();
        final wifiIP = await info.getWifiIP();
        if (wifiIP != null && wifiIP.isNotEmpty) {
          return wifiIP;
        }
        logger.w("$_logTag No Wi-Fi IP found on mobile platform.");
        return null;
      }
      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      logger.e("$_logTag Failed to get local IP addresses: $e");
    }
    return null;
  }

  /// Retrieves **all** non-loopback IPv4 addresses from the device’s interfaces.
  static Future<List<String>> getLocalIpAddresses() async {
    final List<String> result = <String>[];
    try {
      if (kIsWeb) {
        return result;
      }
      if (Platform.isAndroid || Platform.isIOS) {
        final info = NetworkInfo();
        final wifiIP = await info.getWifiIP();
        if (wifiIP != null && wifiIP.isNotEmpty) {
          result.add(wifiIP);
          return result;
        }
        logger.w("$_logTag No Wi-Fi IP found on mobile platform.");
        return result;
      }
      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            result.add(addr.address);
          }
        }
      }
    } catch (e) {
      logger.e("$_logTag Failed to get local IP addresses: $e");
    }
    return result;
  }

  /// Broadcasts "Discovery?" on port 33334 and waits for "Sanmill:\<IP>:\<port>" up to [timeout].
  static Future<String?> discoverHost({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final completer = Completer<String?>();
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    try {
      // Bind an ephemeral port for broadcasting
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      subscription = socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final dg = socket!.receive();
          if (dg != null) {
            final msg = utf8.decode(dg.data).trim();
            if (msg.startsWith('Sanmill:')) {
              final parts = msg.split(':');
              if (parts.length == 3) {
                if (!completer.isCompleted) {
                  completer.complete('${parts[1]}:${parts[2]}');
                }
              }
            }
          }
        }
      });

      // Send broadcast
      socket.send(
        utf8.encode('Discovery?'),
        InternetAddress("255.255.255.255"),
        33334,
      );

      // Wait for a response or timeout
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } catch (e) {
      logger.e("$_logTag discoverHost error: $e");
      return null;
    } finally {
      subscription?.cancel();
      socket?.close();
    }
  }
}

/// Extension to quickly check if a [Socket] is closed.
extension SocketExtension on Socket {
  bool get isClosed {
    try {
      return remotePort == 0;
    } catch (_) {
      return true;
    }
  }
}
