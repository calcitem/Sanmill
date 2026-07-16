// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// environment_config_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/main_fdroid.dart' show configureFdroidEnvironment;
import 'package:sanmill/shared/services/environment_config.dart';

void main() {
  group('EnvironmentConfig', () {
    test('test flag should default to false in normal build', () {
      // bool.fromEnvironment('test') defaults to false
      // unless overridden at compile-time
      expect(EnvironmentConfig.test, isFalse);
    });

    test('devMode flag should default to false in normal build', () {
      expect(EnvironmentConfig.devMode, isFalse);
    });

    test('devModeAsan flag should default to false in normal build', () {
      expect(EnvironmentConfig.devModeAsan, isFalse);
    });

    test('catcher can be toggled at runtime', () {
      // Store original value
      final bool original = EnvironmentConfig.catcher;

      EnvironmentConfig.catcher = false;
      expect(EnvironmentConfig.catcher, isFalse);

      EnvironmentConfig.catcher = true;
      expect(EnvironmentConfig.catcher, isTrue);

      // Restore
      EnvironmentConfig.catcher = original;
    });

    test('logLevel should default to 0 (all)', () {
      expect(EnvironmentConfig.logLevel, 0);
    });

    test('test and devMode are mutable', () {
      final bool origTest = EnvironmentConfig.test;
      final bool origDev = EnvironmentConfig.devMode;

      EnvironmentConfig.test = true;
      expect(EnvironmentConfig.test, isTrue);
      EnvironmentConfig.test = origTest;

      EnvironmentConfig.devMode = true;
      expect(EnvironmentConfig.devMode, isTrue);
      EnvironmentConfig.devMode = origDev;
    });

    test('F-Droid explicitly clears every remote diagnostic endpoint', () {
      final String originalDsn = EnvironmentConfig.diagnosticsDsn;
      final String originalRecipient = EnvironmentConfig.diagnosticsRecipient;
      final String originalPrivacy = EnvironmentConfig.diagnosticsPrivacyUrl;
      final bool originalDisabled = EnvironmentConfig.diagnosticsRemoteDisabled;
      final String originalChannel = EnvironmentConfig.distributionChannel;
      final String originalDistributor = EnvironmentConfig.declaredDistributor;
      addTearDown(() {
        EnvironmentConfig.diagnosticsDsn = originalDsn;
        EnvironmentConfig.diagnosticsRecipient = originalRecipient;
        EnvironmentConfig.diagnosticsPrivacyUrl = originalPrivacy;
        EnvironmentConfig.diagnosticsRemoteDisabled = originalDisabled;
        EnvironmentConfig.distributionChannel = originalChannel;
        EnvironmentConfig.declaredDistributor = originalDistributor;
      });

      EnvironmentConfig.diagnosticsDsn = 'https://public-key@errors.example/42';
      EnvironmentConfig.diagnosticsRecipient = 'unexpected receiver';
      EnvironmentConfig.diagnosticsPrivacyUrl = 'https://example/privacy';
      EnvironmentConfig.diagnosticsRemoteDisabled = false;

      configureFdroidEnvironment();

      expect(EnvironmentConfig.diagnosticsRemoteDisabled, isTrue);
      expect(EnvironmentConfig.diagnosticsDsn, isEmpty);
      expect(EnvironmentConfig.diagnosticsRecipient, isEmpty);
      expect(EnvironmentConfig.diagnosticsPrivacyUrl, isEmpty);
      expect(EnvironmentConfig.distributionChannel, 'fdroid');
      expect(EnvironmentConfig.declaredDistributor, 'F-Droid');
    });
  });
}
