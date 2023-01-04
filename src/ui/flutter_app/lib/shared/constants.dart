// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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

import 'package:flutter/cupertino.dart';

class URL {
  const URL({
    required this.url,
    required this.urlZh,
  });

  final String url;
  final String urlZh;

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
  static const List<String> recipients = <String>["$authorAccount@outlook.com"];

  static String settingsFilename = "${projectNameLower}_settings.json";
  static const String crashLogsFileName = "$projectName-crash-logs.txt";

  static const String feedbackSubjectPrefix = "[$appName] $projectName ";
  static const String feedbackSubjectSuffix = " Feedback";

  static const String fullRepoName = "$authorAccount/$projectName";

  static const URL scmURL = URL(
    url: "https://github.com",
    urlZh: "https://gitee.com",
  );

  static final URL repoURL = scmURL.fromSubPath(fullRepoName);
  static final URL issuesURL = repoURL.fromSubPath("issues");
  static final URL wikiURL = repoURL.fromSubPath("wiki", "wikis");
  static final URL eulaURL = wikiURL.fromSubPath("EULA", "EULA_zh");
  static const String appleStdEulaURL =
      "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/";
  static final URL thirdPartyNoticesURL =
      wikiURL.fromSubPath("third-party_notices");
  static final URL privacyPolicyURL =
      wikiURL.fromSubPath("privacy_policy", "privacy_policy_zh");
  static final URL helpImproveTranslateURL =
      wikiURL.fromSubPath("Translation-and-Localization");
  static final URL thanksURL = wikiURL.fromSubPath("thanks");

  static final double _windowWidth = window.physicalSize.width;
  static final double _windowHeight = window.physicalSize.height;
  static final double windowAspectRatio = _windowHeight / _windowWidth;

  static const int screenThreshold = 800;
  static bool get isSmallScreen => _windowHeight <= screenThreshold;
  static bool get isLargeScreen => !isSmallScreen;

  static const int topSkillLevel = 30;
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey();
