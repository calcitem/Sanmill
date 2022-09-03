// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import 'package:flutter/services.dart';
import 'package:sanmill/generated/assets/assets.gen.dart';

/// Information about the local git repository
class GitInformation {
  /// The current checked out branch
  final String branch;

  /// The current commit id
  final String? revision;

  /// Construct a [GitInformation] from a [branch] and [revision]
  const GitInformation({required this.branch, required this.revision});
}

/// Get the [GitInformation] for the local git repository
Future<GitInformation> get gitInfo async {
  final String branch = await rootBundle.loadString(Assets.files.gitBranch);
  final String revision = await rootBundle.loadString(Assets.files.gitRevision);

  return GitInformation(branch: branch, revision: revision);
}
