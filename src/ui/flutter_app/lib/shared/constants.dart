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

import 'dart:ui';

class URL {
  final String url;
  final String urlZh;

  const URL({
    required this.url,
    required this.urlZh,
  });

  URL fromSubPath(String path, [String? pathZh]) {
    return URL(
      url: "$url/$path",
      urlZh: "$urlZh/${pathZh ?? path}",
    );
  }
}

class Constants {
  const Constants._();
  static const String appName = "Mill";
  static const String authorAccount = "calcitem";
  static const String projectName = "Sanmill";
  static String projectNameLower = projectName.toLowerCase();
  static const List<String> recipients = ["$authorAccount@outlook.com"];

  static String settingsFilename = "${projectNameLower}_settings.json";
  static const String crashLogsFileName = "$projectName-crash-logs.txt";

  static const String feedbackSubjectPrefix = "[$appName] $projectName ";
  static const String feedbackSubjectSuffix = " Feedback";

  static const String fullRepoName = "$authorAccount/$projectName";

  static const scmURL = URL(
    url: "https://github.com",
    urlZh: "https://gitee.com",
  );

  static final repoURL = scmURL.fromSubPath(fullRepoName);
  static final issuesURL = repoURL.fromSubPath("issues");
  static final wikiURL = repoURL.fromSubPath("wiki", "wikis");
  static final eulaURL = wikiURL.fromSubPath("EULA", "EULA_zh");
  static final thirdPartyNoticesURL =
      wikiURL.fromSubPath("third-party_notices");
  static final privacyPolicyURL =
      wikiURL.fromSubPath("privacy_policy", "privacy_policy_zh");
  static final helpImproveTranslateURL =
      wikiURL.fromSubPath("Translation-and-Localization");
  static final thanksURL = wikiURL.fromSubPath("thanks");

  static final _windowWidth = window.physicalSize.width;
  static final _windowHeight = window.physicalSize.height;
  static final windowAspectRatio = _windowHeight / _windowWidth;

  static const screenThreshold = 800;
  static bool get isSmallScreen => _windowHeight <= screenThreshold;
  static bool get isLargeScreen => !isSmallScreen;
}
