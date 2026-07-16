// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'app.dart';
import 'shared/services/environment_config.dart';

void configureFdroidEnvironment() {
  // F-Droid builds are always local-only. Copy/import/replay remains available,
  // but this entry point cannot send a diagnostic network request even if a
  // downstream build environment accidentally supplies a DSN.
  EnvironmentConfig.diagnosticsRemoteDisabled = true;
  EnvironmentConfig.diagnosticsDsn = '';
  EnvironmentConfig.diagnosticsRecipient = '';
  EnvironmentConfig.diagnosticsPrivacyUrl = '';
  EnvironmentConfig.distributionChannel = 'fdroid';
  EnvironmentConfig.declaredDistributor = 'F-Droid';
}

Future<void> main() {
  configureFdroidEnvironment();
  return runSanmillApp();
}
