// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// environment_config.dart

/// Environment configuration
///
/// Enables device to start the app with compile time options
class EnvironmentConfig {
  const EnvironmentConfig._();

  /// Gets whether we build for Monkey/Appium testing
  static bool test = const bool.fromEnvironment('test');

  /// Gets whether we build for devMode
  static bool devMode = const bool.fromEnvironment('dev_mode');

  /// Gets whether we want catcher to be enabled
  /// Defaults to true
  static bool catcher =
      const bool.fromEnvironment("catcher", defaultValue: true);

  /// Gets log level
  /// Defaults to 4
  static const int logLevel = int.fromEnvironment("log_level", defaultValue: 4);
}
