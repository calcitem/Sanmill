// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sanmill/online_play/online_proxy_settings.dart';
import 'package:sanmill/online_play/online_proxy_transport.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  late HttpServer proxy;
  late OnlineProxySettings settings;

  setUp(() async {
    proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    settings = OnlineProxySettings.enabled(
      host: proxy.address.address,
      port: proxy.port,
    );
  });

  tearDown(() async {
    await proxy.close(force: true);
  });

  test('HTTP requests use the configured proxy', () async {
    final Completer<Uri> requestedUri = Completer<Uri>();
    proxy.listen((HttpRequest request) async {
      requestedUri.complete(request.uri);
      request.response.write('proxied');
      await request.response.close();
    });
    final http.Client client = createOnlineHttpClient(settings);
    addTearDown(client.close);

    final http.Response response = await client.get(
      Uri.parse('http://unresolvable.invalid/probe'),
    );

    expect(response.body, 'proxied');
    expect((await requestedUri.future).host, 'unresolvable.invalid');
  });

  test('WebSocket traffic uses the configured proxy', () async {
    proxy.listen((HttpRequest request) async {
      expect(request.uri.host, 'unresolvable.invalid');
      final WebSocket socket = await WebSocketTransformer.upgrade(request);
      socket.add('proxied');
      await socket.close();
    });
    final OnlineWebSocketTransport transport = createOnlineWebSocketTransport(
      settings,
    );
    addTearDown(transport.close);
    final WebSocketChannel channel = transport.connect(
      Uri.parse('ws://unresolvable.invalid/socket'),
    );
    addTearDown(channel.sink.close);

    await channel.ready;
    expect(await channel.stream.first, 'proxied');
  });

  test('HTTPS requests establish a CONNECT tunnel through the proxy', () async {
    final Completer<String> method = Completer<String>();
    proxy.listen((HttpRequest request) async {
      method.complete(request.method);
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
    });
    final http.Client client = createOnlineHttpClient(settings);
    addTearDown(client.close);

    await expectLater(
      client
          .get(Uri.parse('https://unresolvable.invalid/probe'))
          .timeout(const Duration(seconds: 5)),
      throwsA(anything),
    );
    expect(await method.future, 'CONNECT');
  });

  test(
    'secure WebSockets establish a CONNECT tunnel through the proxy',
    () async {
      final Completer<String> method = Completer<String>();
      proxy.listen((HttpRequest request) async {
        method.complete(request.method);
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      });
      final OnlineWebSocketTransport transport = createOnlineWebSocketTransport(
        settings,
      );
      addTearDown(transport.close);
      final WebSocketChannel channel = transport.connect(
        Uri.parse('wss://unresolvable.invalid/socket'),
      );

      await expectLater(
        channel.ready.timeout(const Duration(seconds: 5)),
        throwsA(anything),
      );
      expect(await method.future, 'CONNECT');
    },
  );
}
