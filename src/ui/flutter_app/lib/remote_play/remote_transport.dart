// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'remote_models.dart';

@immutable
class RemoteEndpoint {
  const RemoteEndpoint({
    required this.id,
    required this.label,
    this.address,
    this.port,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String label;
  final String? address;
  final int? port;
  final Map<String, Object?> metadata;
}

@immutable
class RemoteHostOptions {
  const RemoteHostOptions({
    this.bindAddress,
    this.port = 33333,
    this.advertisedLabel = 'Sanmill',
  });

  final String? bindAddress;
  final int port;
  final String advertisedLabel;
}

sealed class RemoteTransportEvent {
  const RemoteTransportEvent();
}

class RemoteTransportStateChanged extends RemoteTransportEvent {
  const RemoteTransportStateChanged(this.state);

  final RemoteConnectionState state;
}

class RemoteTransportConnected extends RemoteTransportEvent {
  const RemoteTransportConnected(this.endpoint);

  final RemoteEndpoint endpoint;
}

class RemoteTransportData extends RemoteTransportEvent {
  const RemoteTransportData(this.bytes);

  final Uint8List bytes;
}

class RemoteTransportDisconnected extends RemoteTransportEvent {
  const RemoteTransportDisconnected({
    required this.reason,
    this.expected = false,
  });

  final String reason;
  final bool expected;
}

class RemoteTransportProtocolMismatch extends RemoteTransportEvent {
  const RemoteTransportProtocolMismatch({required this.peerVersion});

  final String peerVersion;
}

class RemoteTransportFailure extends RemoteTransportEvent {
  const RemoteTransportFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

abstract interface class RemoteTransport {
  RemoteTransportKind get kind;

  RemoteRole get role;

  RemoteConnectionState get state;

  bool get isConnected;

  Stream<RemoteTransportEvent> get events;

  Future<void> startHost(RemoteHostOptions options);

  Future<List<RemoteEndpoint>> discover({
    Duration timeout = const Duration(seconds: 5),
    String? localAddress,
  });

  Future<void> join(RemoteEndpoint endpoint);

  Future<void> reconnect();

  Future<void> send(Uint8List bytes);

  /// Drops only the active peer link while preserving host listeners and
  /// reconnect metadata.
  Future<void> disconnectPeer({required String reason, bool expected = false});

  Future<void> close();
}

/// Optional diagnostics context implemented by production transports.
abstract interface class RemoteTransportLogContextSink {
  void updateLogContext({String? sessionId, String? roundId, String? peerId});
}
