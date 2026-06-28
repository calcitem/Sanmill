// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// build_info.dart

import 'package:flutter/services.dart';

/// Asset that holds the UTC build timestamp stamped by `flutter-init.sh`
/// (mirrors the `git-revision.txt` build stamp).  Loaded by literal path
/// rather than the generated `Assets` accessor so this code keeps compiling
/// even before `flutter_gen` regenerates after the asset is first added.
const String _buildTimeAsset = 'assets/files/build-time.txt';

/// The UTC build timestamp (ISO 8601, e.g. `2026-06-28T11:23:29Z`) recorded
/// when this app bundle was assembled, or `null` when the stamp is missing
/// (for example a build that skipped `flutter-init.sh`).
///
/// Surfaced on the About page version dialog and in the engine-failure /
/// crash report so a report can be tied to an exact build.
Future<String?> get appBuildTime async {
  try {
    final String raw = (await rootBundle.loadString(_buildTimeAsset)).trim();
    return raw.isEmpty ? null : raw;
  } catch (_) {
    // Asset absent (stamp not generated): callers treat this as "unknown".
    return null;
  }
}
