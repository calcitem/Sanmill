// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/ai_compliance_config.dart';
import '../models/llm_analysis.dart';
import 'llm_secure_store.dart';

enum AiReportCategory {
  harmful,
  hate,
  sexual,
  selfHarm,
  privacy,
  offTopic,
  incorrect,
  other,
}

class AiReportReceipt {
  const AiReportReceipt({required this.reportId, required this.expiresAt});
  final String reportId;
  final DateTime expiresAt;
}

class AiReportService {
  AiReportService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  static const Duration _timeout = Duration(seconds: 20);
  final http.Client _httpClient;

  bool get isAvailable => _validatedBaseUri != null;

  Future<AiReportReceipt> submit({
    required AiReportCategory category,
    required LlmTask task,
    required String provider,
    required String model,
    required String appVersion,
    required String platform,
    required String locale,
    String? includedAnswer,
  }) async {
    final Uri? baseUri = _validatedBaseUri;
    if (baseUri == null) {
      throw StateError('AI report relay is not configured.');
    }
    final Uri uri = baseUri.replace(
      path: _joinPath(baseUri.path, 'v1/reports'),
    );
    final http.Response response = await _send(
      'POST',
      uri,
      body: <String, dynamic>{
        'schemaVersion': 1,
        'category': category.name,
        'task': task.name,
        'surface': 'gameAnalysis',
        'provider': provider,
        'model': model,
        'appVersion': appVersion,
        'platform': platform,
        'locale': locale,
        'answer': ?includedAnswer,
      },
    );
    if (response.statusCode != 201 || response.bodyBytes.length > 4096) {
      throw StateError('AI report relay rejected the request.');
    }
    final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid report response.');
    }
    final String reportId = decoded['reportId'] as String? ?? '';
    final String deleteToken = decoded['deleteToken'] as String? ?? '';
    final DateTime? expiresAt = DateTime.tryParse(
      decoded['expiresAt'] as String? ?? '',
    );
    if (reportId.isEmpty || deleteToken.isEmpty || expiresAt == null) {
      throw const FormatException('Invalid report receipt.');
    }
    await LlmSecureStore().writeReportDeleteToken(reportId, deleteToken);
    return AiReportReceipt(reportId: reportId, expiresAt: expiresAt);
  }

  Future<void> delete(String reportId) async {
    final Uri? baseUri = _validatedBaseUri;
    final String? token = await LlmSecureStore().readReportDeleteToken(
      reportId,
    );
    if (baseUri == null || token == null || token.isEmpty) {
      throw StateError('Report deletion is not available.');
    }
    final Uri uri = baseUri.replace(
      path: _joinPath(baseUri.path, 'v1/reports/$reportId'),
    );
    final http.Response response = await _send(
      'DELETE',
      uri,
      headers: <String, String>{'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 204 && response.statusCode != 404) {
      throw StateError('AI report relay rejected deletion.');
    }
    await LlmSecureStore().deleteReportDeleteToken(reportId);
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
    Map<String, dynamic>? body,
  }) async {
    final http.Request request = http.Request(method, uri)
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers.addAll(<String, String>{
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
        ...headers,
      });
    if (body != null) {
      request.body = jsonEncode(body);
    }
    final http.StreamedResponse streamed = await _httpClient
        .send(request)
        .timeout(_timeout);
    if (streamed.isRedirect) {
      throw StateError('Report relay redirects are not accepted.');
    }
    return http.Response.fromStream(streamed).timeout(_timeout);
  }

  Uri? get _validatedBaseUri {
    final Uri? uri = Uri.tryParse(AiComplianceConfig.reportRelayUrl.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    return uri;
  }

  String _joinPath(String base, String suffix) {
    final String trimmedBase = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return '$trimmedBase/$suffix';
  }
}
