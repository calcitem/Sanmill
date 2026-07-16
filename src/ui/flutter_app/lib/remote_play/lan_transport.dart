// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:network_info_plus/network_info_plus.dart';

import '../experience_recording/models/user_action_event.dart';
import '../experience_recording/services/diagnostic_action_trail_service.dart';
import '../experience_recording/services/diagnostic_reproduction_service.dart';
import 'remote_diagnostics.dart';
import 'remote_models.dart';
import 'remote_protocol.dart';
import 'remote_transport.dart';

class LanTransport implements RemoteTransport, RemoteTransportLogContextSink {
  LanTransport({
    required this.role,
    this.discoveryTargets,
    this.enableDiscoveryResponder = true,
  }) : _log = RemoteLogContext(transport: RemoteTransportKind.lan, role: role);

  static const int discoveryPort = 33334;
  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _prefaceTimeout = Duration(seconds: 5);
  static const int _maxPrefaceBytes = 64;

  @override
  final RemoteRole role;

  /// Overrides broadcast targets for deterministic loopback tests.
  /// Production callers leave this null to use limited and directed
  /// broadcasts.
  final Set<String>? discoveryTargets;
  final bool enableDiscoveryResponder;

  final RemoteLogContext _log;
  final StreamController<RemoteTransportEvent> _events =
      StreamController<RemoteTransportEvent>.broadcast(sync: true);

  ServerSocket? _serverSocket;
  StreamSubscription<Socket>? _serverSubscription;
  Socket? _socket;
  // Canceled by _closePeerSocket on every link transition and close().
  // ignore: cancel_subscriptions
  StreamSubscription<Uint8List>? _socketSubscription;
  RawDatagramSocket? _discoverySocket;
  StreamSubscription<RawSocketEvent>? _discoverySubscription;
  Timer? _prefaceTimer;
  Completer<void>? _handshakeCompleter;
  RemoteEndpoint? _lastEndpoint;
  RemoteHostOptions? _hostOptions;
  RemoteConnectionState _state = RemoteConnectionState.idle;
  List<int> _prefaceBuffer = <int>[];
  bool _handshakeComplete = false;
  bool _closing = false;
  int _socketGeneration = 0;

  @override
  RemoteTransportKind get kind => RemoteTransportKind.lan;

  @override
  RemoteConnectionState get state => _state;

  @override
  bool get isConnected => _handshakeComplete && _socket != null;

  @override
  Stream<RemoteTransportEvent> get events => _events.stream;

  ServerSocket? get serverSocket => _serverSocket;

  @override
  void updateLogContext({String? sessionId, String? roundId, String? peerId}) {
    if (sessionId != null) {
      _log.sessionId = sessionId;
    }
    if (roundId != null) {
      _log.roundId = roundId;
    }
    if (peerId != null) {
      _log.peerId = peerId;
    }
  }

  @override
  Future<void> startHost(RemoteHostOptions options) async {
    DiagnosticReplayGuard.requireAllowed('LAN hosting');
    if (role != RemoteRole.host) {
      throw StateError('A join transport cannot host.');
    }
    if (_closing) {
      throw StateError('The LAN transport is closed.');
    }
    if (_serverSocket != null) {
      throw StateError('The LAN host is already listening.');
    }

    _hostOptions = options;
    final InternetAddress bindAddress = options.bindAddress == null
        ? InternetAddress.anyIPv4
        : InternetAddress(options.bindAddress!);
    _log.info(
      'REMOTE_LAN_HOST_START',
      'bind=${bindAddress.address} port=${options.port}',
    );
    try {
      _serverSocket = await ServerSocket.bind(bindAddress, options.port);
      _serverSubscription = _serverSocket!.listen(
        _acceptSocket,
        onError: (Object error, StackTrace stackTrace) {
          _emitFailure('REMOTE_LAN_SERVER_ERROR', error, stackTrace);
        },
        onDone: () {
          if (!_closing) {
            _emitFailure(
              'REMOTE_LAN_SERVER_CLOSED',
              StateError('LAN server socket closed unexpectedly.'),
              StackTrace.current,
            );
          }
        },
        cancelOnError: false,
      );
      _setState(RemoteConnectionState.listening);
      if (enableDiscoveryResponder) {
        await _startDiscoveryResponder(options);
      }
      _log.info(
        'REMOTE_LAN_HOST_LISTENING',
        'bound=${_serverSocket!.address.address}:${_serverSocket!.port}',
      );
    } on Object catch (error, stackTrace) {
      _setState(RemoteConnectionState.error);
      _emitFailure('REMOTE_LAN_HOST_FAILED', error, stackTrace);
      await close();
      rethrow;
    }
  }

