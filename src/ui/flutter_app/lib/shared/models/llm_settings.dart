// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Supported, intentionally narrow transports for AI game analysis.
enum LlmTransport { localOllama, selfHostedProxy }

/// Local-only configuration and consent record for AI game analysis.
@immutable
class LlmSettings {
  const LlmSettings({
    this.enabled = false,
    this.transport = LlmTransport.selfHostedProxy,
    this.endpoint = '',
    this.model = '',
    this.proxyOperatorName = '',
    this.proxyPrivacyPolicyUrl = '',
    this.consentVersion = 0,
    this.consentConfigDigest = '',
    this.adultConfirmed = false,
    this.remoteTransmissionConsented = false,
    this.consentedAtEpochMs,
    this.migrationVersion = 0,
    this.migrationNoticePending = false,
  });

  static const int currentConsentVersion = 1;
  static const int currentMigrationVersion = 1;

  final bool enabled;
  final LlmTransport transport;
  final String endpoint;
  final String model;
  final String proxyOperatorName;
  final String proxyPrivacyPolicyUrl;
  final int consentVersion;
  final String consentConfigDigest;
  final bool adultConfirmed;
  final bool remoteTransmissionConsented;
  final int? consentedAtEpochMs;
  final int migrationVersion;
  final bool migrationNoticePending;

  String get configurationDigest {
    final String canonical = jsonEncode(<String, String>{
      'protocol': 'sanmill-analysis-v1',
      'transport': transport.name,
      'endpoint': endpoint.trim(),
      'model': model.trim(),
      'operator': proxyOperatorName.trim(),
      'privacyPolicy': proxyPrivacyPolicyUrl.trim(),
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  bool get hasValidConsent {
    if (!adultConfirmed || consentVersion != currentConsentVersion) {
      return false;
    }
    if (transport == LlmTransport.selfHostedProxy &&
        !remoteTransmissionConsented) {
      return false;
    }
    return consentedAtEpochMs != null &&
        consentConfigDigest == configurationDigest;
  }

  LlmSettings copyWith({
    bool? enabled,
    LlmTransport? transport,
    String? endpoint,
    String? model,
    String? proxyOperatorName,
    String? proxyPrivacyPolicyUrl,
    int? consentVersion,
    String? consentConfigDigest,
    bool? adultConfirmed,
    bool? remoteTransmissionConsented,
    int? consentedAtEpochMs,
    bool clearConsentedAt = false,
    int? migrationVersion,
    bool? migrationNoticePending,
  }) {
    return LlmSettings(
      enabled: enabled ?? this.enabled,
      transport: transport ?? this.transport,
      endpoint: endpoint ?? this.endpoint,
      model: model ?? this.model,
      proxyOperatorName: proxyOperatorName ?? this.proxyOperatorName,
      proxyPrivacyPolicyUrl:
          proxyPrivacyPolicyUrl ?? this.proxyPrivacyPolicyUrl,
      consentVersion: consentVersion ?? this.consentVersion,
      consentConfigDigest: consentConfigDigest ?? this.consentConfigDigest,
      adultConfirmed: adultConfirmed ?? this.adultConfirmed,
      remoteTransmissionConsented:
          remoteTransmissionConsented ?? this.remoteTransmissionConsented,
      consentedAtEpochMs: clearConsentedAt
          ? null
          : (consentedAtEpochMs ?? this.consentedAtEpochMs),
      migrationVersion: migrationVersion ?? this.migrationVersion,
      migrationNoticePending:
          migrationNoticePending ?? this.migrationNoticePending,
    );
  }

  LlmSettings grantConsent({required bool enable}) {
    final LlmSettings candidate = copyWith(
      enabled: enable,
      consentVersion: currentConsentVersion,
      adultConfirmed: true,
      remoteTransmissionConsented: transport == LlmTransport.selfHostedProxy,
      consentedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
    return candidate.copyWith(
      consentConfigDigest: candidate.configurationDigest,
    );
  }

  LlmSettings revokeConsent() {
    return copyWith(
      enabled: false,
      consentVersion: 0,
      consentConfigDigest: '',
      adultConfirmed: false,
      remoteTransmissionConsented: false,
      clearConsentedAt: true,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'transport': transport.name,
    'endpoint': endpoint,
    'model': model,
    'proxyOperatorName': proxyOperatorName,
    'proxyPrivacyPolicyUrl': proxyPrivacyPolicyUrl,
    'consentVersion': consentVersion,
    'consentConfigDigest': consentConfigDigest,
    'adultConfirmed': adultConfirmed,
    'remoteTransmissionConsented': remoteTransmissionConsented,
    'consentedAtEpochMs': consentedAtEpochMs,
    'migrationVersion': migrationVersion,
    'migrationNoticePending': migrationNoticePending,
  };

  // ignore: sort_constructors_first
  factory LlmSettings.fromJson(Map<dynamic, dynamic> json) {
    final String transportName = json['transport'] as String? ?? '';
    final LlmTransport transport = LlmTransport.values.firstWhere(
      (LlmTransport value) => value.name == transportName,
      orElse: () => LlmTransport.selfHostedProxy,
    );
    return LlmSettings(
      enabled: json['enabled'] as bool? ?? false,
      transport: transport,
      endpoint: json['endpoint'] as String? ?? '',
      model: json['model'] as String? ?? '',
      proxyOperatorName: json['proxyOperatorName'] as String? ?? '',
      proxyPrivacyPolicyUrl: json['proxyPrivacyPolicyUrl'] as String? ?? '',
      consentVersion: json['consentVersion'] as int? ?? 0,
      consentConfigDigest: json['consentConfigDigest'] as String? ?? '',
      adultConfirmed: json['adultConfirmed'] as bool? ?? false,
      remoteTransmissionConsented:
          json['remoteTransmissionConsented'] as bool? ?? false,
      consentedAtEpochMs: json['consentedAtEpochMs'] as int?,
      migrationVersion: json['migrationVersion'] as int? ?? 0,
      migrationNoticePending: json['migrationNoticePending'] as bool? ?? false,
    );
  }
}
