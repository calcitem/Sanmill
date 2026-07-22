// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class OnlineProxySettings {
  const OnlineProxySettings._({
    required this.enabled,
    required this.host,
    required this.port,
  });

  factory OnlineProxySettings.enabled({
    required String host,
    required int port,
  }) {
    final String normalizedHost = _normalizeHost(host);
    _validatePort(port);
    return OnlineProxySettings._(
      enabled: true,
      host: normalizedHost,
      port: port,
    );
  }

  factory OnlineProxySettings.disabledWithAddress({
    required String host,
    required int port,
  }) {
    _validatePort(port);
    return OnlineProxySettings._(
      enabled: false,
      host: host.trim().isEmpty ? '' : _normalizeHost(host),
      port: port,
    );
  }

  factory OnlineProxySettings.fromJson(Map<String, Object?> json) {
    final Object? enabled = json['enabled'];
    if (enabled is! bool) {
      throw const FormatException('Proxy enabled state must be a boolean.');
    }
    final Object? host = json['host'];
    final Object? port = json['port'];
    if (host is! String || port is! int) {
      throw const FormatException('Stored proxy address is invalid.');
    }
    return enabled
        ? OnlineProxySettings.enabled(host: host, port: port)
        : OnlineProxySettings.disabledWithAddress(host: host, port: port);
  }

  factory OnlineProxySettings.fromEnvironment() {
    const String source = String.fromEnvironment('SANMILL_ONLINE_PROXY');
    if (source.trim().isEmpty) {
      return disabled;
    }
    return OnlineProxySettings.parseAuthority(source);
  }

  factory OnlineProxySettings.parseAuthority(String source) {
    final String value = source.trim();
    final RegExpMatch? bracketed = RegExp(
      r'^\[([^\]]+)\]:(\d+)$',
    ).firstMatch(value);
    if (bracketed != null) {
      return OnlineProxySettings.enabled(
        host: bracketed.group(1)!,
        port: int.parse(bracketed.group(2)!),
      );
    }
    final RegExpMatch? ordinary = RegExp(
      r'^([^:\s]+):(\d+)$',
    ).firstMatch(value);
    if (ordinary == null) {
      throw const FormatException(
        'Proxy must use the host:port format. IPv6 addresses need brackets.',
      );
    }
    return OnlineProxySettings.enabled(
      host: ordinary.group(1)!,
      port: int.parse(ordinary.group(2)!),
    );
  }

  static const OnlineProxySettings disabled = OnlineProxySettings._(
    enabled: false,
    host: '',
    port: 7890,
  );

  final bool enabled;
  final String host;
  final int port;

  String get authority => host.contains(':') ? '[$host]:$port' : '$host:$port';

  String get proxyDirective {
    if (!enabled) {
      throw StateError('A disabled proxy has no proxy directive.');
    }
    return 'PROXY $authority';
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'host': host,
    'port': port,
  };

  static bool isValidHost(String source) {
    try {
      _normalizeHost(source);
      return true;
    } on FormatException {
      return false;
    }
  }

  static String _normalizeHost(String source) {
    String host = source.trim();
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    if (host.isEmpty || RegExp(r'[\s/@?#]').hasMatch(host)) {
      throw const FormatException('Proxy host is invalid.');
    }
    final bool isIpv6 = host.contains(':');
    final Uri? parsed = Uri.tryParse(
      isIpv6 ? 'http://[$host]' : 'http://$host',
    );
    if (parsed == null || parsed.host.isEmpty) {
      throw const FormatException('Proxy host is invalid.');
    }
    return parsed.host;
  }

  static void _validatePort(int port) {
    if (port < 1 || port > 65535) {
      throw const FormatException('Proxy port must be between 1 and 65535.');
    }
  }
}

abstract interface class OnlineProxySettingsStore {
  Future<OnlineProxySettings?> read();

  Future<void> write(OnlineProxySettings settings);
}

class SecureOnlineProxySettingsStore implements OnlineProxySettingsStore {
  SecureOnlineProxySettingsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'online.friend_match.proxy.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<OnlineProxySettings?> read() async {
    final String? source = await _storage.read(key: _key);
    if (source == null) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(source);
      if (decoded is! Map) {
        throw const FormatException('Stored proxy must be an object.');
      }
      return OnlineProxySettings.fromJson(decoded.cast<String, Object?>());
    } on Object {
      await _storage.delete(key: _key);
      return null;
    }
  }

  @override
  Future<void> write(OnlineProxySettings settings) {
    return _storage.write(key: _key, value: jsonEncode(settings.toJson()));
  }
}
