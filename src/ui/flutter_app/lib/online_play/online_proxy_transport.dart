// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:http/http.dart' as http;

import 'online_proxy_settings.dart';
import 'online_proxy_transport_base.dart';
import 'online_proxy_transport_stub.dart'
    if (dart.library.io) 'online_proxy_transport_io.dart'
    as implementation;

export 'online_proxy_transport_base.dart' show OnlineWebSocketTransport;

bool get onlineProxySupported => implementation.onlineProxySupported;

http.Client createOnlineHttpClient(OnlineProxySettings settings) =>
    implementation.createOnlineHttpClient(settings);

OnlineWebSocketTransport createOnlineWebSocketTransport(
  OnlineProxySettings settings,
) => implementation.createOnlineWebSocketTransport(settings);
