// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'online_proxy_settings.dart';
import 'online_proxy_transport_base.dart';

const bool onlineProxySupported = true;

http.Client createOnlineHttpClient(OnlineProxySettings settings) {
  final HttpClient client = HttpClient();
  _configureProxy(client, settings);
  return IOClient(client);
}

OnlineWebSocketTransport createOnlineWebSocketTransport(
  OnlineProxySettings settings,
) => _IoOnlineWebSocketTransport(settings);

void _configureProxy(HttpClient client, OnlineProxySettings settings) {
  if (settings.enabled) {
    client.findProxy = (Uri _) => settings.proxyDirective;
  }
}

class _IoOnlineWebSocketTransport implements OnlineWebSocketTransport {
  _IoOnlineWebSocketTransport(OnlineProxySettings settings)
    : _client = HttpClient() {
    _configureProxy(_client, settings);
  }

  final HttpClient _client;
  bool _closed = false;

  @override
  WebSocketChannel connect(Uri uri) {
    if (_closed) {
      throw StateError('Online WebSocket transport is closed.');
    }
    return IOWebSocketChannel.connect(
      uri,
      customClient: _client,
      connectTimeout: const Duration(seconds: 15),
    );
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _client.close(force: true);
  }
}
