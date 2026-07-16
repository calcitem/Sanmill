// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores AI proxy credentials outside the settings database.
///
/// Web credentials are session-only because browser-backed secure storage
/// cannot provide the same OS-keystore guarantees as native platforms.
class LlmSecureStore {
  factory LlmSecureStore() => _instance;
  LlmSecureStore._();

  static final LlmSecureStore _instance = LlmSecureStore._();
  static const String _proxyTokenKey = 'llm_proxy_access_token_v1';
  static final Map<String, String> _webSessionValues = <String, String>{};
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions.defaultOptions,
  );

  Future<String> readProxyToken() async {
    if (kIsWeb) {
      return _webSessionValues[_proxyTokenKey] ?? '';
    }
    return await _storage.read(key: _proxyTokenKey) ?? '';
  }

  Future<void> writeProxyToken(String token) async {
    final String value = token.trim();
    if (kIsWeb) {
      if (value.isEmpty) {
        _webSessionValues.remove(_proxyTokenKey);
      } else {
        _webSessionValues[_proxyTokenKey] = value;
      }
      return;
    }
    if (value.isEmpty) {
      await _storage.delete(key: _proxyTokenKey);
    } else {
      await _storage.write(key: _proxyTokenKey, value: value);
    }
  }

  Future<void> clearProxyToken() => writeProxyToken('');

  Future<void> writeReportDeleteToken(String reportId, String token) async {
    final String key = 'ai_report_delete_$reportId';
    if (kIsWeb) {
      _webSessionValues[key] = token;
      return;
    }
    await _storage.write(key: key, value: token);
  }

  Future<String?> readReportDeleteToken(String reportId) async {
    final String key = 'ai_report_delete_$reportId';
    if (kIsWeb) {
      return _webSessionValues[key];
    }
    return _storage.read(key: key);
  }

  Future<void> deleteReportDeleteToken(String reportId) async {
    final String key = 'ai_report_delete_$reportId';
    if (kIsWeb) {
      _webSessionValues.remove(key);
      return;
    }
    await _storage.delete(key: key);
  }
}
