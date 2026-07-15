// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../shared/services/logger.dart';
import 'remote_models.dart';

class RemoteDiagnostics {
  int bytesSent = 0;
  int bytesReceived = 0;
  int framesSent = 0;
  int framesReceived = 0;
  int duplicateMessages = 0;
  int rejectedMessages = 0;
  int resyncRequests = 0;
  int resynchronizations = 0;
  int reconnectAttempts = 0;
  int lastRevision = 0;
  DateTime? connectedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'bytesSent': bytesSent,
    'bytesReceived': bytesReceived,
    'framesSent': framesSent,
    'framesReceived': framesReceived,
    'duplicateMessages': duplicateMessages,
    'rejectedMessages': rejectedMessages,
    'resyncRequests': resyncRequests,
    'resynchronizations': resynchronizations,
    'reconnectAttempts': reconnectAttempts,
    'lastRevision': lastRevision,
    'connectedAt': connectedAt?.toIso8601String(),
  };
}

/// Adds stable, grep-friendly context to every remote-play log line.
class RemoteLogContext {
  RemoteLogContext({required this.transport, required this.role});

  final RemoteTransportKind transport;
  final RemoteRole role;

  String sessionId = '';
  String roundId = '';
  String peerId = '';
  RemoteConnectionState state = RemoteConnectionState.idle;

  String get prefix {
    final String transportLabel = switch (transport) {
      RemoteTransportKind.lan => 'LAN',
      RemoteTransportKind.bluetooth => 'BLE',
    };
    return '[Remote][$transportLabel][${role.name}]'
        '[${shortId(sessionId)}][${shortId(roundId)}][${state.name}]';
  }

  String get _peerDetails => peerId.isEmpty ? '' : 'peer=${shortId(peerId)} ';

  void trace(String eventCode, String details) {
    logger.t('$prefix $eventCode $_peerDetails$details');
  }

  void debug(String eventCode, String details) {
    logger.d('$prefix $eventCode $_peerDetails$details');
  }

  void info(String eventCode, String details) {
    logger.i('$prefix $eventCode $_peerDetails$details');
  }

  void warning(String eventCode, String details) {
    logger.w('$prefix $eventCode $_peerDetails$details');
  }

  void error(String eventCode, Object error, [StackTrace? stackTrace]) {
    logger.e(
      '$prefix $eventCode $_peerDetails$error',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static String shortId(String value) {
    if (value.isEmpty) {
      return '-';
    }
    return value.length <= 8 ? value : value.substring(0, 8);
  }

  /// A non-reversible identifier suitable for logging a resume token.
  static String secretDigest(String secret) {
    if (secret.isEmpty) {
      return '-';
    }
    return sha256.convert(utf8.encode(secret)).toString().substring(0, 8);
  }
}
