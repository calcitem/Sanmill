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

  // Connection constants
  static const int _maxReconnectAttempts = 3;
  static const Duration _reconnectDelay = Duration(seconds: 2);
  static const Duration _connectionTimeout = Duration(seconds: 10);
  static const Duration _heartbeatTimeout = Duration(seconds: 5);
  static const Duration _messageProcessingTimeout = Duration(milliseconds: 500);

  ServerSocket? _serverSocket;
  Socket? _clientSocket;
  bool isHost = false;
  String? _opponentAddress;
  int? _opponentPort;

  /// Called when the remote side disconnects or any fatal error occurs.
  VoidCallback? onDisconnected;

  /// Called whenever a client connects (on the Host side).
  void Function(String clientIp, int clientPort)? onClientConnected;

  /// Called when we detect a protocol mismatch between client and server.
  void Function(String message)? onProtocolMismatch;

  /// Called when connection status changes
  void Function(bool isConnected)? onConnectionStatusChanged;

  /// Whether this service has been disposed; prevents double-disposal or late callbacks.
  bool _disposed = false;

  /// Whether we have started the host's heartbeat.
  bool _heartbeatStarted = false;

  /// Queue of incoming message lines to process in sequence.
  final Queue<String> _messageQueue = Queue<String>();

  /// Prevent re-entrancy when processing the message queue.
  bool _isProcessingMessages = false;

  /// Track whether a reconnection attempt is in progress
  bool _isReconnecting = false;

  /// Discovery socket for responding to LAN "Discovery?" broadcasts.
  RawDatagramSocket? _discoverySocket;

  /// Heartbeat timers for the host side (ping and ping-check).
  Timer? _heartbeatTimer;
  Timer? _heartbeatCheckTimer;

  /// Auto-reconnection timer
  Timer? _reconnectTimer;

  /// Tracks the last time we received a heartbeat or heartbeatAck.
  DateTime _lastHeartbeatReceived = DateTime.now();

  /// A [Completer] for the client's initial handshake (client->host).
  Completer<bool>? _protocolHandshakeCompleter;

  /// Tracks network statistics for diagnostics
  int _messagesSent = 0;
  int _messagesReceived = 0;
  int _reconnectAttempts = 0;
  DateTime? _lastConnectionTime;

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

  /// Get connection status information for diagnostics
  Map<String, dynamic> getConnectionStatus() {
    return {
      'isConnected': isConnected,
      'isHost': isHost,
      'opponentAddress': _opponentAddress,
      'opponentPort': _opponentPort,
      'messagesSent': _messagesSent,
      'messagesReceived': _messagesReceived,
      'reconnectAttempts': _reconnectAttempts,
      'lastConnectionTime': _lastConnectionTime?.toIso8601String(),
      'protocolVersion': protocolVersion,
    };
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
      // Attempt to release any previously occupied port
      await _serverSocket?.close();
      _serverSocket = null;

      // Bind server port
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      isHost = true;
      logger.i("$_logTag Hosting LAN game on port $port");

      // Debounce connection handling
      DateTime? lastConnectionAttempt;

      // Only accept the first incoming client connection;
      // subsequent connections are closed.
      _serverSocket!.listen(
        (Socket socket) {
          final now = DateTime.now();
          final remoteAddress = socket.remoteAddress.address;

          // Prevent too frequent connection attempts (to avoid DoS attacks)
          if (lastConnectionAttempt != null &&
              now.difference(lastConnectionAttempt!).inSeconds < 2) {
            logger.w(
                "$_logTag Connection attempt from $remoteAddress is too frequent, rejected");
            socket.destroy();
            return;
          }
          lastConnectionAttempt = now;

          // Handle existing connection case
          if (_clientSocket != null && !_clientSocket!.isClosed) {
            logger.w(
                "$_logTag Another client ($remoteAddress) attempted to connect; rejected");
            socket.destroy();
            return;
          }

          // Accept new client
          _handleNewClient(socket);
        },
        onError: (Object error, [StackTrace? st]) {
          logger.e("$_logTag Server socket error: $error");
          _handleDisconnection(error: error.toString());
        },
        onDone: () {
          logger.i("$_logTag Server socket closed.");
          if (!_disposed && isHost) {
            _handleDisconnection(reason: "Server socket closed unexpectedly");
          }
        },
      );

      // Listen for "Discovery?" broadcasts
      await _startDiscoveryListener(port);

      // Notify connection status change
      _notifyConnectionStatusChanged(true,
          info: "Started hosting game, waiting for players to join...");
    } catch (e, st) {
      logger.e("$_logTag Failed to start host: $e");
      logger.e("$_logTag Stack trace: $st");
      _handleDisconnection(error: e.toString());
      throw Exception("Failed to start host: $e");
    }
  }

  /// Internal helper to finalize a newly connected client in host mode.
  void _handleNewClient(Socket socket) {
    _clientSocket = socket;
    _opponentAddress = socket.remoteAddress.address;
    _opponentPort = socket.remotePort;
    _lastConnectionTime = DateTime.now();
    logger.i(
        "$_logTag Accepted client at $_opponentAddress:${socket.remotePort}");

    // Reset connection statistics
    _messagesSent = 0;
    _messagesReceived = 0;
    _reconnectAttempts = 0;

    // Notify any callback/UI
    onClientConnected?.call(_opponentAddress!, socket.remotePort);
    _notifyConnectionStatusChanged(true);

    // Start reading line-by-line from the client
    _listenToSocket(socket);

    // If host, begin heartbeat if not already started
    if (isHost && !_heartbeatStarted) {
      _startHeartbeat();
    }
  }

  /// Connect as a client to [host]:[port], retrying up to [retryCount] times.
  Future<void> connectToHost(String host, int port,
      {int retryCount = _maxReconnectAttempts}) async {
    if (_disposed) {
      throw Exception("NetworkService is disposed; cannot connect as client.");
    }
    isHost = false;
    _reconnectAttempts = 0;

    for (int attempt = 0; attempt < retryCount; attempt++) {
      if (_disposed) {
        break;
      }

      _reconnectAttempts = attempt + 1;
      try {
        logger.i(
            "$_logTag Attempting to connect to $host:$port (attempt ${attempt + 1})");

        // Add connection timeout
        final socket = await Socket.connect(host, port)
            .timeout(_connectionTimeout, onTimeout: () {
          throw TimeoutException(
              'Connection timed out after ${_connectionTimeout.inSeconds} seconds');
        });

        if (_disposed) {
          // If we became disposed during connect, close and exit
          socket.destroy();
          return;
        }

        _clientSocket = socket;
        _opponentAddress = host;
        _opponentPort = port;
        _lastConnectionTime = DateTime.now();
        logger.i("$_logTag Connected to host at $host:$port");

        // Reset connection statistics
        _messagesSent = 0;
        _messagesReceived = 0;
        _notifyConnectionStatusChanged(true);

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
      } catch (e, st) {
        logger.e("$_logTag Connect attempt ${attempt + 1} failed: $e");
        logger.d("$_logTag Stack trace: $st");

        // Clean up any partially established connection
        _clientSocket?.destroy();
        _clientSocket = null;

        if (attempt == retryCount - 1) {
          _handleDisconnection(error: e.toString());
          throw Exception("Failed after $retryCount attempts: $e");
        }

        await Future<void>.delayed(_reconnectDelay);
      }
    }
  }

  /// Attempts to reconnect to the last known host address
  Future<bool> attemptReconnect() async {
    if (_disposed ||
        _isReconnecting ||
        isHost ||
        _opponentAddress == null ||
        _opponentPort == null) {
      return false;
    }

    _isReconnecting = true;
    logger.i(
        "$_logTag Attempting to reconnect to $_opponentAddress:$_opponentPort");

    // Notify UI that reconnection is in progress
    GameController().headerTipNotifier.showTip("Attempting to reconnect...");

    try {
      // Use progressive delay for retries
      for (int attempt = 0; attempt < _maxReconnectAttempts; attempt++) {
        if (_disposed) {
          break;
        }

        // Update UI to show current reconnection status
        GameController()
            .headerTipNotifier
            .showTip("Reconnecting (${attempt + 1}/$_maxReconnectAttempts)");

        try {
          await connectToHost(_opponentAddress!, _opponentPort!,
              retryCount: 1); // Try only once each time
          _isReconnecting = false;
          GameController()
              .headerTipNotifier
              .showTip("Reconnected successfully!");
          return true;
        } catch (e) {
          // If it's the last attempt, exit the loop and throw an exception
          if (attempt == _maxReconnectAttempts - 1) {
            continue;
          }

          // Gradually increase wait time
          final waitTime = Duration(seconds: (attempt + 1) * 2);
          await Future<void>.delayed(waitTime);
        }
      }
      // All attempts failed
      throw Exception("Reconnection failed");
    } catch (e) {
      logger.e("$_logTag Reconnection failed: $e");
      _isReconnecting = false;
      GameController()
          .headerTipNotifier
          .showTip("Unable to reconnect, please restart the game");
      return false;
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
      }, onError: (error, st) {
        logger.e("$_logTag Discovery socket error: $error");
        logger.d("$_logTag Stack trace: $st");
      });
    } catch (e, st) {
      logger.e("$_logTag Could not bind discovery socket on port 33334: $e");
      logger.d("$_logTag Stack trace: $st");
    }
  }

  /// Replies to a "Discovery?" message with "Sanmill:localIp:serverPort".
  Future<void> _respondToDiscovery(Datagram datagram, int serverPort) async {
    final localIp = await getLocalIpAddress();
    if (localIp != null && !_disposed) {
      final reply = 'Sanmill:$localIp:$serverPort';
      final replyData = utf8.encode(reply);
      try {
        _discoverySocket?.send(replyData, datagram.address, datagram.port);
        logger.i("$_logTag Replied to discovery request with $reply");
      } catch (e) {
        logger.e("$_logTag Failed to send discovery reply: $e");
      }
    }
  }

  /// Listens line-by-line from [socket]. If we are the client, we only respond to the host's heartbeats.
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

        if (trimmed.isEmpty) {
          return; // Skip empty messages
        }

        _messagesReceived++;
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
            _sendMessageInternal("heartbeatAck");
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
          logger.d("$_logTag Stack trace: $st");
          _handleDisconnection(error: error.toString());
        }
      },
      onDone: () {
        if (!_disposed) {
          logger.i("$_logTag Remote socket closed by $_opponentAddress");
          _handleDisconnection(reason: "Remote socket closed");
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

    try {
      // Longer timeout for processing complex messages
      final timer = Timer(_messageProcessingTimeout * 2, () {
        if (_isProcessingMessages) {
          logger.w(
              "$_logTag Message processing timed out, will continue in the next message loop");
          _isProcessingMessages = false;

          // Do not discard the message queue, but try to process it again in the next clock cycle
          if (_messageQueue.isNotEmpty && !_disposed) {
            Future.delayed(Duration.zero, () => _processMessageQueue());
          }
        }
      });

      int processedCount = 0;
      final startTime = DateTime.now();

      while (_messageQueue.isNotEmpty && !_disposed) {
        final message = _messageQueue.removeFirst();
        _handleNetworkMessage(message);
        processedCount++;

        // Check for message processing limit or time threshold
        if (processedCount >= 5 ||
            DateTime.now().difference(startTime).inMilliseconds > 100) {
          // Temporarily yield the event loop to avoid UI stalling
          await Future<void>.delayed(Duration.zero);
          processedCount = 0;
        }
      }

      timer.cancel();
    } catch (e, st) {
      logger.e("$_logTag Error processing message queue: $e");
      logger.d("$_logTag Stack trace: $st");
    } finally {
      _isProcessingMessages = false;
    }
  }

  /// Internal method to handle protocol handshake lines.
  void _handleProtocol(String line) {
    final parts = line.split(":");
    if (parts.length < 2) {
      logger.w("$_logTag Malformed protocol message: $line");
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
        _handleDisconnection(reason: "Protocol version mismatch");
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

    if (move.isEmpty) {
      logger.w("$_logTag Attempted to send empty message, ignoring");
      return;
    }

    _sendMessageInternal(move);
  }

  /// Internal method to send a message and handle errors
  void _sendMessageInternal(String message) {
    if (_clientSocket != null && !_clientSocket!.isClosed) {
      try {
        _clientSocket!.write("$message\n");
        _messagesSent++;
        logger.t("$_logTag Sent => $message");
      } catch (e, st) {
        logger.e("$_logTag Error sending message: $e");
        logger.d("$_logTag Stack trace: $st");

        // Gracefully handle connection reset exception
        if (e != null && e.toString().contains("Connection reset by peer")) {
          logger
              .w("$_logTag Client disconnected abruptly (during message send)");
          _handleDisconnection(error: "Connection reset by peer");
        } else {
          _handleDisconnection(error: "Send error: $e");
        }
      }
    } else {
      logger.w("$_logTag Attempted to send but no valid client socket.");
      // Do not throw an exception, treat this case as a known connection issue
      _handleDisconnection(reason: "No active connection to send data");
    }
  }

  /// Launch a periodic heartbeat (host side only), checking for heartbeatAck.
  void _startHeartbeat() {
    if (_heartbeatStarted || !isHost || _disposed) {
      return;
    }
    _heartbeatStarted = true;
    _lastHeartbeatReceived = DateTime.now();

    // Consecutive heartbeat failure count
    int consecutiveFailures = 0;
    const int maxConsecutiveFailures = 3;

    // Send heartbeat every second
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || !isHost) {
        return;
      }
      if (_clientSocket == null || _clientSocket!.isClosed) {
        return;
      }

      try {
        _clientSocket!.write("heartbeat\n");
        logger.t("$_logTag [Host] => heartbeat");
        // Reset failure count after successful send
        consecutiveFailures = 0;
      } catch (e) {
        logger.e("$_logTag Error sending heartbeat: $e");
        consecutiveFailures++;

        // Only consider disconnection after multiple consecutive failures
        if (consecutiveFailures >= maxConsecutiveFailures) {
          if (e != null && e.toString().contains("Connection reset by peer")) {
            logger
                .w("$_logTag Client disconnected abruptly (during heartbeat)");
            _handleDisconnection(error: "Connection reset by peer");
          } else {
            _handleDisconnection(error: "Heartbeat send error: $e");
          }
        }
      }
    });

    // Heartbeat check is set to a more aggressive frequency
    _heartbeatCheckTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_disposed) {
        return;
      }
      final diff = DateTime.now().difference(_lastHeartbeatReceived);
      if (diff > _heartbeatTimeout && !_disposed) {
        logger.e(
            "$_logTag Heartbeat timeout (>${_heartbeatTimeout.inSeconds}s). Disconnecting...");
        _handleDisconnection(reason: "Heartbeat timeout");
      }
    });
  }

  /// Handles incoming game-control or normal messages (excluding heartbeat/protocol).
  void _handleNetworkMessage(String message) {
    if (_disposed) {
      return;
    }

    // Validate message format
    if (message.isEmpty) {
      logger.w("$_logTag Received empty message, ignoring");
      return;
    }

    try {
      // Handle "restart:" commands
      if (message.startsWith("restart:")) {
        final parts = message.split(":");
        if (parts.length < 2) {
          logger.w("$_logTag Malformed restart message: $message");
          return;
        }

        final command = parts[1];
        if (command == "request") {
          logger.i("$_logTag Received restart request");
          GameController().handleRestartRequest();
        } else if (command == "accepted") {
          logger.i("$_logTag Opponent accepted restart request");
          GameController().reset(lanRestart: true);
          GameController().headerTipNotifier.showTip("Game restarted");
        } else if (command == "rejected") {
          logger.i("$_logTag Opponent rejected restart request");
          GameController()
              .headerTipNotifier
              .showTip("Restart request rejected");
        } else {
          logger.w("$_logTag Unknown restart command: $command");
        }
        return;
      }

      // Handle "take back:" commands
      if (message.startsWith("take back:")) {
        final parts =
            message.split(':'); // ["take back", "1", "request/accepted..."]
        if (parts.length < 3) {
          logger.w("$_logTag Malformed take back message: $message");
          return; // Malformed
        }

        final stepCountStr = parts[1];
        final command = parts[2];

        final steps = int.tryParse(stepCountStr);
        if (steps == null || steps <= 0) {
          logger.w(
              "$_logTag Invalid step count in take back message: $stepCountStr");
          return;
        }

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
        } else {
          logger.w("$_logTag Unknown take back command: $command");
        }
        return;
      }

      // Handle "resign:"
      if (message.startsWith("resign:")) {
        logger.i("$_logTag Received resign request: $message");
        // Handle resignation in GameController
        GameController().handleResignation();
        return;
      }

      // Handle "response:aiMovesFirst:"
      if (message.startsWith("response:aiMovesFirst:")) {
        final parts = message.split(":");
        if (parts.length < 3) {
          logger.w("$_logTag Malformed aiMovesFirst response: $message");
          return;
        }

        final valueStr = parts[2];
        final bool hostAiMovesFirst = valueStr.toLowerCase() == "true";
        _handleAiMovesFirstResponse(hostAiMovesFirst);
        return;
      }

      // Otherwise, pass to the game logic
      logger.i("$_logTag Normal message => $message");
      GameController().handleLanMove(message);
    } catch (e, st) {
      logger.e("$_logTag Error handling network message: $e");
      logger.d("$_logTag Stack trace: $st");
      // Message handling errors shouldn't disconnect the session
    }
  }

  /// Executes the local take-back by rolling back moves, then updates turn for LAN logic.
  static void _performLanTakeBack(int steps) {
    try {
      // For example, use the HistoryNavigator or direct logic:
      HistoryNavigator.doEachMove(HistoryNavMode.takeBack, steps);
      // Possibly update the local turn
      final localColor = GameController().getLocalColor();
      GameController().isLanOpponentTurn =
          GameController().position.sideToMove != localColor;
    } catch (e, st) {
      logger.e("$_logTag Error performing take-back: $e");
      logger.d("$_logTag Stack trace: $st");
    }
  }

  /// Processes "response:aiMovesFirst:true/false" from the host.
  void _handleAiMovesFirstResponse(bool hostAiMovesFirst) {
    try {
      // If the host picks true => client is the opposite (false), etc.
      final bool clientAiMovesFirst = !hostAiMovesFirst;
      DB().generalSettings =
          DB().generalSettings.copyWith(aiMovesFirst: clientAiMovesFirst);
      logger.i(
          "$_logTag Updated client aiMovesFirst=$clientAiMovesFirst (host=$hostAiMovesFirst)");

      // Update UI if needed
      GameController().headerIconsNotifier.showIcons();
      GameController().boardSemanticsNotifier.updateSemantics();
    } catch (e, st) {
      logger.e("$_logTag Error handling AI moves first response: $e");
      logger.d("$_logTag Stack trace: $st");
    }
  }

  /// Handles disconnection from either side, cleaning up and notifying the GameController.
  void _handleDisconnection({String? reason, String? error}) {
    if (_disposed) {
      return; // Already handled
    }

    final String disconnectReason = error ?? reason ?? "Unknown reason";
    // Provide a more user-friendly message
    String userFriendlyMessage = "Disconnected from opponent";

    if (error != null && error.contains("Connection reset by peer")) {
      logger.i(
          "$_logTag Client disconnected abruptly (connection reset by peer)");
      userFriendlyMessage = "The opponent may have left the game";
    } else if (disconnectReason.contains("timeout")) {
      userFriendlyMessage = "Connection timed out, network connection unstable";
    } else if (disconnectReason.contains("refused")) {
      userFriendlyMessage = "Connection refused, the server may be down";
    }

    logger.i("$_logTag Opponent disconnected: $disconnectReason");

    // Use a more user-friendly message
    GameController().headerTipNotifier.showTip(userFriendlyMessage);

    // If the game is still ongoing, declare a draw or other result
    GameController().isLanOpponentTurn = false;
    if (GameController().position.phase != Phase.gameOver) {
      GameController().position._setGameOver(
            PieceColor.draw,
            GameOverReason.drawStalemateCondition,
          );
      GameController()
          .headerTipNotifier
          .showTip("$userFriendlyMessage, game over");
    }

    // Notify connection status change
    _notifyConnectionStatusChanged(false, info: userFriendlyMessage);

    // Clean up resources
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
    } catch (e) {
      logger.e("$_logTag Error destroying client socket: $e");
    }
    try {
      _serverSocket?.close();
    } catch (e) {
      logger.e("$_logTag Error closing server socket: $e");
    }
    try {
      _discoverySocket?.close();
    } catch (e) {
      logger.e("$_logTag Error closing discovery socket: $e");
    }

    _clientSocket = null;
    _serverSocket = null;
    _discoverySocket = null;

    _heartbeatTimer?.cancel();
    _heartbeatCheckTimer?.cancel();
    _reconnectTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatCheckTimer = null;
    _reconnectTimer = null;

    _messageQueue.clear();
    _isProcessingMessages = false;
    _protocolHandshakeCompleter = null;
    _heartbeatStarted = false;
    _isReconnecting = false;

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
    } catch (e, st) {
      logger.e("$_logTag Failed to get local IP addresses: $e");
      logger.d("$_logTag Stack trace: $st");
    }
    return null;
  }

  /// Retrieves **all** non-loopback IPv4 addresses from the device's interfaces.
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
    } catch (e, st) {
      logger.e("$_logTag Failed to get local IP addresses: $e");
      logger.d("$_logTag Stack trace: $st");
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
    Timer? timeoutTimer;

    try {
      // Bind an ephemeral port for broadcasting
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      // Set up timeout
      timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          logger.i(
              "$_logTag Host discovery timed out after ${timeout.inSeconds}s");
          completer.complete(null);
        }
      });

      subscription = socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final dg = socket!.receive();
          if (dg != null) {
            try {
              final msg = utf8.decode(dg.data).trim();
              if (msg.startsWith('Sanmill:')) {
                final parts = msg.split(':');
                if (parts.length == 3) {
                  if (!completer.isCompleted) {
                    final result = '${parts[1]}:${parts[2]}';
                    logger.i("$_logTag Found host: $result");
                    completer.complete(result);
                  }
                } else {
                  logger.w("$_logTag Malformed discovery response: $msg");
                }
              }
            } catch (e) {
              logger.e("$_logTag Error decoding discovery response: $e");
            }
          }
        }
      }, onError: (error, st) {
        logger.e("$_logTag Discovery socket error: $error");
        logger.d("$_logTag Stack trace: $st");
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      });

      // Send broadcast multiple times to increase reliability
      for (int i = 0; i < 3; i++) {
        if (completer.isCompleted) {
          break;
        }
        try {
          socket.send(
            utf8.encode('Discovery?'),
            InternetAddress("255.255.255.255"),
            33334,
          );
          logger.d(
              "$_logTag Sent broadcast discovery request (attempt ${i + 1})");
          await Future.delayed(const Duration(seconds: 1));
        } catch (e) {
          logger.e("$_logTag Error sending discovery broadcast: $e");
        }
      }

      return await completer.future;
    } catch (e, st) {
      logger.e("$_logTag discoverHost error: $e");
      logger.d("$_logTag Stack trace: $st");
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      return null;
    } finally {
      timeoutTimer?.cancel();
      subscription?.cancel();
      socket?.close();
    }
  }

  /// Notify connection status change, with additional information
  void _notifyConnectionStatusChanged(bool isConnected, {String? info}) {
    // First call the callback
    onConnectionStatusChanged?.call(isConnected);

    // Update UI to show connection status
    if (isConnected) {
      final String statusInfo = info ?? "Connected";
      GameController().headerTipNotifier.showTip(statusInfo);
    } else if (info != null) {
      GameController().headerTipNotifier.showTip(info);
    }

    // Update other UI elements to reflect connection status
    GameController().headerIconsNotifier.showIcons();
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
