// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:typed_data';

import '../experience_recording/models/user_action_event.dart';
import '../experience_recording/services/diagnostic_action_trail_service.dart';
import '../experience_recording/services/diagnostic_reproduction_service.dart';
import 'bluetooth_adapter.dart';
import 'remote_diagnostics.dart';
import 'remote_models.dart';
import 'remote_protocol.dart';
import 'remote_transport.dart';
import 'universal_ble_adapter.dart';

class BluetoothTransport
    implements RemoteTransport, RemoteTransportLogContextSink {
  BluetoothTransport({required this.role, BluetoothAdapter? adapter})
    : adapter = adapter ?? UniversalBluetoothAdapter(),
      _log = RemoteLogContext(
        transport: RemoteTransportKind.bluetooth,
        role: role,
      );

  static const String serviceId = '68a612c0-966c-41bd-9afd-9d7175a724fc';
  static const String writeCharacteristicId =
      '9d1d4eb7-2f54-4a5c-8f62-846b34231d49';
  static const String notifyCharacteristicId =
      '16024828-8c6d-441d-b629-cc7cf6a4cb35';
  static const int safePayloadLength = 20;
  static const int preferredMtu = 247;

  @override
  final RemoteRole role;
  final BluetoothAdapter adapter;
  final RemoteLogContext _log;
  final StreamController<RemoteTransportEvent> _events =
      StreamController<RemoteTransportEvent>.broadcast(sync: true);

  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  RemoteConnectionState _state = RemoteConnectionState.idle;
  RemoteEndpoint? _lastEndpoint;
  String? _activeDeviceId;
  int _payloadLength = safePayloadLength;
  Future<void> _sendSerial = Future<void>.value();
  bool _closing = false;
  bool _connectedEventSent = false;
  bool _centralConnectionListening = false;
  StreamSubscription<Uint8List>? _notificationSubscription;

  @override
  RemoteTransportKind get kind => RemoteTransportKind.bluetooth;

  @override
  RemoteConnectionState get state => _state;

  @override
  bool get isConnected =>
      _activeDeviceId != null && _connectedEventSent && !_closing;

  @override
  Stream<RemoteTransportEvent> get events => _events.stream;

  bool get supportsHosting => adapter.supportsPeripheralHosting;

  int get payloadLength => _payloadLength;

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
    DiagnosticReplayGuard.requireAllowed('Bluetooth hosting');
    if (role != RemoteRole.host) {
      throw StateError('A join BLE transport cannot host.');
    }
    _assertOpen();
    if (!adapter.supportsPeripheralHosting) {
      throw UnsupportedError('BLE hosting is not supported on this platform.');
    }
    await _ensureReady();
    _listenPeripheralEvents();
    await adapter.preparePeripheral(
      serviceId: serviceId,
      writeCharacteristicId: writeCharacteristicId,
      notifyCharacteristicId: notifyCharacteristicId,
      onWrite: _onPeripheralWrite,
    );
    await adapter.startAdvertising(
      serviceId: serviceId,
      localName: options.advertisedLabel,
    );
    _setState(RemoteConnectionState.listening);
    _log.info(
      'REMOTE_BLE_ADVERTISING_STARTED',
      'service=$serviceId label=${options.advertisedLabel}',
    );
  }

  @override
  Future<List<RemoteEndpoint>> discover({
    Duration timeout = const Duration(seconds: 5),
    String? localAddress,
  }) async {
    DiagnosticReplayGuard.requireAllowed('Bluetooth discovery');
    if (role != RemoteRole.join) {
      throw StateError('Only a join BLE transport can scan.');
    }
    _assertOpen();
    await _ensureReady();
    _setState(RemoteConnectionState.scanning);
    final Map<String, RemoteEndpoint> found = <String, RemoteEndpoint>{};
    final StreamSubscription<BluetoothScanResult> subscription = adapter
        .scanResults
        .listen((BluetoothScanResult result) {
          found[result.deviceId] = RemoteEndpoint(
            id: result.deviceId,
            label: result.name,
            metadata: <String, Object?>{'rssi': result.rssi},
          );
          _log.debug(
            'REMOTE_BLE_SCAN_RESULT',
            'device=${RemoteLogContext.shortId(result.deviceId)} '
                'name=${result.name} rssi=${result.rssi}',
          );
        });
    try {
      await adapter.startScan(serviceId: serviceId);
      _log.info('REMOTE_BLE_SCAN_STARTED', 'service=$serviceId');
      await Future<void>.delayed(timeout);
    } finally {
      try {
        await adapter.stopScan();
      } on Object catch (error, stackTrace) {
        _log.error('REMOTE_BLE_SCAN_STOP_FAILED', error, stackTrace);
      }
      await subscription.cancel();
      if (_state == RemoteConnectionState.scanning) {
        _setState(RemoteConnectionState.idle);
      }
    }
    _log.info('REMOTE_BLE_SCAN_FINISHED', 'count=${found.length}');
    return found.values.toList(growable: false);
  }

  @override
  Future<void> join(RemoteEndpoint endpoint) async {
    DiagnosticReplayGuard.requireAllowed('Bluetooth connections');
    if (role != RemoteRole.join) {
      throw StateError('A host BLE transport cannot join.');
    }
    _assertOpen();
    await _ensureReady();
    _lastEndpoint = endpoint;
    _log.peerId = endpoint.id;
    _connectedEventSent = false;
    _payloadLength = safePayloadLength;
    _setState(RemoteConnectionState.connecting);
    _listenCentralConnectionEvents();
    _log.info(
      'REMOTE_BLE_CONNECT_START',
      'device=${RemoteLogContext.shortId(endpoint.id)}',
    );
    try {
      await adapter.connect(endpoint.id);
      _activeDeviceId = endpoint.id;
      await adapter.subscribe(
        deviceId: endpoint.id,
        serviceId: serviceId,
        characteristicId: notifyCharacteristicId,
      );
      final StreamSubscription<Uint8List> notificationSubscription = adapter
          .notifications(
            deviceId: endpoint.id,
            characteristicId: notifyCharacteristicId,
          )
          .listen(
            (Uint8List bytes) => _onIncomingChunk(endpoint.id, bytes),
            onError: (Object error, StackTrace stackTrace) => _emitFailure(
              'REMOTE_BLE_NOTIFICATION_FAILED',
              error,
              stackTrace,
            ),
          );
      _notificationSubscription = notificationSubscription;
      _subscriptions.add(notificationSubscription);
      try {
        final int mtu = await adapter.requestMtu(endpoint.id, preferredMtu);
        _updatePayloadLength(mtu - 3, source: 'centralMtu');
      } on Object catch (error) {
        _log.warning(
          'REMOTE_BLE_MTU_FALLBACK',
          'device=${RemoteLogContext.shortId(endpoint.id)} '
              'payload=$safePayloadLength error=$error',
        );
      }
      _connectedEventSent = true;
      _setState(RemoteConnectionState.negotiating);
      _events.add(RemoteTransportConnected(endpoint));
      _log.info(
        'REMOTE_BLE_CONNECTED',
        'device=${RemoteLogContext.shortId(endpoint.id)} '
            'payload=$_payloadLength',
      );
    } on Object catch (error, stackTrace) {
      _setState(RemoteConnectionState.error);
      _emitFailure('REMOTE_BLE_CONNECT_FAILED', error, stackTrace);
      await _disconnectActive(expected: true);
      rethrow;
    }
  }

  void _listenCentralConnectionEvents() {
    if (_centralConnectionListening) {
      return;
    }
    _centralConnectionListening = true;
    final StreamSubscription<BluetoothConnectionEvent> subscription = adapter
        .centralConnectionChanges
        .listen((BluetoothConnectionEvent event) {
          if (event.deviceId != _activeDeviceId || event.connected) {
            return;
          }
          _onLinkLost(event.error ?? 'BLE central connection closed.');
        });
    _subscriptions.add(subscription);
  }

  void _listenPeripheralEvents() {
    _subscriptions.add(
      adapter.peripheralConnectionChanges.listen((
        BluetoothConnectionEvent event,
      ) {
        if (event.connected) {
          if (_activeDeviceId != null && _activeDeviceId != event.deviceId) {
            _log.warning(
              'REMOTE_BLE_EXTRA_CLIENT_CONNECTED',
              'active=${RemoteLogContext.shortId(_activeDeviceId!)} '
                  'extra=${RemoteLogContext.shortId(event.deviceId)}',
            );
            return;
          }
          _activeDeviceId ??= event.deviceId;
          _log.peerId = event.deviceId;
          _log.info(
            'REMOTE_BLE_CENTRAL_CONNECTED',
            'device=${RemoteLogContext.shortId(event.deviceId)}',
          );
        } else if (event.deviceId == _activeDeviceId) {
          _onLinkLost('BLE peripheral client disconnected.');
        }
      }),
    );
    _subscriptions.add(
      adapter.peripheralSubscriptionChanges.listen((
        BluetoothSubscriptionEvent event,
      ) async {
        if (event.characteristicId.toLowerCase() !=
            notifyCharacteristicId.toLowerCase()) {
          return;
        }
        if (_activeDeviceId != null && event.deviceId != _activeDeviceId) {
          _log.warning(
            'REMOTE_BLE_EXTRA_CLIENT_SUBSCRIPTION_REJECTED',
            'device=${RemoteLogContext.shortId(event.deviceId)}',
          );
          await _sendBusyToPeripheral(event.deviceId);
          return;
        }
        if (!event.subscribed) {
          if (event.deviceId == _activeDeviceId) {
            _onLinkLost('BLE peer unsubscribed from notifications.');
          }
          return;
        }
        _activeDeviceId = event.deviceId;
        final int? maximum = await adapter.maximumNotifyLength(event.deviceId);
        if (maximum != null) {
          _updatePayloadLength(maximum, source: 'peripheralMaximum');
        }
        if (!_connectedEventSent) {
          _connectedEventSent = true;
          final RemoteEndpoint endpoint = RemoteEndpoint(
            id: event.deviceId,
            label: event.deviceId,
          );
          _lastEndpoint = endpoint;
          _setState(RemoteConnectionState.negotiating);
          _events.add(RemoteTransportConnected(endpoint));
          _log.info(
            'REMOTE_BLE_SUBSCRIBED',
            'device=${RemoteLogContext.shortId(event.deviceId)} '
                'payload=$_payloadLength',
          );
        }
      }),
    );
    _subscriptions.add(
      adapter.peripheralMtuChanges.listen((BluetoothMtuEvent event) {
        if (event.deviceId == _activeDeviceId) {
          _updatePayloadLength(event.mtu - 3, source: 'peripheralMtu');
        }
      }),
    );
  }

  void _onPeripheralWrite(String deviceId, Uint8List bytes) {
    if (deviceId != _activeDeviceId || !_connectedEventSent) {
      _log.warning(
        'REMOTE_BLE_WRITE_REJECTED',
        'device=${RemoteLogContext.shortId(deviceId)} bytes=${bytes.length}',
      );
      return;
    }
    _onIncomingChunk(deviceId, bytes);
  }

  Future<void> _sendBusyToPeripheral(String deviceId) async {
    try {
      final int maximum =
          await adapter.maximumNotifyLength(deviceId) ?? safePayloadLength;
      final Uint8List frame = RemoteFrameCodec.encode(
        RemoteEnvelope(
          type: RemoteMessageType.busy,
          sessionId: '',
          roundId: '',
          messageId: '${DateTime.now().microsecondsSinceEpoch}-$deviceId',
          revision: 0,
          payload: const <String, Object?>{'reason': 'activeSession'},
        ),
      );
      final List<Uint8List> chunks = RemoteFrameChunker.split(
        frame,
        maxPayload: maximum < safePayloadLength ? safePayloadLength : maximum,
      );
      for (final Uint8List chunk in chunks) {
        await adapter.notify(
          deviceId: deviceId,
          characteristicId: notifyCharacteristicId,
          value: chunk,
        );
      }
      _log.info(
        'REMOTE_BLE_BUSY_SENT',
        'device=${RemoteLogContext.shortId(deviceId)} chunks=${chunks.length}',
      );
    } on Object catch (error, stackTrace) {
      _log.error('REMOTE_BLE_BUSY_SEND_FAILED', error, stackTrace);
    }
  }

  void _onIncomingChunk(String deviceId, Uint8List bytes) {
    if (_closing || deviceId != _activeDeviceId || bytes.isEmpty) {
      return;
    }
    _log.trace(
      'REMOTE_BLE_CHUNK_RECEIVED',
      'device=${RemoteLogContext.shortId(deviceId)} bytes=${bytes.length}',
    );
    _events.add(RemoteTransportData(Uint8List.fromList(bytes)));
  }

  @override
  Future<void> reconnect() async {
    _assertOpen();
    _connectedEventSent = false;
    _payloadLength = safePayloadLength;
    if (role == RemoteRole.host) {
      _activeDeviceId = null;
      _setState(RemoteConnectionState.reconnecting);
      return;
    }
    final RemoteEndpoint? endpoint = _lastEndpoint;
    if (endpoint == null) {
      throw StateError('No previous BLE endpoint is available.');
    }
    await _disconnectActive(expected: true);
    await join(endpoint);
  }

  @override
  Future<void> send(Uint8List bytes) {
    DiagnosticReplayGuard.requireAllowed('Bluetooth sending');
    final Completer<void> result = Completer<void>();
    _sendSerial = _sendSerial.then<void>((_) async {
      try {
        await _sendChunks(bytes);
        result.complete();
      } on Object catch (error, stackTrace) {
        _emitFailure('REMOTE_BLE_SEND_FAILED', error, stackTrace);
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<void> _sendChunks(Uint8List bytes) async {
    final String? deviceId = _activeDeviceId;
    if (!isConnected || deviceId == null) {
      throw StateError('BLE peer is not connected.');
    }
    final int chunkCount =
        (bytes.length + _payloadLength - 1) ~/ _payloadLength;
    _log.debug(
      'REMOTE_BLE_FRAME_FRAGMENTED',
      'bytes=${bytes.length} payload=$_payloadLength chunks=$chunkCount',
    );
    for (int offset = 0, index = 0; offset < bytes.length; index++) {
      final int end = (offset + _payloadLength).clamp(0, bytes.length);
      final Uint8List chunk = Uint8List.fromList(bytes.sublist(offset, end));
      if (role == RemoteRole.host) {
        await adapter.notify(
          deviceId: deviceId,
          characteristicId: notifyCharacteristicId,
          value: chunk,
        );
      } else {
        await adapter.write(
          deviceId: deviceId,
          serviceId: serviceId,
          characteristicId: writeCharacteristicId,
          value: chunk,
        );
      }
      _log.trace(
        'REMOTE_BLE_CHUNK_SENT',
        'index=${index + 1}/$chunkCount bytes=${chunk.length}',
      );
      offset = end;
    }
  }

  @override
  Future<void> disconnectPeer({
    required String reason,
    bool expected = false,
  }) async {
    if (_activeDeviceId == null) {
      return;
    }
    _log.warning('REMOTE_BLE_PEER_DROP', 'reason=$reason');
    await _disconnectActive(expected: true);
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

  void _onLinkLost(String reason) {
    if (_closing || _activeDeviceId == null) {
      return;
    }
    _log.warning(
      'REMOTE_BLE_LINK_LOST',
      'device=${RemoteLogContext.shortId(_activeDeviceId!)} reason=$reason',
    );
    _activeDeviceId = null;
    _connectedEventSent = false;
    _payloadLength = safePayloadLength;
    _setState(RemoteConnectionState.reconnecting);
    _events.add(RemoteTransportDisconnected(reason: reason));
  }

  Future<void> _ensureReady() async {
    if (!await adapter.hasPermissions()) {
      _log.info('REMOTE_BLE_PERMISSION_REQUESTED', '');
      await adapter.requestPermissions();
    }
    final BluetoothAvailability availability = await adapter.getAvailability();
    if (availability != BluetoothAvailability.ready) {
      throw BluetoothUnavailableException(availability);
    }
  }

  void _updatePayloadLength(int candidate, {required String source}) {
    final int next = candidate >= safePayloadLength
        ? candidate
        : safePayloadLength;
    if (_payloadLength == next) {
      return;
    }
    final int previous = _payloadLength;
    _payloadLength = next;
    _log.debug(
      'REMOTE_BLE_PAYLOAD_CHANGED',
      'source=$source previous=$previous current=$next',
    );
  }

  Future<void> _disconnectActive({required bool expected}) async {
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    final String? deviceId = _activeDeviceId;
    _activeDeviceId = null;
    _connectedEventSent = false;
    _payloadLength = safePayloadLength;
    if (role == RemoteRole.join && deviceId != null) {
      try {
        await adapter.disconnect(deviceId);
      } on Object catch (error, stackTrace) {
        if (!expected) {
          _log.error('REMOTE_BLE_DISCONNECT_FAILED', error, stackTrace);
        }
      }
    }
  }

  void _setState(RemoteConnectionState next) {
    if (_state == next) {
      return;
    }
    final RemoteConnectionState previous = _state;
    _state = next;
    _log.state = next;
    if (!_events.isClosed) {
      _events.add(RemoteTransportStateChanged(next));
    }
    _log.info(
      'REMOTE_TRANSPORT_STATE_CHANGED',
      'from=${previous.name} to=${next.name}',
    );
    DiagnosticActionTrailService().record(
      actionId: 'remote.state.changed',
      phase: UserActionPhase.success,
      payload: <String, dynamic>{
        'transport': 'bluetooth',
        'fromState': previous.name,
        'toState': next.name,
      },
    );
  }

  void _emitFailure(String code, Object error, StackTrace stackTrace) {
    _log.error(code, error, stackTrace);
    if (!_events.isClosed) {
      _events.add(RemoteTransportFailure(error, stackTrace));
    }
    DiagnosticActionTrailService().record(
      actionId: 'remote.state.changed',
      phase: UserActionPhase.failure,
      payload: <String, dynamic>{
        'transport': 'bluetooth',
        'fromState': _state.name,
        'toState': RemoteConnectionState.error.name,
        'errorCategory': error.runtimeType.toString(),
      },
    );
  }

  void _assertOpen() {
    if (_closing) {
      throw StateError('The BLE transport is closed.');
    }
  }

  @override
  Future<void> close() async {
    if (_closing) {
      return;
    }
    _closing = true;
    _log.info('REMOTE_BLE_CLOSE_START', '');
    await _disconnectActive(expected: true);
    for (final StreamSubscription<Object?> subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    if (role == RemoteRole.host) {
      adapter.clearPeripheralWriteHandler();
      try {
        await adapter.stopAdvertising();
      } on Object catch (error, stackTrace) {
        _log.error('REMOTE_BLE_ADVERTISING_STOP_FAILED', error, stackTrace);
      }
      try {
        await adapter.clearPeripheralServices();
      } on Object catch (error, stackTrace) {
        _log.error('REMOTE_BLE_SERVICE_CLEAR_FAILED', error, stackTrace);
      }
    }
    await adapter.dispose();
    _setState(RemoteConnectionState.ended);
    await _events.close();
    _log.info('REMOTE_BLE_CLOSED', '');
  }
}

class BluetoothUnavailableException implements Exception {
  const BluetoothUnavailableException(this.availability);

  final BluetoothAvailability availability;

  @override
  String toString() => 'Bluetooth is unavailable: ${availability.name}.';
}
