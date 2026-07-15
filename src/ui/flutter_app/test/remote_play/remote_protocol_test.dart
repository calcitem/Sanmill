// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/remote_play/remote_protocol.dart';

void main() {
  RemoteEnvelope envelope({
    RemoteMessageType type = RemoteMessageType.actionRequest,
    String messageId = 'message-1',
    int revision = 7,
  }) {
    return RemoteEnvelope(
      type: type,
      sessionId: 'session-1',
      roundId: 'round-1',
      messageId: messageId,
      revision: revision,
      payload: const <String, Object?>{'action': 'd6'},
    );
  }

  group('RemoteFrameCodec', () {
    test('round-trips a strict envelope', () {
      final Uint8List bytes = RemoteFrameCodec.encode(envelope());
      final RemoteFrameDecoder decoder = RemoteFrameDecoder();

      final List<RemoteEnvelope> decoded = decoder.add(bytes);

      expect(decoded, hasLength(1));
      expect(decoded.single.type, RemoteMessageType.actionRequest);
      expect(decoded.single.messageId, 'message-1');
      expect(decoded.single.revision, 7);
      expect(decoded.single.payload['action'], 'd6');
      expect(decoder.pendingBytes, 0);
    });

    test('accepts every possible two-part split', () {
      final Uint8List bytes = RemoteFrameCodec.encode(envelope());
      for (int split = 1; split < bytes.length; split++) {
        final RemoteFrameDecoder decoder = RemoteFrameDecoder();
        expect(decoder.add(bytes.sublist(0, split)), isEmpty);
        final List<RemoteEnvelope> decoded = decoder.add(bytes.sublist(split));
        expect(decoded, hasLength(1), reason: 'split=$split');
        expect(decoded.single.messageId, 'message-1');
      }
    });

    test('decodes coalesced frames', () {
      final Uint8List first = RemoteFrameCodec.encode(envelope());
      final Uint8List second = RemoteFrameCodec.encode(
        envelope(messageId: 'message-2', revision: 8),
      );
      final RemoteFrameDecoder decoder = RemoteFrameDecoder();

      final List<RemoteEnvelope> decoded = decoder.add(<int>[
        ...first,
        ...second,
      ]);

      expect(decoded.map((RemoteEnvelope value) => value.messageId), <String>[
        'message-1',
        'message-2',
      ]);
    });

    test('survives random 1-20 byte fragmentation across many frames', () {
      final List<Uint8List> encoded = List<Uint8List>.generate(
        40,
        (int index) => RemoteFrameCodec.encode(
          envelope(messageId: 'random-$index', revision: index),
        ),
      );
      final Uint8List stream = Uint8List.fromList(
        encoded.expand((Uint8List frame) => frame).toList(growable: false),
      );
      final RemoteFrameDecoder decoder = RemoteFrameDecoder();
      final Random random = Random(20260715);
      final List<RemoteEnvelope> decoded = <RemoteEnvelope>[];
      for (int offset = 0; offset < stream.length;) {
        final int length = min(1 + random.nextInt(20), stream.length - offset);
        decoded.addAll(decoder.add(stream.sublist(offset, offset + length)));
        offset += length;
      }

      expect(decoded, hasLength(encoded.length));
      expect(
        decoded.map((RemoteEnvelope value) => value.messageId),
        List<String>.generate(40, (int index) => 'random-$index'),
      );
      expect(decoder.pendingBytes, 0);
    });

    test('reassembles a large frame from one-byte BLE fragments', () {
      final String snapshotData = List<String>.filled(50000, 'x').join();
      final Uint8List encoded = RemoteFrameCodec.encode(
        RemoteEnvelope(
          type: RemoteMessageType.snapshot,
          sessionId: 'session-large',
          roundId: 'round-large',
          messageId: 'large-fragmented-frame',
          revision: 99,
          payload: <String, Object?>{'data': snapshotData},
        ),
      );
      final RemoteFrameDecoder decoder = RemoteFrameDecoder();
      final List<RemoteEnvelope> decoded = <RemoteEnvelope>[];

      for (final int byte in encoded) {
        decoded.addAll(decoder.add(<int>[byte]));
      }

      expect(decoded, hasLength(1));
      expect(decoded.single.payload['data'], snapshotData);
      expect(decoder.pendingBytes, 0);
    });

    test('rejects zero and oversized advertised lengths', () {
      final RemoteFrameDecoder zeroDecoder = RemoteFrameDecoder();
      expect(
        () => zeroDecoder.add(<int>[0, 0, 0, 0]),
        throwsA(
          isA<RemoteProtocolException>().having(
            (RemoteProtocolException e) => e.code,
            'code',
            RemoteProtocolError.invalidLength,
          ),
        ),
      );

      final ByteData oversized = ByteData(4)
        ..setUint32(0, RemoteProtocolConstants.maxFrameBytes + 1, Endian.big);
      final RemoteFrameDecoder oversizedDecoder = RemoteFrameDecoder();
      expect(
        () => oversizedDecoder.add(oversized.buffer.asUint8List()),
        throwsA(
          isA<RemoteProtocolException>().having(
            (RemoteProtocolException e) => e.code,
            'code',
            RemoteProtocolError.frameTooLarge,
          ),
        ),
      );
    });

    test('rejects malformed JSON and unknown fields', () {
      expect(
        () => RemoteFrameCodec.decodeBody(
          Uint8List.fromList(utf8.encode('{broken')),
        ),
        throwsA(
          isA<RemoteProtocolException>().having(
            (RemoteProtocolException e) => e.code,
            'code',
            RemoteProtocolError.invalidJson,
          ),
        ),
      );

      final Map<String, Object?> json = envelope().toJson()
        ..['unexpected'] = true;
      expect(
        () => RemoteFrameCodec.decodeBody(
          Uint8List.fromList(utf8.encode(jsonEncode(json))),
        ),
        throwsA(
          isA<RemoteProtocolException>().having(
            (RemoteProtocolException e) => e.code,
            'code',
            RemoteProtocolError.invalidEnvelope,
          ),
        ),
      );
    });

    test('rejects malformed UTF-8, versions, types, and revisions', () {
      expect(
        () => RemoteFrameCodec.decodeBody(Uint8List.fromList(<int>[0xFF])),
        throwsA(
          isA<RemoteProtocolException>().having(
            (RemoteProtocolException e) => e.code,
            'code',
            RemoteProtocolError.invalidUtf8,
          ),
        ),
      );

      final Map<String, Object?> wrongVersion = envelope().toJson()
        ..['version'] = 1;
      final Map<String, Object?> wrongType = envelope().toJson()
        ..['type'] = 'move';
      final Map<String, Object?> wrongRevision = envelope().toJson()
        ..['revision'] = -1;
      for (final (Map<String, Object?>, RemoteProtocolError) value
          in <(Map<String, Object?>, RemoteProtocolError)>[
            (wrongVersion, RemoteProtocolError.unsupportedVersion),
            (wrongType, RemoteProtocolError.unknownMessageType),
            (wrongRevision, RemoteProtocolError.invalidEnvelope),
          ]) {
        expect(
          () => RemoteFrameCodec.decodeBody(
            Uint8List.fromList(utf8.encode(jsonEncode(value.$1))),
          ),
          throwsA(
            isA<RemoteProtocolException>().having(
              (RemoteProtocolException e) => e.code,
              'code',
              value.$2,
            ),
          ),
        );
      }
    });

    test('rejects an encoded payload larger than 64 KiB', () {
      final RemoteEnvelope oversized = RemoteEnvelope(
        type: RemoteMessageType.snapshot,
        sessionId: 'session',
        roundId: 'round',
        messageId: 'oversized',
        revision: 0,
        payload: <String, Object?>{
          'data': List<String>.filled(
            RemoteProtocolConstants.maxFrameBytes,
            'x',
          ).join(),
        },
      );

      expect(
        () => RemoteFrameCodec.encode(oversized),
        throwsA(
          isA<RemoteProtocolException>().having(
            (RemoteProtocolException e) => e.code,
            'code',
            RemoteProtocolError.frameTooLarge,
          ),
        ),
      );
    });
  });

  group('RemoteFrameChunker', () {
    test('uses safe fixed-size chunks and preserves bytes', () {
      final Uint8List source = Uint8List.fromList(
        List<int>.generate(53, (int index) => index),
      );

      final List<Uint8List> chunks = RemoteFrameChunker.split(
        source,
        maxPayload: 20,
      );

      expect(chunks.map((Uint8List value) => value.length), <int>[20, 20, 13]);
      expect(chunks.expand((Uint8List value) => value), source);
    });
  });
}
