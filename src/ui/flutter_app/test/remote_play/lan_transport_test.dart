// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/remote_play/lan_transport.dart';
import 'package:sanmill/remote_play/remote_models.dart';
import 'package:sanmill/remote_play/remote_protocol.dart';
import 'package:sanmill/remote_play/remote_transport.dart';

void main() {
  test('LAN v2 exchanges framed bytes over a real loopback socket', () async {
    final LanTransport host = LanTransport(
      role: RemoteRole.host,
      enableDiscoveryResponder: false,
    );
    final LanTransport client = LanTransport(role: RemoteRole.join);
    addTearDown(host.close);
    addTearDown(client.close);

    final Completer<Uint8List> received = Completer<Uint8List>();
    final StreamSubscription<RemoteTransportEvent> hostEvents = host.events
        .listen((RemoteTransportEvent event) {
          if (event is RemoteTransportData && !received.isCompleted) {
            received.complete(event.bytes);
          }
        });
    addTearDown(hostEvents.cancel);

    await host.startHost(
      const RemoteHostOptions(bindAddress: '127.0.0.1', port: 0),
    );
    final int port = host.serverSocket!.port;
    await client.join(
      RemoteEndpoint(
        id: '127.0.0.1:$port',
        label: 'loopback',
        address: '127.0.0.1',
        port: port,
      ),
    );
    final Uint8List frame = RemoteFrameCodec.encode(
      const RemoteEnvelope(
        type: RemoteMessageType.ping,
        sessionId: 'session',
        roundId: 'round',
        messageId: 'ping-1',
        revision: 0,
        payload: <String, Object?>{},
      ),
    );

    await client.send(frame);

    expect(await received.future.timeout(const Duration(seconds: 2)), frame);
    expect(host.isConnected, isTrue);
    expect(client.isConnected, isTrue);
  });

  test('UDP discovery finds a host through a real loopback socket', () async {
    final LanTransport host = LanTransport(role: RemoteRole.host);
    final LanTransport client = LanTransport(
      role: RemoteRole.join,
      discoveryTargets: const <String>{'127.0.0.1'},
    );
    addTearDown(host.close);
    addTearDown(client.close);

    await host.startHost(
      const RemoteHostOptions(
        bindAddress: '127.0.0.1',
        port: 0,
        advertisedLabel: 'Loopback host',
      ),
    );
    final List<RemoteEndpoint> found = await client.discover(
      timeout: const Duration(milliseconds: 600),
      localAddress: '127.0.0.1',
    );

    expect(found, hasLength(1));
    expect(found.single.address, '127.0.0.1');
    expect(found.single.port, host.serverSocket!.port);
    expect(found.single.label, 'Loopback host');
  });

  test('an extra LAN client receives a framed busy response', () async {
    final LanTransport host = LanTransport(
      role: RemoteRole.host,
      enableDiscoveryResponder: false,
    );
    final LanTransport activeClient = LanTransport(role: RemoteRole.join);
    final LanTransport extraClient = LanTransport(role: RemoteRole.join);
    addTearDown(host.close);
    addTearDown(activeClient.close);
    addTearDown(extraClient.close);

    await host.startHost(
      const RemoteHostOptions(bindAddress: '127.0.0.1', port: 0),
    );
    final RemoteEndpoint endpoint = RemoteEndpoint(
      id: 'loopback',
      label: 'loopback',
      address: '127.0.0.1',
      port: host.serverSocket!.port,
    );
    await activeClient.join(endpoint);
    final Future<RemoteTransportData> busyData = extraClient.events
        .where((RemoteTransportEvent event) => event is RemoteTransportData)
        .cast<RemoteTransportData>()
        .first;

    await extraClient.join(endpoint);
    final RemoteFrameDecoder decoder = RemoteFrameDecoder();
    final List<RemoteEnvelope> frames = decoder.add(
      (await busyData.timeout(const Duration(seconds: 2))).bytes,
    );

    expect(frames, hasLength(1));
    expect(frames.single.type, RemoteMessageType.busy);
    expect(frames.single.payload['reason'], 'activeSession');
    expect(host.isConnected, isTrue);
  });

  test('client reports a legacy LAN protocol version', () async {
    final ServerSocket oldHost = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(oldHost.close);
    final StreamSubscription<Socket> oldHostSubscription = oldHost.listen((
      Socket socket,
    ) {
      socket.listen((Uint8List bytes) {
        socket.write('protocol:1.0\n');
        unawaited(socket.flush());
      });
    });
    addTearDown(oldHostSubscription.cancel);

    final LanTransport client = LanTransport(role: RemoteRole.join);
    addTearDown(client.close);
    final Future<RemoteTransportProtocolMismatch> mismatch = client.events
        .where(
          (RemoteTransportEvent event) =>
              event is RemoteTransportProtocolMismatch,
        )
        .cast<RemoteTransportProtocolMismatch>()
        .first;

    await expectLater(
      client.join(
        RemoteEndpoint(
          id: 'legacy',
          label: 'legacy',
          address: '127.0.0.1',
          port: oldHost.port,
        ),
      ),
      throwsA(isA<RemoteLanVersionMismatchException>()),
    );

    expect(
      (await mismatch.timeout(const Duration(seconds: 2))).peerVersion,
      '1.0',
    );
  });

  test('host reports a legacy LAN protocol version', () async {
    final LanTransport host = LanTransport(
      role: RemoteRole.host,
      enableDiscoveryResponder: false,
    );
    addTearDown(host.close);
    await host.startHost(
      const RemoteHostOptions(bindAddress: '127.0.0.1', port: 0),
    );
    final Future<RemoteTransportProtocolMismatch> mismatch = host.events
        .where(
          (RemoteTransportEvent event) =>
              event is RemoteTransportProtocolMismatch,
        )
        .cast<RemoteTransportProtocolMismatch>()
        .first;
    final Socket oldClient = await Socket.connect(
      InternetAddress.loopbackIPv4,
      host.serverSocket!.port,
    );
    addTearDown(oldClient.destroy);
    oldClient.write('protocol:1.0\n');
    await oldClient.flush();

    expect(
      (await mismatch.timeout(const Duration(seconds: 2))).peerVersion,
      '1.0',
    );
    expect(
      await utf8.decoder
          .bind(oldClient)
          .first
          .timeout(const Duration(seconds: 2)),
      contains('protocol:2.0'),
    );
  });

  test('preserves framed bytes coalesced with the protocol preface', () async {
    final Uint8List frame = RemoteFrameCodec.encode(
      const RemoteEnvelope(
        type: RemoteMessageType.ping,
        sessionId: 'session',
        roundId: 'round',
        messageId: 'coalesced',
        revision: 0,
        payload: <String, Object?>{},
      ),
    );
    final ServerSocket server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(server.close);
    final StreamSubscription<Socket> serverSubscription = server.listen((
      Socket socket,
    ) {
      socket.listen((Uint8List bytes) {
        socket.add(<int>[...('protocol:2.0\n'.codeUnits), ...frame]);
        unawaited(socket.flush());
      });
    });
    addTearDown(serverSubscription.cancel);

    final LanTransport client = LanTransport(role: RemoteRole.join);
    addTearDown(client.close);
    final Future<RemoteTransportData> data = client.events
        .where((RemoteTransportEvent event) => event is RemoteTransportData)
        .cast<RemoteTransportData>()
        .first;
    await client.join(
      RemoteEndpoint(
        id: 'coalesced',
        label: 'coalesced',
        address: '127.0.0.1',
        port: server.port,
      ),
    );

    expect((await data.timeout(const Duration(seconds: 2))).bytes, frame);
  });
}
