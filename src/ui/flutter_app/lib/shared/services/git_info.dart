// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// git_info.dart

import 'package:flutter/services.dart';

import '../../generated/assets/assets.gen.dart';

/// Information about the local git repository
class GitInfo {
  /// Construct a [GitInfo] from a [branch] and [revision]
  const GitInfo({required this.branch, required this.revision});

  /// The current checked out branch
  final String branch;

  /// The current commit id
  final String? revision;
}

/// Get the [GitInfo] for the local git repository
Future<GitInfo> get gitInfo async {
  final String branch = await rootBundle.loadString(Assets.files.gitBranch);
  final String revision = await rootBundle.loadString(Assets.files.gitRevision);

  return GitInfo(branch: branch, revision: revision);
}
