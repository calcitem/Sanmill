// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// network_service.dart

// ignore_for_file: always_specify_types

part of '../mill.dart';

/// NetworkService handles LAN hosting, client connections, discovery, and heartbeat checks.
/// This version only listens on and broadcasts from the specifically selected IP.
/// No usage of 255.255.255.255 anymore.
class NetworkService with WidgetsBindingObserver {
  NetworkService() {
    WidgetsBinding.instance.addObserver(this);
  }

  static const String _logTag = "[Network]";
  static const String protocolVersion = "1.0";

  static const int _maxReconnectAttempts = 3;
  static const Duration _reconnectDelay = Duration(seconds: 2);
  static const Duration _connectionTimeout = Duration(seconds: 10);
  static const Duration _heartbeatTimeout = Duration(seconds: 5);
  static const Duration _messageProcessingTimeout = Duration(milliseconds: 500);

  /// Store the user-chosen IP when starting a host or if provided at creation.
  String? _boundIpAddress;

  ServerSocket? _serverSocket;
  Socket? _clientSocket;
  bool isHost = false;
  String? _opponentAddress;
  int? _opponentPort;

  VoidCallback? onDisconnected;
  void Function(String clientIp, int clientPort)? onClientConnected;
  void Function(String message)? onProtocolMismatch;
  void Function(bool isConnected)? onConnectionStatusChanged;

  bool _disposed = false;
  bool _heartbeatStarted = false;

  final Queue<String> _messageQueue = Queue<String>();
  bool _isProcessingMessages = false;
  bool _isReconnecting = false;

  RawDatagramSocket? _discoverySocket;
  Timer? _heartbeatTimer;
  Timer? _heartbeatCheckTimer;
  Timer? _reconnectTimer;
  DateTime _lastHeartbeatReceived = DateTime.now();
  Completer<bool>? _protocolHandshakeCompleter;

  int _messagesSent = 0;
  int _messagesReceived = 0;
  int _reconnectAttempts = 0;
  DateTime? _lastConnectionTime;

  bool _isInBackground = false;
  DateTime? _backgroundStartTime;
  static const Duration _maxBackgroundTime = Duration(minutes: 2);

  ServerSocket? get serverSocket => _serverSocket;

