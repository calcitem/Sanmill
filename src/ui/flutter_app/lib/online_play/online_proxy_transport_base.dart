// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:web_socket_channel/web_socket_channel.dart';

abstract interface class OnlineWebSocketTransport {
  WebSocketChannel connect(Uri uri);

  void close();
}
