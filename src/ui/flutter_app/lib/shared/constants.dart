/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'dart:ui';

class URL {
  final String url;
  final String urlZH;

  const URL({
    required this.url,
    required this.urlZH,
  });

  URL fromSubpath(String path, [String? pathZH]) {
    return URL(
      url: "$url/$path",
      urlZH: "$urlZH/${pathZH ?? path}",
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

  static const vcsURL = URL(
    url: "https://github.com",
    urlZH: "https://gitee.com",
  );

  static final repoURL = vcsURL.fromSubpath(fullRepoName);
  static final issuesURL = repoURL.fromSubpath("issues");
  static final wikiURL = repoURL.fromSubpath("wiki", "wikis");
  static final eulaURL = wikiURL.fromSubpath("EULA", "EULA_zh");
  static final thirdPartyNoticesURL =
      wikiURL.fromSubpath("third-party_notices");
  static final privacyPolicyURL =
      wikiURL.fromSubpath("privacy_policy", "privacy_policy_zh");
  static final helpImproveTranslateURL =
      wikiURL.fromSubpath("Translation-and-Localization");
  static final thanksURL = wikiURL.fromSubpath("thanks");

  static final _windowWidth = window.physicalSize.width;
  static final _windowHeight = window.physicalSize.height;
  static final windowAspectRatio = _windowHeight / _windowWidth;

  static const screenThreshhold = 800;
  static bool get isSmallScreen => _windowHeight <= screenThreshhold;
  static bool get isLargeScreen => !isSmallScreen;
}
