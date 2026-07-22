// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/online_play/online_proxy_settings.dart';

void main() {
  test('normalizes a proxy and creates the dart:io directive', () {
    final OnlineProxySettings settings = OnlineProxySettings.enabled(
      host: ' Proxy.Example ',
      port: 7890,
    );

    expect(settings.enabled, isTrue);
    expect(settings.host, 'proxy.example');
    expect(settings.authority, 'proxy.example:7890');
    expect(settings.proxyDirective, 'PROXY proxy.example:7890');
  });

  test('supports bracketed IPv6 proxy authorities', () {
    final OnlineProxySettings settings = OnlineProxySettings.parseAuthority(
      '[2001:db8::1]:8080',
    );

    expect(settings.host, '2001:db8::1');
    expect(settings.authority, '[2001:db8::1]:8080');
  });

  test('round trips enabled and disabled settings through JSON', () {
    final OnlineProxySettings enabled = OnlineProxySettings.enabled(
      host: '127.0.0.1',
      port: 7890,
    );

    expect(OnlineProxySettings.fromJson(enabled.toJson()).toJson(), {
      'enabled': true,
      'host': '127.0.0.1',
      'port': 7890,
    });
    final OnlineProxySettings disabled = OnlineProxySettings.fromJson(
      <String, Object?>{
        'enabled': false,
        'host': 'saved.example',
        'port': 8080,
      },
    );
    expect(disabled.enabled, isFalse);
    expect(disabled.host, 'saved.example');
    expect(disabled.port, 8080);
  });

  test('rejects schemes, missing ports, and invalid port ranges', () {
    expect(
      () => OnlineProxySettings.parseAuthority('http://127.0.0.1:7890'),
      throwsFormatException,
    );
    expect(
      () => OnlineProxySettings.parseAuthority('127.0.0.1'),
      throwsFormatException,
    );
    expect(
      () => OnlineProxySettings.enabled(host: '127.0.0.1', port: 65536),
      throwsFormatException,
    );
  });
}