  void _acceptSocket(Socket candidate) {
    final String address = candidate.remoteAddress.address;
    final int port = candidate.remotePort;
    if (_socket != null) {
      _log.warning('REMOTE_LAN_EXTRA_CLIENT_REJECTED', 'remote=$address:$port');
      unawaited(_sendBusyAndClose(candidate));
      return;
    }
    _log.info(
      'REMOTE_LAN_CLIENT_ACCEPTED',
      'remote=$address:$port awaitingPreface=true',
    );
    _log.peerId = '$address:$port';
    _installSocket(
      candidate,
      RemoteEndpoint(
        id: '$address:$port',
        label: address,
        address: address,
        port: port,
      ),
      sendPreface: false,
    );
  }

  @override
  Future<List<RemoteEndpoint>> discover({
    Duration timeout = const Duration(seconds: 5),
    String? localAddress,
  }) async {
    DiagnosticReplayGuard.requireAllowed('LAN discovery');
    if (role != RemoteRole.join) {
      throw StateError('Only a join transport can discover hosts.');
    }
    if (_closing) {
      throw StateError('The LAN transport is closed.');
    }
    _setState(RemoteConnectionState.scanning);
    final String nonce = _randomHex(16);
    final InternetAddress bindAddress = localAddress == null
        ? InternetAddress.anyIPv4
        : InternetAddress(localAddress);
    final RawDatagramSocket socket = await RawDatagramSocket.bind(
      bindAddress,
      0,
    );
    socket.broadcastEnabled = true;
    final Map<String, RemoteEndpoint> found = <String, RemoteEndpoint>{};
    late final StreamSubscription<RawSocketEvent> subscription;
    subscription = socket.listen(
      (RawSocketEvent event) {
        if (event != RawSocketEvent.read) {
          return;
        }
        Datagram? datagram;
        while ((datagram = socket.receive()) != null) {
          try {
            final Map<String, Object?> response = _decodeDiscovery(
              datagram!.data,
            );
            if (response['kind'] != 'offer' ||
                response['gameId'] != 'mill' ||
                response['nonce'] != nonce ||
                response['version'] != RemoteProtocolConstants.version) {
              continue;
            }
            final Object? rawPort = response['port'];
            if (rawPort is! int || rawPort <= 0 || rawPort > 65535) {
              continue;
            }
            final String address = datagram.address.address;
            final String id = '$address:$rawPort';
            final String label = response['label'] is String
                ? response['label']! as String
                : address;
            found[id] = RemoteEndpoint(
              id: id,
              label: label,
              address: address,
              port: rawPort,
              metadata: <String, Object?>{'sessionId': response['sessionId']},
            );
            _log.info('REMOTE_LAN_DISCOVERY_OFFER', 'remote=$id label=$label');
          } on Object catch (error) {
            _log.warning(
              'REMOTE_LAN_DISCOVERY_INVALID_RESPONSE',
              'remote=${datagram!.address.address} error=$error',
            );
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _log.error('REMOTE_LAN_DISCOVERY_SOCKET_ERROR', error, stackTrace);
      },
    );

    final Uint8List request = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'service': 'sanmill',
          'gameId': 'mill',
          'kind': 'discover',
          'version': RemoteProtocolConstants.version,
          'nonce': nonce,
        }),
      ),
    );
    final Set<String> broadcastAddresses = discoveryTargets == null
        ? <String>{'255.255.255.255'}
        : Set<String>.of(discoveryTargets!);
    if (discoveryTargets == null) {
      try {
        final String? directedBroadcast = await NetworkInfo()
            .getWifiBroadcast();
        if (directedBroadcast != null && directedBroadcast.isNotEmpty) {
          broadcastAddresses.add(directedBroadcast);
        }
      } on Object catch (error) {
        _log.debug(
          'REMOTE_LAN_DISCOVERY_BROADCAST_LOOKUP_FAILED',
          'error=$error',
        );
      }
    }

    _log.info(
      'REMOTE_LAN_DISCOVERY_STARTED',
      'local=${socket.address.address}:${socket.port} targets=$broadcastAddresses',
    );
    try {
      for (int attempt = 1; attempt <= 3; attempt++) {
        for (final String address in broadcastAddresses) {
          try {
            socket.send(request, InternetAddress(address), discoveryPort);
          } on Object catch (error) {
            _log.warning(
              'REMOTE_LAN_DISCOVERY_PROBE_FAILED',
              'target=$address attempt=$attempt error=$error',
            );
          }
        }
        _log.debug(
          'REMOTE_LAN_DISCOVERY_PROBE_SENT',
          'attempt=$attempt bytes=${request.length}',
        );
        if (attempt < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
      await Future<void>.delayed(timeout);
    } finally {
      await subscription.cancel();
      socket.close();
      if (_state == RemoteConnectionState.scanning) {
        _setState(RemoteConnectionState.idle);
      }
    }
    _log.info('REMOTE_LAN_DISCOVERY_FINISHED', 'count=${found.length}');
    return found.values.toList(growable: false);
  }

  @override
  Future<void> join(RemoteEndpoint endpoint) async {
    DiagnosticReplayGuard.requireAllowed('LAN connections');
    if (role != RemoteRole.join) {
      throw StateError('A host transport cannot join another host.');
    }
    final String? address = endpoint.address;
    final int? port = endpoint.port;
    if (address == null || port == null) {
      throw ArgumentError('A LAN endpoint requires an address and port.');
    }
    if (_closing) {
      throw StateError('The LAN transport is closed.');
    }
    _lastEndpoint = endpoint;
    _log.peerId = endpoint.id;
    _setState(RemoteConnectionState.connecting);
    _log.info('REMOTE_LAN_CONNECT_START', 'remote=$address:$port');
    try {
      final Socket socket = await Socket.connect(
        address,
        port,
        timeout: _connectTimeout,
      );
      _installSocket(socket, endpoint, sendPreface: true);
      await _handshakeCompleter!.future.timeout(_prefaceTimeout);
    } on Object catch (error, stackTrace) {
      if (error is! RemoteLanVersionMismatchException) {
        _emitFailure('REMOTE_LAN_CONNECT_FAILED', error, stackTrace);
      }
      await _closePeerSocket(expected: true);
      if (_state != RemoteConnectionState.error) {
        _setState(RemoteConnectionState.error);
      }
      rethrow;
    }
  }

  void _installSocket(
    Socket socket,
    RemoteEndpoint endpoint, {
    required bool sendPreface,
  }) {
    _socketGeneration++;
    final int generation = _socketGeneration;
    _socket = socket;
    _lastEndpoint = endpoint;
    _prefaceBuffer = <int>[];
    _handshakeComplete = false;
    _handshakeCompleter = Completer<void>();
    if (role == RemoteRole.host) {
      _handshakeCompleter!.future.ignore();
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    _prefaceTimer?.cancel();
    _prefaceTimer = Timer(_prefaceTimeout, () {
      if (!_handshakeComplete && generation == _socketGeneration) {
        final TimeoutException error = TimeoutException(
          'LAN protocol preface timed out.',
          _prefaceTimeout,
        );
        _log.warning('REMOTE_LAN_PREFACE_TIMEOUT', 'remote=${endpoint.id}');
        if (!(_handshakeCompleter?.isCompleted ?? true)) {
          _handshakeCompleter!.completeError(error, StackTrace.current);
        }
        unawaited(_closePeerSocket(expected: false));
      }
    });
    _socketSubscription = socket.listen(
      (Uint8List bytes) => _onSocketData(generation, endpoint, bytes),
      onError: (Object error, StackTrace stackTrace) {
        if (generation != _socketGeneration) {
          return;
        }
        _log.error('REMOTE_LAN_SOCKET_ERROR', error, stackTrace);
        if (!(_handshakeCompleter?.isCompleted ?? true)) {
          _handshakeCompleter!.completeError(error, stackTrace);
        }
      },
      onDone: () => _onSocketDone(generation),
      cancelOnError: false,
    );
    if (sendPreface) {
      socket.write('protocol:${RemoteProtocolConstants.lanVersion}\n');
      unawaited(socket.flush());
      _log.debug(
        'REMOTE_LAN_PREFACE_SENT',
        'version=${RemoteProtocolConstants.lanVersion}',
      );
    }
  }

  void _onSocketData(int generation, RemoteEndpoint endpoint, Uint8List bytes) {
    if (generation != _socketGeneration || _closing) {
      return;
    }
    if (_handshakeComplete) {
      _events.add(RemoteTransportData(bytes));
      return;
    }

    _prefaceBuffer.addAll(bytes);
    final int newline = _prefaceBuffer.indexOf(10);
    if (newline < 0) {
      if (_prefaceBuffer.length > _maxPrefaceBytes) {
        const FormatException error = FormatException(
          'LAN protocol preface is too long.',
        );
        _log.warning(
          'REMOTE_LAN_PREFACE_INVALID',
          'bytes=${_prefaceBuffer.length}',
        );
        if (!(_handshakeCompleter?.isCompleted ?? true)) {
          _handshakeCompleter!.completeError(error, StackTrace.current);
        }
        unawaited(_closePeerSocket(expected: false));
      }
      return;
    }

    final String line;
    try {
      line = ascii.decode(_prefaceBuffer.sublist(0, newline)).trim();
    } on FormatException catch (error, stackTrace) {
      if (!(_handshakeCompleter?.isCompleted ?? true)) {
        _handshakeCompleter!.completeError(error, stackTrace);
      }
      unawaited(_closePeerSocket(expected: false));
      return;
    }
    final List<int> remainder = _prefaceBuffer.sublist(newline + 1);
    _prefaceBuffer = <int>[];
    const String prefix = 'protocol:';
    if (!line.startsWith(prefix)) {
      final FormatException error = FormatException(
        'Invalid LAN protocol preface: $line',
      );
      _log.warning('REMOTE_LAN_PREFACE_INVALID', 'line=$line');
      if (!(_handshakeCompleter?.isCompleted ?? true)) {
        _handshakeCompleter!.completeError(error, StackTrace.current);
      }
      unawaited(_closePeerSocket(expected: false));
      return;
    }
    final String peerVersion = line.substring(prefix.length);
    if (role == RemoteRole.host) {
      _socket?.write('protocol:${RemoteProtocolConstants.lanVersion}\n');
      unawaited(_socket?.flush());
    }
    if (peerVersion != RemoteProtocolConstants.lanVersion) {
      final RemoteLanVersionMismatchException error =
          RemoteLanVersionMismatchException(peerVersion);
      _log.warning(
        'REMOTE_LAN_VERSION_MISMATCH',
        'local=${RemoteProtocolConstants.lanVersion} peer=$peerVersion',
      );
      _events.add(RemoteTransportProtocolMismatch(peerVersion: peerVersion));
      if (!(_handshakeCompleter?.isCompleted ?? true)) {
        _handshakeCompleter!.completeError(error, StackTrace.current);
      }
      unawaited(_closePeerSocket(expected: true));
      return;
    }

    _prefaceTimer?.cancel();
    _prefaceTimer = null;
    _handshakeComplete = true;
    _setState(RemoteConnectionState.negotiating);
    _events.add(RemoteTransportConnected(endpoint));
    _log.info(
      'REMOTE_LAN_PREFACE_ACCEPTED',
      'version=$peerVersion remote=${endpoint.id}',
    );
    if (!(_handshakeCompleter?.isCompleted ?? true)) {
      _handshakeCompleter!.complete();
    }
    if (remainder.isNotEmpty) {
      _events.add(RemoteTransportData(Uint8List.fromList(remainder)));
    }
  }

  void _onSocketDone(int generation) {
    if (generation != _socketGeneration) {
      return;
    }
    final bool wasConnected = _handshakeComplete;
    _socket = null;
    _handshakeComplete = false;
    _prefaceTimer?.cancel();
    _prefaceTimer = null;
    if (!(_handshakeCompleter?.isCompleted ?? true)) {
      _handshakeCompleter!.completeError(
        const SocketException('LAN socket closed during protocol handshake.'),
        StackTrace.current,
      );
    }
    if (_closing) {
      return;
    }
    _setState(
      wasConnected
          ? RemoteConnectionState.reconnecting
          : role == RemoteRole.host
          ? RemoteConnectionState.listening
          : RemoteConnectionState.error,
    );
    _events.add(
      RemoteTransportDisconnected(
        reason: wasConnected
            ? 'LAN peer closed the connection.'
            : 'LAN connection closed during handshake.',
      ),
    );
    _log.warning(
      'REMOTE_LAN_SOCKET_CLOSED',
      'wasConnected=$wasConnected serverAlive=${_serverSocket != null}',
    );
  }

  @override
  Future<void> reconnect() async {
    if (_closing) {
      throw StateError('The LAN transport is closed.');
    }
    if (role == RemoteRole.host) {
      if (_serverSocket == null) {
        final RemoteHostOptions? options = _hostOptions;
        if (options == null) {
          throw StateError('No previous LAN host options are available.');
        }
        await startHost(options);
      } else {
        _setState(RemoteConnectionState.reconnecting);
      }
      return;
    }
    final RemoteEndpoint? endpoint = _lastEndpoint;
    if (endpoint == null) {
      throw StateError('No previous LAN endpoint is available.');
    }
    await _closePeerSocket(expected: true);
    await join(endpoint);
  }

  @override
  Future<void> send(Uint8List bytes) async {
    DiagnosticReplayGuard.requireAllowed('LAN sending');
    final Socket? socket = _socket;
    if (!_handshakeComplete || socket == null) {
      throw const SocketException('LAN peer is not connected.');
    }
    socket.add(bytes);
    await socket.flush();
    _log.trace('REMOTE_LAN_BYTES_SENT', 'bytes=${bytes.length}');
  }

  @override
  Future<void> disconnectPeer({
    required String reason,
    bool expected = false,
  }) async {
    if (_socket == null) {
      return;
    }
    _log.warning('REMOTE_LAN_PEER_DROP', 'reason=$reason');
    await _closePeerSocket(expected: true);
    _setState(
      expected && role == RemoteRole.host
          ? RemoteConnectionState.listening
          : expected
          ? RemoteConnectionState.error
          : RemoteConnectionState.reconnecting,
    );
    _events.add(
      RemoteTransportDisconnected(reason: reason, expected: expected),
    );
  }

  Future<void> _startDiscoveryResponder(RemoteHostOptions options) async {
    try {
      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
      );
      _discoverySocket!.broadcastEnabled = true;
      _discoverySubscription = _discoverySocket!.listen(
        (RawSocketEvent event) {
          if (event != RawSocketEvent.read || _closing) {
            return;
          }
          Datagram? datagram;
          while ((datagram = _discoverySocket!.receive()) != null) {
            _respondToDiscovery(datagram!, options);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          _log.error('REMOTE_LAN_DISCOVERY_RESPONDER_ERROR', error, stackTrace);
        },
      );
      _log.info(
        'REMOTE_LAN_DISCOVERY_RESPONDER_STARTED',
        'port=$discoveryPort',
      );
    } on Object catch (error, stackTrace) {
      // Manual IP connection remains available when a platform/firewall does
      // not permit UDP broadcast discovery.
      _log.error('REMOTE_LAN_DISCOVERY_RESPONDER_FAILED', error, stackTrace);
    }
  }

  void _respondToDiscovery(Datagram datagram, RemoteHostOptions options) {
    try {
      final Map<String, Object?> request = _decodeDiscovery(datagram.data);
      if (request['service'] != 'sanmill' ||
          request['gameId'] != 'mill' ||
          request['kind'] != 'discover' ||
          request['version'] != RemoteProtocolConstants.version ||
          request['nonce'] is! String) {
        return;
      }
      final Uint8List response = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'service': 'sanmill',
            'gameId': 'mill',
            'kind': 'offer',
            'version': RemoteProtocolConstants.version,
            'nonce': request['nonce'],
            'port': _serverSocket?.port ?? options.port,
            'label': options.advertisedLabel,
            'sessionId': _log.sessionId,
          }),
        ),
      );
      _discoverySocket!.send(response, datagram.address, datagram.port);
      _log.debug(
        'REMOTE_LAN_DISCOVERY_REPLY_SENT',
        'remote=${datagram.address.address}:${datagram.port}',
      );
    } on Object catch (error) {
      _log.warning(
        'REMOTE_LAN_DISCOVERY_REQUEST_REJECTED',
        'remote=${datagram.address.address} error=$error',
      );
    }
  }

  static Map<String, Object?> _decodeDiscovery(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > 2048) {
      throw const FormatException('Invalid discovery datagram length.');
    }
    final Object? decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('Discovery datagram must be an object.');
    }
    return decoded.map<String, Object?>((Object? key, Object? value) {
      if (key is! String) {
        throw const FormatException('Discovery keys must be strings.');
      }
      return MapEntry<String, Object?>(key, value);
    });
  }

  void _setState(RemoteConnectionState next) {
    if (_state == next) {
      return;
    }
    final RemoteConnectionState previous = _state;
    _state = next;
    _log.state = next;
    _events.add(RemoteTransportStateChanged(next));
    _log.info(
      'REMOTE_TRANSPORT_STATE_CHANGED',
      'from=${previous.name} to=${next.name}',
    );
    DiagnosticActionTrailService().record(
      actionId: 'remote.state.changed',
      phase: UserActionPhase.success,
      payload: <String, dynamic>{
        'transport': 'lan',
        'fromState': previous.name,
        'toState': next.name,
      },
    );
  }

  Future<void> _sendBusyAndClose(Socket candidate) async {
    try {
      final RemoteEnvelope busy = RemoteEnvelope(
        type: RemoteMessageType.busy,
        sessionId: '',
        roundId: '',
        messageId: _randomHex(16),
        revision: 0,
        payload: const <String, Object?>{'reason': 'activeSession'},
      );
      candidate.write('protocol:${RemoteProtocolConstants.lanVersion}\n');
      candidate.add(RemoteFrameCodec.encode(busy));
      await candidate.flush();
      await candidate.close();
      _log.info(
        'REMOTE_LAN_BUSY_SENT',
        'remote=${candidate.remoteAddress.address}:${candidate.remotePort}',
      );
    } on Object catch (error, stackTrace) {
      _log.error('REMOTE_LAN_BUSY_SEND_FAILED', error, stackTrace);
      candidate.destroy();
    }
  }

  void _emitFailure(String eventCode, Object error, StackTrace stackTrace) {
    _log.error(eventCode, error, stackTrace);
    _events.add(RemoteTransportFailure(error, stackTrace));
    DiagnosticActionTrailService().record(
      actionId: 'remote.state.changed',
      phase: UserActionPhase.failure,
      payload: <String, dynamic>{
        'transport': 'lan',
        'fromState': _state.name,
        'toState': RemoteConnectionState.error.name,
        'errorCategory': error.runtimeType.toString(),
      },
    );
  }

  Future<void> _closePeerSocket({required bool expected}) async {
    _socketGeneration++;
    _prefaceTimer?.cancel();
    _prefaceTimer = null;
    final StreamSubscription<Uint8List>? subscription = _socketSubscription;
    _socketSubscription = null;
    await subscription?.cancel();
    final Socket? socket = _socket;
    _socket = null;
    _handshakeComplete = false;
    socket?.destroy();
    if (!expected) {
      _events.add(
        const RemoteTransportDisconnected(
          reason: 'LAN socket closed after a transport failure.',
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    if (_closing) {
      return;
    }
    _closing = true;
    _log.info('REMOTE_LAN_CLOSE_START', '');
    await _closePeerSocket(expected: true);
    await _discoverySubscription?.cancel();
    _discoverySubscription = null;
    _discoverySocket?.close();
    _discoverySocket = null;
    await _serverSocket?.close();
    _serverSocket = null;
    await _serverSubscription?.cancel();
    _serverSubscription = null;
    _setState(RemoteConnectionState.ended);
    await _events.close();
    _log.info('REMOTE_LAN_CLOSED', '');
  }

  static Future<List<String>> getLocalIpAddresses() async {
    final Set<String> addresses = <String>{};
    try {
      final String? wifi = await NetworkInfo().getWifiIP();
      if (wifi != null && _isUsableIpv4(wifi)) {
        addresses.add(wifi);
      }
    } on Object {
      // NetworkInterface.list below is the cross-platform fallback.
    }
    final List<NetworkInterface> interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
      includeLoopback: false,
    );
    for (final NetworkInterface interface in interfaces) {
      for (final InternetAddress address in interface.addresses) {
        if (_isUsableIpv4(address.address)) {
          addresses.add(address.address);
        }
      }
    }
    return addresses.toList(growable: false);
  }

  static bool _isUsableIpv4(String address) {
    return InternetAddress.tryParse(address)?.type ==
            InternetAddressType.IPv4 &&
        !address.startsWith('127.') &&
        !address.startsWith('169.254.');
  }

  static String _randomHex(int bytes) {
    final Random random = Random.secure();
    return List<int>.generate(
      bytes,
      (_) => random.nextInt(256),
      growable: false,
    ).map((int value) => value.toRadixString(16).padLeft(2, '0')).join();
  }
}

class RemoteLanVersionMismatchException implements Exception {
  const RemoteLanVersionMismatchException(this.peerVersion);

  final String peerVersion;

  @override
  String toString() {
    return 'LAN protocol mismatch: local='
        '${RemoteProtocolConstants.lanVersion}, peer=$peerVersion';
  }
}
