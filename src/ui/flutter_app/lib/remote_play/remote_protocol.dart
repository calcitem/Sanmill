// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

abstract final class RemoteProtocolConstants {
  static const int version = 2;
  static const String lanVersion = '2.0';
  static const int maxFrameBytes = 64 * 1024;
  static const int lengthPrefixBytes = 4;
  static const int fallbackBlePayloadBytes = 20;
}

enum RemoteMessageType {
  hello,
  helloAccepted,
  helloRejected,
  busy,
  matchConfig,
  ready,
  actionRequest,
  actionCommitted,
  actionRejected,
  snapshotRequest,
  snapshot,
  takeBackRequest,
  takeBackResponse,
  restartRequest,
  restartResponse,
  resign,
  ping,
  pong,
  disconnect,
}

@immutable
class RemoteEnvelope {
  const RemoteEnvelope({
    required this.type,
    required this.sessionId,
    required this.roundId,
    required this.messageId,
    required this.revision,
    required this.payload,
    this.version = RemoteProtocolConstants.version,
  });

  factory RemoteEnvelope.fromJson(Map<String, Object?> json) {
    const Set<String> fields = <String>{
      'version',
      'type',
      'sessionId',
      'roundId',
      'messageId',
      'revision',
      'payload',
    };
    if (json.keys.any((String key) => !fields.contains(key)) ||
        json.length != fields.length) {
      throw const RemoteProtocolException(
        RemoteProtocolError.invalidEnvelope,
        'Envelope fields do not match the v2 schema.',
      );
    }

    final Object? rawVersion = json['version'];
    if (rawVersion is! int || rawVersion != RemoteProtocolConstants.version) {
      throw RemoteProtocolException(
        RemoteProtocolError.unsupportedVersion,
        'Unsupported protocol version: $rawVersion.',
      );
    }

    final Object? rawType = json['type'];
    if (rawType is! String) {
      throw const RemoteProtocolException(
        RemoteProtocolError.invalidEnvelope,
        'Message type must be a string.',
      );
    }
    final RemoteMessageType type;
    try {
      type = RemoteMessageType.values.byName(rawType);
    } on ArgumentError {
      throw RemoteProtocolException(
        RemoteProtocolError.unknownMessageType,
        'Unknown message type: $rawType.',
      );
    }

    final Object? rawPayload = json['payload'];
    if (rawPayload is! Map) {
      throw const RemoteProtocolException(
        RemoteProtocolError.invalidEnvelope,
        'Message payload must be an object.',
      );
    }

    return RemoteEnvelope(
      version: rawVersion,
      type: type,
      sessionId: _stringField(json, 'sessionId', allowEmpty: true),
      roundId: _stringField(json, 'roundId', allowEmpty: true),
      messageId: _stringField(json, 'messageId'),
      revision: _revisionField(json),
      payload: rawPayload.map<String, Object?>((Object? key, Object? value) {
        if (key is! String) {
          throw const RemoteProtocolException(
            RemoteProtocolError.invalidEnvelope,
            'Payload keys must be strings.',
          );
        }
        return MapEntry<String, Object?>(key, value);
      }),
    );
  }

  final int version;
  final RemoteMessageType type;
  final String sessionId;
  final String roundId;
  final String messageId;
  final int revision;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'type': type.name,
    'sessionId': sessionId,
    'roundId': roundId,
    'messageId': messageId,
    'revision': revision,
    'payload': payload,
  };
}

enum RemoteProtocolError {
  invalidLength,
  frameTooLarge,
  invalidUtf8,
  invalidJson,
  invalidEnvelope,
  unsupportedVersion,
  unknownMessageType,
}

class RemoteProtocolException implements Exception {
  const RemoteProtocolException(this.code, this.message);

  final RemoteProtocolError code;
  final String message;

  @override
  String toString() => 'RemoteProtocolException(${code.name}): $message';
}

abstract final class RemoteFrameCodec {
  static Uint8List encode(RemoteEnvelope envelope) {
    final Uint8List body = Uint8List.fromList(
      utf8.encode(jsonEncode(envelope.toJson())),
    );
    if (body.isEmpty) {
      throw const RemoteProtocolException(
        RemoteProtocolError.invalidLength,
        'A frame body cannot be empty.',
      );
    }
    if (body.length > RemoteProtocolConstants.maxFrameBytes) {
      throw RemoteProtocolException(
        RemoteProtocolError.frameTooLarge,
        'Frame has ${body.length} bytes.',
      );
    }
    final ByteData prefix = ByteData(RemoteProtocolConstants.lengthPrefixBytes)
      ..setUint32(0, body.length, Endian.big);
    return Uint8List.fromList(<int>[...prefix.buffer.asUint8List(), ...body]);
  }