  bool get isConnected {
    if (_disposed) {
      return false;
    }
    if (isHost) {
      return _serverSocket != null &&
          _clientSocket != null &&
          !_clientSocket!.isClosed;
    }
    return _clientSocket != null && !_clientSocket!.isClosed;
  }

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) {
      return;
    }

    logger.i("$_logTag App lifecycle changed to $state");

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _isInBackground = true;
      _backgroundStartTime = DateTime.now();
      logger.i("$_logTag App went to background");
    } else if (state == AppLifecycleState.resumed) {
      if (_isInBackground) {
        _isInBackground = false;
        _handleAppResumed();
      }
    }
  }

  void _handleAppResumed() {
    if (_disposed) {
      return;
    }

    logger.i("$_logTag App resumed from background");

    if (_backgroundStartTime != null) {
      final timeInBackground = DateTime.now().difference(_backgroundStartTime!);
      if (timeInBackground > _maxBackgroundTime) {
        logger.w(
            "$_logTag App was in background for ${timeInBackground.inSeconds}s, checking connection");
        _checkConnectionAfterResume();
      } else {
        logger.i(
            "$_logTag App was in background for ${timeInBackground.inSeconds}s, still OK");
        if (isHost && _serverSocket != null) {
          Future.delayed(const Duration(milliseconds: 500), () {
            _checkConnectionAfterResume();
          });
        }
      }
    }

    _backgroundStartTime = null;
  }

  void _checkConnectionAfterResume() {
    if (_disposed) {
      return;
    }

    try {
      if (isHost && _serverSocket != null) {
        if (_serverSocket!.port == 0) {
          logger.w("$_logTag Server socket invalid after resume");
          _handleDisconnection(reason: "Server socket invalid after wake up");
          return;
        }

        try {
          _serverSocket!.address;
        } catch (e) {
          logger.w("$_logTag Server socket exception after resume: $e");
          _handleDisconnection(reason: "Server socket invalid: $e");
          return;
        }

        if (_clientSocket != null && _clientSocket!.isClosed) {
          logger.w("$_logTag Client socket closed after resume");
          _handleDisconnection(reason: "Client disconnected while asleep");
          return;
        }

        _sendTestHeartbeatAfterResume();
      } else if (!isHost && _clientSocket != null) {
        if (_clientSocket!.isClosed) {
          logger.w("$_logTag Host socket closed after resume");
          _handleDisconnection(reason: "Host disconnected while asleep");
          return;
        }
        _sendTestHeartbeatAfterResume();
      }
    } catch (e, st) {
      logger.e("$_logTag Error checking connection after resume: $e");
      logger.d("$_logTag Stack trace: $st");
      _handleDisconnection(error: "Connection error after wake: $e");
    }
  }

  void _sendTestHeartbeatAfterResume() {
    if (_disposed) {
      return;
    }
    try {
      _sendMessageInternal("heartbeat");
      logger.i("$_logTag Sent test heartbeat after resume");
      Future.delayed(const Duration(seconds: 3), () {
        if (!_disposed && isConnected) {
          logger.i("$_logTag Connection is still alive after resume");
        }
      });
    } catch (e) {
      logger.e("$_logTag Error sending test heartbeat: $e");
      _handleDisconnection(error: "Failed to send data after wake: $e");
    }
  }

  /// Starts hosting on the selected IP address.
  Future<void> startHost(
    int port, {
    String? localIpAddress,
    void Function(String, int)? onClientConnected,
  }) async {
    if (_disposed) {
      throw Exception("NetworkService disposed; cannot start host.");
    }

    this.onClientConnected = onClientConnected;

    try {
      // Get context and message *before* any async gaps
      final BuildContext? context = rootScaffoldMessengerKey.currentContext;
      final String infoMsg = context != null
          ? S.of(context).startedHostingGameWaitingForPlayersToJoin
          : "Started hosting, waiting for players..."; // Fallback message

      await _serverSocket?.close();
      _serverSocket = null;

      // Always use the passed IP if not null
      final String? bindIp = localIpAddress ?? await getLocalIpAddress();
      if (bindIp == null) {
        throw Exception("No valid IP to bind to");
      }
      _boundIpAddress = bindIp; // Store it for later usage

      _serverSocket = await ServerSocket.bind(InternetAddress(bindIp), port);
      isHost = true;
      logger.i("$_logTag Hosting on $bindIp:$port");

      DateTime? lastConnAttempt;

      _serverSocket!.listen(
        (Socket socket) {
          final now = DateTime.now();
          final remoteAddr = socket.remoteAddress.address;

          if (lastConnAttempt != null &&
              now.difference(lastConnAttempt!).inSeconds < 2) {
            logger
                .w("$_logTag Connection from $remoteAddr too frequent, reject");
            socket.destroy();
            return;
          }
          lastConnAttempt = now;

          if (_clientSocket != null && !_clientSocket!.isClosed) {
            logger.w("$_logTag Another client tried to connect; rejected");
            socket.destroy();
            return;
          }

          _handleNewClient(socket);
        },
        onError: (error, st) {
          logger.e("$_logTag Server socket error: $error");
          _handleDisconnection(error: error.toString());
        },
        onDone: () {
          logger.i("$_logTag Server socket closed");
          if (!_disposed && isHost) {
            _handleDisconnection(reason: "Server socket closed unexpectedly");
          }
        },
      );

      // Listen for discovery requests on the *same* selected IP
      await _startDiscoveryListener(port, localIpAddress: bindIp);

      // Now that hosting is confirmed, notify with the pre-fetched message
      _notifyConnectionStatusChanged(true, info: infoMsg);
    } catch (e, st) {
      logger.e("$_logTag Failed to start host: $e");
      logger.e("$_logTag Stack trace: $st");
      _handleDisconnection(error: e.toString());
      throw Exception("Failed to start host: $e");
    }
  }

  void _handleNewClient(Socket socket) {
    _clientSocket = socket;
    _opponentAddress = socket.remoteAddress.address;
    _opponentPort = socket.remotePort;
    _lastConnectionTime = DateTime.now();
    logger.i(
        "$_logTag Accepted client at $_opponentAddress:${socket.remotePort}");

    _messagesSent = 0;
    _messagesReceived = 0;
    _reconnectAttempts = 0;

    onClientConnected?.call(_opponentAddress!, socket.remotePort);
    _notifyConnectionStatusChanged(true);

    _listenToSocket(socket);

    if (isHost && !_heartbeatStarted) {
      _startHeartbeat();
    }
  }

  /// Connect as a client.
  Future<void> connectToHost(String host, int port,
      {int retryCount = _maxReconnectAttempts}) async {
    if (_disposed) {
      throw Exception("NetworkService disposed; cannot connect.");
    }
    isHost = false;
    _reconnectAttempts = 0;

    for (int attempt = 0; attempt < retryCount; attempt++) {
      if (_disposed) {
        break;
      }

      _reconnectAttempts = attempt + 1;
      try {
        logger.i("$_logTag Connecting to $host:$port (attempt ${attempt + 1})");

        final socket = await Socket.connect(host, port)
            .timeout(_connectionTimeout, onTimeout: () {
          throw TimeoutException(
              "Connection timed out after ${_connectionTimeout.inSeconds}s");
        });

        if (_disposed) {
          socket.destroy();
          return;
        }

        _clientSocket = socket;
        _opponentAddress = host;
        _opponentPort = port;
        _lastConnectionTime = DateTime.now();
        logger.i("$_logTag Connected to $host:$port");

        _messagesSent = 0;
        _messagesReceived = 0;
        _notifyConnectionStatusChanged(true);

        _listenToSocket(socket);

        _protocolHandshakeCompleter = Completer<bool>();
        sendMove("protocol:$protocolVersion");

        final success = await _protocolHandshakeCompleter!.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            logger.e("$_logTag Protocol handshake timed out");
            return false;
          },
        );

        if (!success) {
          throw Exception("Protocol handshake failed or mismatched");
        }

        sendMove("request:aiMovesFirst");
        return;
      } catch (e, st) {
        logger.e("$_logTag Connect attempt ${attempt + 1} failed: $e");
        logger.d("$_logTag Stack trace: $st");

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

  Future<bool> attemptReconnect() async {
    if (_disposed ||
        _isReconnecting ||
        isHost ||
        _opponentAddress == null ||
        _opponentPort == null) {
      return false;
    }

    _isReconnecting = true;
    logger
        .i("$_logTag Attempting reconnect to $_opponentAddress:$_opponentPort");

    final BuildContext? currentContext =
        rootScaffoldMessengerKey.currentContext;
    final String attemptingToReconnect = currentContext != null
        ? S.of(currentContext).attemptingToReconnect
        : "Attempting to reconnect...";
    final String reconnectedSuccessfully = currentContext != null
        ? S.of(currentContext).reconnectedSuccessfully
        : "Reconnected successfully";
    final String unableToReconnect = currentContext != null
        ? S.of(currentContext).unableToReconnectPleaseRestartTheGame
        : "Unable to reconnect, please restart the game";
    final localizations = currentContext != null ? S.of(currentContext) : null;

    GameController().headerTipNotifier.showTip(attemptingToReconnect);

    try {
      for (int attempt = 0; attempt < _maxReconnectAttempts; attempt++) {
        if (_disposed) {
          break;
        }
        final String reconnectingMsg = localizations != null
            ? localizations.reconnecting(attempt + 1, _maxReconnectAttempts)
            : "Reconnecting (${attempt + 1}/$_maxReconnectAttempts)";
        GameController().headerTipNotifier.showTip(reconnectingMsg);

        try {
          await connectToHost(_opponentAddress!, _opponentPort!, retryCount: 1);
          _isReconnecting = false;
          GameController().headerTipNotifier.showTip(reconnectedSuccessfully);
          return true;
        } catch (e) {
          if (attempt == _maxReconnectAttempts - 1) {
            continue;
          }
          final waitTime = Duration(seconds: (attempt + 1) * 2);
          await Future.delayed(waitTime);
        }
      }

      throw Exception("Reconnection failed");
    } catch (e) {
      logger.e("$_logTag Reconnection failed: $e");
      _isReconnecting = false;
      GameController().headerTipNotifier.showTip(unableToReconnect);
      return false;
    }
  }

  /// Listens for discovery requests on the selected IP or anyIPv4,
  /// depending on platform capabilities.
  Future<void> _startDiscoveryListener(int serverPort,
      {String? localIpAddress}) async {
    if (_disposed) {
      return;
    }
    try {
      // If the OS is Android/Windows/Linux, we bind to 0.0.0.0:33334 for maximum discovery.
      // If it's iOS (or other restricted platforms), we still bind to the chosen IP address.
      InternetAddress bindAddress;
      if (!kIsWeb) {
        if (Platform.isIOS == false) {
          // Bind to 0.0.0.0 for maximum LAN discovery
          bindAddress = InternetAddress.anyIPv4;
        } else if (Platform.isIOS) {
          // iOS is restricted, so fallback to the specifically chosen IP
          if (localIpAddress == null && _boundIpAddress == null) {
            logger.e("$_logTag No local IP for iOS discovery listener");
            return;
          }
          bindAddress = InternetAddress(localIpAddress ?? _boundIpAddress!);
        } else {
          // If other platform, do what you think is safe or desired
          // Here we just do the old approach by default:
          if (localIpAddress == null && _boundIpAddress == null) {
            logger.e("$_logTag No local IP for discovery listener");
            return;
          }
          bindAddress = InternetAddress(localIpAddress ?? _boundIpAddress!);
        }
      } else {
        // Web platform not supported, or do nothing
        logger.e("$_logTag Web platform does not support RawDatagramSocket.");
        return;
      }

      // Actually bind the discovery socket
      _discoverySocket = await RawDatagramSocket.bind(bindAddress, 33334);
      _discoverySocket!.broadcastEnabled = true;

      logger.i("$_logTag Discovery listener on ${bindAddress.address}:33334");

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

  /// Sends "Sanmill:\<chosenIP>:serverPort" back to the discoverer,
  /// using _boundIpAddress instead of getLocalIpAddress().
  Future<void> _respondToDiscovery(Datagram datagram, int serverPort) async {
    if (_disposed) {
      return;
    }

    final localIp = _boundIpAddress; // Use the bound IP
    if (localIp != null) {
      final reply = 'Sanmill:$localIp:$serverPort';
      final replyData = utf8.encode(reply);
      try {
        _discoverySocket?.send(replyData, datagram.address, datagram.port);
        logger.i("$_logTag Replied discovery with $reply");
      } catch (e) {
        logger.e("$_logTag Failed discovery reply: $e");
      }
    }
  }

  void _listenToSocket(Socket socket) {
    socket
        .cast<List<int>>()
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
          return;
        }

        _messagesReceived++;
        logger.t(
            "$_logTag Received from $_opponentAddress:$remotePort => $trimmed");

        if (trimmed.startsWith("protocol:")) {
          _handleProtocol(trimmed);
          return;
        }
        if (trimmed == "heartbeat") {
          if (!isHost) {
            _lastHeartbeatReceived = DateTime.now();
            _sendMessageInternal("heartbeatAck");
            logger.t("$_logTag [Client] got heartbeat -> ack");
          }
          return;
        }
        if (trimmed == "heartbeatAck") {
          if (isHost) {
            _lastHeartbeatReceived = DateTime.now();
            logger.t("$_logTag [Host] got heartbeatAck");
          }
          return;
        }

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

    socket.done.catchError((error, st) {
      if (!_disposed) {
        logger.e("$_logTag Socket write error on done: $error");
        _handleDisconnection(error: error.toString());
      }
    });
  }

  Future<void> _processMessageQueue() async {
    if (_isProcessingMessages || _disposed) {
      return;
    }
    _isProcessingMessages = true;

    try {
      final timer = Timer(_messageProcessingTimeout * 2, () {
        if (_isProcessingMessages) {
          logger
              .w("$_logTag Message processing timed out, continuing next loop");
          _isProcessingMessages = false;
          if (_messageQueue.isNotEmpty && !_disposed) {
            Future.delayed(Duration.zero, _processMessageQueue);
          }
        }
      });

      int processedCount = 0;
      final startTime = DateTime.now();

      while (_messageQueue.isNotEmpty && !_disposed) {
        final message = _messageQueue.removeFirst();
        _handleNetworkMessage(message);
        processedCount++;

        if (processedCount >= 5 ||
            DateTime.now().difference(startTime).inMilliseconds > 100) {
          await Future<void>.delayed(Duration.zero);
          processedCount = 0;
        }
      }
      timer.cancel();
    } catch (e, st) {
      logger.e("$_logTag Error processing queue: $e");
      logger.d("$_logTag Stack trace: $st");
    } finally {
      _isProcessingMessages = false;
    }
  }

  void _handleProtocol(String line) {
    final parts = line.split(":");
    if (parts.length < 2) {
      logger.w("$_logTag Malformed protocol message: $line");
      return;
    }
    final theirProtocol = parts[1];

    if (isHost) {
      sendMove("protocol:$protocolVersion");
      if (theirProtocol != protocolVersion) {
        final msg =
            "Protocol mismatch: server=$protocolVersion, client=$theirProtocol";
        logger.w("$_logTag $msg");
        onProtocolMismatch?.call(msg);
      }
    } else {
      if (theirProtocol != protocolVersion) {
        final msg =
            "Protocol mismatch: client=$protocolVersion, server=$theirProtocol";
        logger.w("$_logTag $msg");
        onProtocolMismatch?.call(msg);
        _handleDisconnection(reason: "Protocol mismatch");
        _protocolHandshakeCompleter?.complete(false);
      } else {
        logger.i("$_logTag Protocol handshake success");
        _protocolHandshakeCompleter?.complete(true);
      }
    }
  }

  void sendMove(String move) {
    if (_disposed) {
      throw Exception("NetworkService disposed; cannot send.");
    }
    if (move.isEmpty) {
      logger.w("$_logTag Attempted to send empty message");
      return;
    }
    _sendMessageInternal(move);
  }

  void _sendMessageInternal(String message) {
    if (_clientSocket != null && !_clientSocket!.isClosed) {
      try {
        _clientSocket!.write("$message\n");
        _messagesSent++;
        logger.t("$_logTag Sent => $message");
      } catch (e, st) {
        logger.e("$_logTag Error sending: $e");
        logger.d("$_logTag Stack trace: $st");

        if (e is SocketException) {
          if (e.message.contains("Connection reset by peer") ||
              e.message.contains("Broken pipe") ||
              e.message.contains("Software caused connection abort")) {
            logger.w("$_logTag Connection error on send");
            _handleDisconnection(error: "Connection error: ${e.message}");
          } else {
            _handleDisconnection(error: "Send error: ${e.message}");
          }
        } else {
          _handleDisconnection(error: "Send error: $e");
        }
      }
    } else {
      logger.w("$_logTag No valid socket to send data");
      _handleDisconnection(reason: "No active socket");
    }
  }

  void _startHeartbeat() {
    if (_heartbeatStarted || !isHost || _disposed) {
      return;
    }
    _heartbeatStarted = true;
    _lastHeartbeatReceived = DateTime.now();

    int consecutiveFailures = 0;
    const int maxFailures = 3;

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
        consecutiveFailures = 0;
      } catch (e) {
        logger.e("$_logTag Error sending heartbeat: $e");
        consecutiveFailures++;
        if (consecutiveFailures >= maxFailures) {
          if (e.toString().contains("Connection reset by peer")) {
            logger.w("$_logTag Connection reset by peer during heartbeat");
            _handleDisconnection(error: "Connection reset by peer");
          } else {
            _handleDisconnection(error: "Heartbeat send error: $e");
          }
        }
      }
    });

    _heartbeatCheckTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_disposed) {
        return;
      }
      final diff = DateTime.now().difference(_lastHeartbeatReceived);
      if (diff > _heartbeatTimeout && !_disposed) {
        logger.e("$_logTag Heartbeat timeout. Disconnecting...");
        _handleDisconnection(reason: "Heartbeat timeout");
      }
    });
  }

  void _handleNetworkMessage(String message) {
    if (_disposed) {
      return;
    }
    if (message.isEmpty) {
      logger.w("$_logTag Received empty message");
      return;
    }

    try {
      if (message.startsWith("restart:")) {
        final parts = message.split(":");
        if (parts.length < 2) {
          logger.w("$_logTag Malformed restart message: $message");
          return;
        }

        final cmd = parts[1];
        if (cmd == "request") {
          logger.i("$_logTag Opponent requests restart");
          GameController().handleRestartRequest();
        } else if (cmd == "accepted") {
          logger.i("$_logTag Opponent accepted restart");
          GameController().reset(lanRestart: true);
          GameController().headerTipNotifier.showTip("Game restarted");
        } else if (cmd == "rejected") {
          logger.i("$_logTag Opponent rejected restart");
          GameController().headerTipNotifier.showTip("Restart rejected");
        } else {
          logger.w("$_logTag Unknown restart command: $cmd");
        }
        return;
      }

      if (message.startsWith("take back:")) {
        final parts = message.split(':');
        if (parts.length < 3) {
          logger.w("$_logTag Malformed take back message: $message");
          return;
        }
        final stepCountStr = parts[1];
        final command = parts[2];
        final steps = int.tryParse(stepCountStr);
        if (steps == null || steps <= 0) {
          logger.w("$_logTag Invalid steps in take back: $stepCountStr");
          return;
        }

        final context = rootScaffoldMessengerKey.currentContext;
        final String takeBackAccepted = context != null
            ? S.of(context).takeBackAccepted
            : "Take back accepted";
        final String takeBackRejected = context != null
            ? S.of(context).takeBackRejected
            : "Take back rejected";

        if (command == "request") {
          GameController().handleTakeBackRequest(steps);
        } else if (command == "accepted") {
          _performLanTakeBack(steps);
          GameController().pendingTakeBackCompleter?.complete(true);
          GameController().pendingTakeBackCompleter = null;
          GameController().headerTipNotifier.showTip(takeBackAccepted);
        } else if (command == "rejected") {
          GameController().pendingTakeBackCompleter?.complete(false);
          GameController().pendingTakeBackCompleter = null;
          GameController().headerTipNotifier.showTip(takeBackRejected);
        } else {
          logger.w("$_logTag Unknown take back command: $command");
        }
        return;
      }

      if (message.startsWith("resign:")) {
        logger.i("$_logTag Opponent resigned => $message");
        GameController().handleResignation();
        return;
      }

      if (message.startsWith("response:aiMovesFirst:")) {
        final parts = message.split(":");
        if (parts.length < 3) {
          logger.w("$_logTag Malformed aiMovesFirst: $message");
          return;
        }
        final valueStr = parts[2];
        final bool hostAiMovesFirst = valueStr.toLowerCase() == "true";
        _handleAiMovesFirstResponse(hostAiMovesFirst);
        return;
      }

      logger.i("$_logTag Normal game message => $message");
      GameController().handleLanMove(message);
    } catch (e, st) {
      logger.e("$_logTag Error handling message: $e");
      logger.d("$_logTag Stack trace: $st");
    }
  }

  static void _performLanTakeBack(int steps) {
    try {
      HistoryNavigator.doEachMove(HistoryNavMode.takeBack, steps);
      final localColor = GameController().getLocalColor();
      GameController().isLanOpponentTurn =
          GameController().position.sideToMove != localColor;
    } catch (e, st) {
      logger.e("$_logTag Error performing take back: $e");
      logger.d("$_logTag Stack trace: $st");
    }
  }

  void _handleAiMovesFirstResponse(bool hostAiMovesFirst) {
    try {
      final bool clientAiMovesFirst = !hostAiMovesFirst;
      DB().generalSettings =
          DB().generalSettings.copyWith(aiMovesFirst: clientAiMovesFirst);
      logger.i(
          "$_logTag Updated client aiMovesFirst=$clientAiMovesFirst (host=$hostAiMovesFirst)");

      GameController().headerIconsNotifier.showIcons();
      GameController().boardSemanticsNotifier.updateSemantics();
    } catch (e, st) {
      logger.e("$_logTag Error handling AI moves first: $e");
      logger.d("$_logTag Stack trace: $st");
    }
  }

  void _handleDisconnection({String? reason, String? error}) {
    if (_disposed) {
      return;
    }
    final String disconnectReason = error ?? reason ?? "Unknown reason";

    final BuildContext? context = rootScaffoldMessengerKey.currentContext;
    final String disconnectedMsg = context != null
        ? S.of(context).disconnectedFromOpponent
        : "Disconnected from opponent";
    String userFriendlyMessage = disconnectedMsg;

    if (error != null && error.contains("Connection reset by peer")) {
      final String opponentLeftMsg = context != null
          ? S.of(context).theOpponentMayHaveLeftTheGame
          : "Opponent may have left the game";
      userFriendlyMessage = opponentLeftMsg;
    } else if (disconnectReason.contains("timeout")) {
      userFriendlyMessage = context != null
          ? S.of(context).connectionTimedOutNetworkConnectionUnstable
          : "Connection timed out, unstable network";
    } else if (disconnectReason.contains("refused")) {
      userFriendlyMessage = context != null
          ? S.of(context).connectionRefusedTheServerMayBeDown
          : "Connection refused, server may be down";
    }

    final gameOverText = context != null ? S.of(context).gameOver : "Game over";

    logger.i("$_logTag Opponent disconnected: $disconnectReason");

    GameController()
        .headerTipNotifier
        .showTip("$userFriendlyMessage, $gameOverText");

    GameController().isLanOpponentTurn = false;
    if (GameController().position.phase != Phase.gameOver) {
      GameController().position.setGameOver(
            PieceColor.draw,
            GameOverReason.drawStalemateCondition,
          );
      GameController()
          .headerTipNotifier
          .showTip("$userFriendlyMessage, $gameOverText");
    }

    _notifyConnectionStatusChanged(false, info: userFriendlyMessage);
    _disposeInternals();
    onDisconnected?.call();
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    WidgetsBinding.instance.removeObserver(this);
    logger.i("$_logTag dispose() called");
    _disposeInternals();
  }

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
      if (_serverSocket != null) {
        if (_serverSocket!.port > 0) {
          _serverSocket!.close();
        } else {
          logger.w("$_logTag Skipping close of invalid server socket (port=0)");
        }
      }
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

    logger.i("$_logTag Network disposed");
  }

  /// Returns the first non-loopback IPv4 address, or null if not found.
  static Future<String?> getLocalIpAddress() async {
    try {
      if (kIsWeb) {
        return null;
      }

      if (Platform.isAndroid || Platform.isIOS) {
        final info = NetworkInfo();
        final wifiIP = await info.getWifiIP();
        if (wifiIP != null && wifiIP.isNotEmpty) {
          logger.i("$_logTag Using WiFi IP: $wifiIP");
          return wifiIP;
        }
        logger.w("$_logTag No Wi-Fi IP found, fallback to interface scan");
      }

      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);

      // Attempt wifi-like names first
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if ((name.contains('wlan') ||
                name.contains('en0') ||
                name.contains('wifi') ||
                name.contains('wireless')) &&
            iface.addresses.isNotEmpty) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback) {
              logger.i("$_logTag Selected WiFi interface: ${addr.address}");
              return addr.address;
            }
          }
        }
      }

      // Fallback: any non-loopback interface
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            logger.i("$_logTag Selected fallback interface: ${addr.address}");
            return addr.address;
          }
        }
      }
      logger.w("$_logTag No suitable network interface found");
    } catch (e, st) {
      logger.e("$_logTag Error getting local IP: $e");
      logger.d("$_logTag Stack: $st");
    }
    return null;
  }

  /// Returns all non-loopback IPv4 addresses, giving the user a chance to pick one.
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
          logger.i("$_logTag Added mobile WiFi IP: $wifiIP");
          return result;
        }
        logger.w("$_logTag No Wi-Fi IP found, scanning interfaces");
      }

      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);

      // Gather WiFi-like interfaces first
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.contains('wlan') ||
            name.contains('en0') ||
            name.contains('wifi') ||
            name.contains('wireless')) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback) {
              result.add(addr.address);
              logger.i(
                  "$_logTag Found WiFi interface ${iface.name}: ${addr.address}");
            }
          }
        }
      }

      // Then add other non-loopbacks
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (!name.contains('lo') &&
            !name.contains('wlan') &&
            !name.contains('en0') &&
            !name.contains('wifi') &&
            !name.contains('wireless')) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback && !result.contains(addr.address)) {
              result.add(addr.address);
              logger
                  .i("$_logTag Found interface ${iface.name}: ${addr.address}");
            }
          }
        }
      }
    } catch (e, st) {
      logger.e("$_logTag Error listing local IPs: $e");
      logger.d("$_logTag Stack: $st");
    }
    return result;
  }

  /// Use the user-chosen IP to bind the local socket (for broadcast).
  /// If localIpAddress is passed, do not call getLocalIpAddress().
  static Future<String?> discoverHost({
    Duration timeout = const Duration(seconds: 10),
    String? localIpAddress,
  }) async {
    final completer = Completer<String?>();
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    Timer? timeoutTimer;

    try {
      // Prefer user-specified IP
      final String? localIp = localIpAddress ?? await getLocalIpAddress();
      if (localIp == null) {
        logger.e("[Network] No local IP to discover host");
        return null;
      }

      final localAddr = InternetAddress(localIp);
      socket = await RawDatagramSocket.bind(localAddr, 0);
      socket.broadcastEnabled = true;
      logger.i("[Network] Discovery bound to $localIp (port ${socket.port})");

      timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          logger.i(
              "[Network] Host discovery timed out after ${timeout.inSeconds}s");
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
                    logger.i("[Network] Found host: $result");
                    completer.complete(result);
                  }
                } else {
                  logger.w("[Network] Malformed discovery response: $msg");
                }
              }
            } catch (e) {
              logger.e("[Network] Error decoding discovery response: $e");
            }
          }
        }
      }, onError: (error, st) {
        logger.e("[Network] Discovery socket error: $error");
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      });

      // Compute broadcast address from the chosen IP
      final broadcastAddrString = _computeBroadcastAddress(localIp);
      final broadcastAddr = InternetAddress(broadcastAddrString);
      logger.i(
          "[Network] Using broadcast address for discovery: $broadcastAddrString");

      // Send the "Discovery?" message a few times
      for (int i = 0; i < 3; i++) {
        if (completer.isCompleted) {
          break;
        }

        try {
          socket.send(
            utf8.encode('Discovery?'),
            broadcastAddr,
            33334,
          );
          logger.d(
              "[Network] Sent discovery broadcast to $broadcastAddrString (attempt ${i + 1})");
          await Future.delayed(const Duration(seconds: 1));
        } catch (e) {
          logger.e("[Network] Error sending discovery broadcast: $e");
        }
      }

      return await completer.future;
    } catch (e) {
      logger.e("[Network] discoverHost error: $e");
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

  /// Simple method to compute broadcast by replacing the last octet with '255'.
  /// This removes any fallback to 255.255.255.255.
  static String _computeBroadcastAddress(String localIp) {
    final parts = localIp.split('.');
    if (parts.length == 4) {
      parts[3] = '255';
      return parts.join('.');
    }
    // If not IPv4, just return the original IP (no fallback to 255.255.255.255).
    return localIp;
  }

  void _notifyConnectionStatusChanged(bool isConnected, {String? info}) {
    onConnectionStatusChanged?.call(isConnected);

    final BuildContext? context = rootScaffoldMessengerKey.currentContext;
    final String msg =
        info ?? (context != null ? S.of(context).connected : "Connected");

    if (isConnected) {
      GameController().headerTipNotifier.showTip(msg);
    } else if (info != null) {
      GameController().headerTipNotifier.showTip(info);
    }

    GameController().headerIconsNotifier.showIcons();
  }
}

extension SocketExtension on Socket {
  bool get isClosed {
    try {
      return remotePort == 0;
    } catch (_) {
      return true;
    }
  }
}
