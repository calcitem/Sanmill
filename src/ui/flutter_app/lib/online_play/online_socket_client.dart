// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../experience_recording/services/diagnostic_reproduction_service.dart';

sealed class OnlineSocketEvent {
  const OnlineSocketEvent();
}

class OnlineSocketMessage extends OnlineSocketEvent {
  const OnlineSocketMessage(this.json);

  final Map<String, Object?> json;
}

class OnlineSocketClosed extends OnlineSocketEvent {
  const OnlineSocketClosed(this.code, this.reason);

  final int? code;
  final String? reason;
}

class OnlineSocketError extends OnlineSocketEvent {
  const OnlineSocketError(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

abstract interface class OnlineSocketClient {
  Stream<OnlineSocketEvent> get events;

  bool get isConnected;

  Future<void> connect(Uri uri);

  void send(Map<String, Object?> message);

  Future<void> close();
}

class ChannelOnlineSocketClient implements OnlineSocketClient {
  final StreamController<OnlineSocketEvent> _events =
      StreamController<OnlineSocketEvent>.broadcast(sync: true);
  WebSocketChannel? _channel;
  // Canceled by [_closeChannel] and [close].
  // ignore: cancel_subscriptions
  StreamSubscription<Object?>? _subscription;
  bool _connected = false;

  @override
  Stream<OnlineSocketEvent> get events => _events.stream;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect(Uri uri) async {
    DiagnosticReplayGuard.requireAllowed('Online socket connections');
    await _closeChannel();
    final WebSocketChannel channel = WebSocketChannel.connect(uri);
    _channel = channel;
    await channel.ready;
    _connected = true;
    _subscription = channel.stream.listen(
      _onData,
      onError: (Object error, StackTrace stackTrace) {
        _connected = false;
        _events.add(OnlineSocketError(error, stackTrace));
      },
      onDone: () {
        _connected = false;
        _events.add(OnlineSocketClosed(channel.closeCode, channel.closeReason));
      },
      cancelOnError: false,
    );
  }

  void _onData(Object? data) {
    if (data is! String) {
      _events.add(
        OnlineSocketError(
          const FormatException('Online socket message must be text.'),
          StackTrace.current,
        ),
      );
      return;
    }
    try {
      final Object? decoded = jsonDecode(data);
      if (decoded is! Map) {
        throw const FormatException('Online socket message must be an object.');
      }
      _events.add(OnlineSocketMessage(decoded.cast<String, Object?>()));
    } on Object catch (error, stackTrace) {
      _events.add(OnlineSocketError(error, stackTrace));
    }
  }

  @override
  void send(Map<String, Object?> message) {
    DiagnosticReplayGuard.requireAllowed('Online socket sending');
    final WebSocketChannel? channel = _channel;
    if (!_connected || channel == null) {
      throw StateError('Online socket is not connected.');
    }
    channel.sink.add(jsonEncode(message));
  }

  @override
  Future<void> close() async {
    await _closeChannel();
    await _events.close();
  }

  Future<void> _closeChannel() async {
    final StreamSubscription<Object?>? subscription = _subscription;
    final WebSocketChannel? channel = _channel;
    _subscription = null;
    _channel = null;
    _connected = false;
    await subscription?.cancel();
    await channel?.sink.close(1000, 'Client closing');
  }
}