  static RemoteEnvelope decodeBody(Uint8List body) {
    if (body.isEmpty) {
      throw const RemoteProtocolException(
        RemoteProtocolError.invalidLength,
        'A frame body cannot be empty.',
      );
    }
    if (body.length > RemoteProtocolConstants.maxFrameBytes) {
      throw RemoteProtocolException(
        RemoteProtocolError.frameTooLarge,
        'Frame has ${body.length} bytes.',
      );
    }

    final String source;
    try {
      source = utf8.decode(body, allowMalformed: false);
    } on FormatException {
      throw const RemoteProtocolException(
        RemoteProtocolError.invalidUtf8,
        'Frame is not valid UTF-8.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const RemoteProtocolException(
        RemoteProtocolError.invalidJson,
        'Frame is not valid JSON.',
      );
    }
    if (decoded is! Map) {
      throw const RemoteProtocolException(
        RemoteProtocolError.invalidEnvelope,
        'Frame root must be an object.',
      );
    }
    final Map<String, Object?> json = decoded.map<String, Object?>((
      Object? key,
      Object? value,
    ) {
      if (key is! String) {
        throw const RemoteProtocolException(
          RemoteProtocolError.invalidEnvelope,
          'Envelope keys must be strings.',
        );
      }
      return MapEntry<String, Object?>(key, value);
    });
    return RemoteEnvelope.fromJson(json);
  }
}

/// Stateful decoder for a TCP stream or a reassembled BLE byte stream.
class RemoteFrameDecoder {
  final BytesBuilder _prefix = BytesBuilder(copy: false);
  final BytesBuilder _body = BytesBuilder(copy: false);
  int? _expectedBodyLength;

  int get pendingBytes => _expectedBodyLength == null
      ? _prefix.length
      : RemoteProtocolConstants.lengthPrefixBytes + _body.length;

  List<RemoteEnvelope> add(List<int> bytes) {
    if (bytes.isEmpty) {
      return const <RemoteEnvelope>[];
    }
    final Uint8List input = bytes is Uint8List
        ? bytes
        : Uint8List.fromList(bytes);
    final List<RemoteEnvelope> frames = <RemoteEnvelope>[];
    int offset = 0;

    while (offset < input.length) {
      if (_expectedBodyLength == null) {
        final int missingPrefixBytes =
            RemoteProtocolConstants.lengthPrefixBytes - _prefix.length;
        final int prefixBytes = _boundedTake(
          missingPrefixBytes,
          input.length - offset,
        );
        _prefix.add(Uint8List.sublistView(input, offset, offset + prefixBytes));
        offset += prefixBytes;
        if (_prefix.length < RemoteProtocolConstants.lengthPrefixBytes) {
          break;
        }
        final Uint8List prefix = _prefix.takeBytes();
        final int bodyLength = ByteData.sublistView(
          prefix,
        ).getUint32(0, Endian.big);
        if (bodyLength <= 0) {
          reset();
          throw const RemoteProtocolException(
            RemoteProtocolError.invalidLength,
            'Frame length must be positive.',
          );
        }
        if (bodyLength > RemoteProtocolConstants.maxFrameBytes) {
          reset();
          throw RemoteProtocolException(
            RemoteProtocolError.frameTooLarge,
            'Advertised frame length is $bodyLength bytes.',
          );
        }
        _expectedBodyLength = bodyLength;
      }

      final int expectedBodyLength = _expectedBodyLength!;
      final int missingBodyBytes = expectedBodyLength - _body.length;
      final int bodyBytes = _boundedTake(
        missingBodyBytes,
        input.length - offset,
      );
      _body.add(Uint8List.sublistView(input, offset, offset + bodyBytes));
      offset += bodyBytes;
      if (_body.length < expectedBodyLength) {
        break;
      }
      final Uint8List body = _body.takeBytes();
      _expectedBodyLength = null;
      try {
        frames.add(RemoteFrameCodec.decodeBody(body));
      } on Object {
        reset();
        rethrow;
      }
    }

    return frames;
  }

  void reset() {
    _prefix.takeBytes();
    _body.takeBytes();
    _expectedBodyLength = null;
  }

  static int _boundedTake(int needed, int available) =>
      needed < available ? needed : available;
}

abstract final class RemoteFrameChunker {
  static List<Uint8List> split(Uint8List frame, {required int maxPayload}) {
    if (maxPayload <= 0) {
      throw ArgumentError.value(maxPayload, 'maxPayload', 'Must be positive.');
    }
    if (frame.isEmpty) {
      return const <Uint8List>[];
    }
    final List<Uint8List> chunks = <Uint8List>[];
    for (int offset = 0; offset < frame.length; offset += maxPayload) {
      final int end = (offset + maxPayload).clamp(0, frame.length);
      chunks.add(Uint8List.sublistView(frame, offset, end));
    }
    return chunks;
  }
}

String _stringField(
  Map<String, Object?> json,
  String key, {
  bool allowEmpty = false,
}) {
  final Object? value = json[key];
  if (value is! String || (!allowEmpty && value.isEmpty)) {
    throw RemoteProtocolException(
      RemoteProtocolError.invalidEnvelope,
      '$key must be ${allowEmpty ? 'a string' : 'a non-empty string'}.',
    );
  }
  return value;
}

int _revisionField(Map<String, Object?> json) {
  final Object? value = json['revision'];
  if (value is! int || value < 0) {
    throw const RemoteProtocolException(
      RemoteProtocolError.invalidEnvelope,
      'revision must be a non-negative integer.',
    );
  }
  return value;
}
