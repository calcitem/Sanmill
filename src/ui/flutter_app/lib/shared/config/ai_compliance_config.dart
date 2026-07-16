// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

/// Compile-time release gate for AI game analysis.
///
/// Official builds must enable this only after the current legal notice,
/// store declarations, EU representative assessment, processor terms, and
/// production report relay have all been approved for that release.
abstract final class AiComplianceConfig {
  static const bool releaseApproved = bool.fromEnvironment(
    'SANMILL_ENABLE_AI_ANALYSIS',
  );

  static const String reportRelayUrl = String.fromEnvironment(
    'SANMILL_AI_REPORT_RELAY_URL',
  );

  static bool get releaseGateSatisfied {
    if (!releaseApproved) {
      return false;
    }
    final Uri? uri = Uri.tryParse(reportRelayUrl.trim());
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }
}
