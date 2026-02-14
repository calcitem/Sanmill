// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// environment_config_test.dart

import 'package:flutter_test/flutter_test.dart';
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
  });
}
