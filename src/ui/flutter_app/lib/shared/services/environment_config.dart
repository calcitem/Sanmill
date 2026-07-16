// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

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

  /// Whether to enable Address Sanitizer in dev mode
  static bool devModeAsan = const bool.fromEnvironment('DEV_MODE');

  /// Gets whether we want catcher to be enabled
  /// Defaults to true
  static bool catcher = const bool.fromEnvironment(
    "catcher",
    defaultValue: true,
  );

  /// Gets log level
  /// Defaults to 0 (all) to record all logs for user viewing
  /// Level values: 0=all, 1=trace, 2=debug, 3=info, 4=warning, 5=error, 6=fatal
  static const int logLevel = int.fromEnvironment("log_level");

  /// Public GlitchTip DSN injected by an official or downstream build.
  ///
  /// A DSN is intentionally not a secret, but it is kept out of this checkout
  /// until the jointly administered project endpoint exists. Remote sending is
  /// disabled unless the DSN, recipient name and privacy URL are all present.
  static String diagnosticsDsn = const String.fromEnvironment(
    'SANMILL_DIAGNOSTICS_DSN',
  );

  static String diagnosticsRecipient = const String.fromEnvironment(
    'SANMILL_DIAGNOSTICS_RECIPIENT',
  );

  static String diagnosticsPrivacyUrl = const String.fromEnvironment(
    'SANMILL_DIAGNOSTICS_PRIVACY_URL',
  );

  /// F-Droid can force local-only diagnostics without patching source code.
  static bool diagnosticsRemoteDisabled = const bool.fromEnvironment(
    'SANMILL_DIAGNOSTICS_REMOTE_DISABLED',
  );

  static String distributionChannel = const String.fromEnvironment(
    'SANMILL_DISTRIBUTION_CHANNEL',
    defaultValue: 'source',
  );

  static String declaredDistributor = const String.fromEnvironment(
    'SANMILL_DISTRIBUTOR',
    defaultValue: 'unconfigured',
  );

  static const String sourceRevision = String.fromEnvironment(
    'SANMILL_SOURCE_REVISION',
    defaultValue: 'unknown',
  );

  static const String sourceUrl = String.fromEnvironment(
    'SANMILL_SOURCE_URL',
    defaultValue: 'https://github.com/calcitem/Sanmill',
  );

  /// Platform build pipelines may provide a signing certificate/team digest.
  static const String signerDigest = String.fromEnvironment(
    'SANMILL_SIGNER_DIGEST',
  );
}
