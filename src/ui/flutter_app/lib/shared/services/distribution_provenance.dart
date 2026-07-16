// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'environment_config.dart';
import 'logger.dart';

/// Non-user-identifying build and signing provenance included in reports.
class DistributionProvenance {
  const DistributionProvenance({
    required this.applicationId,
    required this.version,
    required this.buildNumber,
    required this.platform,
    required this.channel,
    required this.sourceRevision,
    required this.sourceUrl,
    required this.declaredDistributor,
    required this.signingKind,
    required this.signingDigest,
    required this.signingStatus,
  });

  static const MethodChannel _channel = MethodChannel(
    'com.calcitem.sanmill/diagnostics',
  );

  final String applicationId;
  final String version;
  final String buildNumber;
  final String platform;
  final String channel;
  final String sourceRevision;
  final String sourceUrl;
  final String declaredDistributor;
  final String signingKind;
  final String? signingDigest;
  final String signingStatus;

  static Future<DistributionProvenance> collect() async {
    final PackageInfo package = await PackageInfo.fromPlatform();
    String? runtimeSigningDigest;
    if (!kIsWeb && Platform.isAndroid) {
      try {
        runtimeSigningDigest = await _channel.invokeMethod<String>(
          'getSigningCertificateSha256',
        );
      } on MissingPluginException {
        // Older/source builds remain diagnosable and explicitly say that the
        // runtime signing evidence is unavailable.
      } on PlatformException catch (error) {
        logger.w('[DistributionProvenance] Signing query failed: $error');
      }
    }
    final String? buildSigningDigest =
        EnvironmentConfig.signerDigest.trim().isEmpty
        ? null
        : EnvironmentConfig.signerDigest.trim();
    final String? signingDigest = runtimeSigningDigest ?? buildSigningDigest;
    return DistributionProvenance(
      applicationId: package.packageName,
      version: package.version,
      buildNumber: package.buildNumber,
      platform: _platformName(),
      channel: EnvironmentConfig.distributionChannel,
      sourceRevision: EnvironmentConfig.sourceRevision,
      sourceUrl: EnvironmentConfig.sourceUrl,
      declaredDistributor: EnvironmentConfig.declaredDistributor,
      signingKind: _signingKind(),
      signingDigest: signingDigest,
      signingStatus: signingDigest == null
          ? (_signingKind() == 'unavailable'
                ? 'platform-does-not-provide-signing'
                : 'not-observed')
          : runtimeSigningDigest == null
          ? 'build-declared'
          : 'runtime-observed',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'applicationId': applicationId,
    'version': version,
    'buildNumber': buildNumber,
    'platform': platform,
    'channel': channel,
    'sourceRevision': sourceRevision,
    'sourceUrl': sourceUrl,
    'declaredDistributor': declaredDistributor,
    'signing': <String, dynamic>{
      'kind': signingKind,
      'status': signingStatus,
      if (signingDigest != null) 'sha256': signingDigest,
    },
  };

  static String _platformName() {
    if (kIsWeb) {
      return 'web';
    }
    return Platform.operatingSystem;
  }

  static String _signingKind() {
    if (kIsWeb || Platform.isLinux) {
      return 'unavailable';
    }
    if (Platform.isAndroid) {
      return 'android-certificate-sha256';
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return 'apple-team-id-digest';
    }
    if (Platform.isWindows) {
      return 'windows-signing-certificate-sha256';
    }
    return 'unknown';
  }
}
