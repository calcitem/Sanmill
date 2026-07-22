// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'online_proxy_settings.dart';
import 'online_proxy_transport_base.dart';

const bool onlineProxySupported = false;

http.Client createOnlineHttpClient(OnlineProxySettings settings) {
  if (settings.enabled) {
    throw UnsupportedError('Online proxy settings require dart:io.');
  }
  return http.Client();
}

OnlineWebSocketTransport createOnlineWebSocketTransport(
  OnlineProxySettings settings,
) {
  if (settings.enabled) {
    throw UnsupportedError('Online proxy settings require dart:io.');
  }
  return _DefaultOnlineWebSocketTransport();
}

class _DefaultOnlineWebSocketTransport implements OnlineWebSocketTransport {
  bool _closed = false;

  @override
  WebSocketChannel connect(Uri uri) {
    if (_closed) {
      throw StateError('Online WebSocket transport is closed.');
    }
    return WebSocketChannel.connect(uri);
  }

  @override
  void close() {
    _closed = true;
  }
}
