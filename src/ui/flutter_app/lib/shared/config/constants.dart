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

class UrlHelper {
  const UrlHelper({
    required this.base,
    required this.baseChinese,
  });

  final String base;
  final String baseChinese;

  UrlHelper fromSubPath(String path, [String? pathChinese]) {
    return UrlHelper(
      base: "$base/$path",
      baseChinese: "$baseChinese/${pathChinese ?? path}",
    );
  }
}

class Constants {
  const Constants._();
  static const String appName = "Mill";
  static const String authorAccount = "calcitem";
  static const String projectName = "Sanmill";
  static String projectNameLower = projectName.toLowerCase();
  static const List<String> recipientEmails = <String>[
    "$authorAccount@outlook.com"
  ];

  static String settingsFile = "${projectNameLower}_settings.json";
  static const String crashLogsFile = "$projectName-crash-logs.txt";

  static const String feedbackSubjectPrefix = "[$appName] $projectName ";
  static const String feedbackSubjectSuffix = " Feedback";

  static const String fullRepositoryName = "$authorAccount/$projectName";

  static const UrlHelper sourceControlUrl = UrlHelper(
    base: "https://github.com",
    baseChinese: "https://gitee.com",
  );

  static final UrlHelper repositoryUrl =
      sourceControlUrl.fromSubPath(fullRepositoryName);
  static final UrlHelper issuesURL = repositoryUrl.fromSubPath("issues");
  static final UrlHelper wikiURL = repositoryUrl.fromSubPath("wiki", "wikis");
  static final UrlHelper endUserLicenseAgreementUrl =
      wikiURL.fromSubPath("EULA", "EULA_zh");
  static const String appleStandardEulaUrl =
      "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/";
  static final UrlHelper thirdPartyNoticesURL =
      wikiURL.fromSubPath("third-party_notices");
  static final UrlHelper privacyPolicyUrl =
      wikiURL.fromSubPath("privacy_policy", "privacy_policy_zh");
  static final UrlHelper helpImproveTranslateURL =
      wikiURL.fromSubPath("Translation-and-Localization");
  static final UrlHelper thanksURL = wikiURL.fromSubPath("thanks");

  static final double _windowWidth = window.physicalSize.width;
  static final double _windowHeight = window.physicalSize.height;
  static final double windowAspectRatio = _windowHeight / _windowWidth;

  static const int screenSizeThreshold = 800;
  static bool get isSmallScreen => _windowHeight <= screenSizeThreshold;
  static bool get isLargeScreen => !isSmallScreen;

  static const int highestSkillLevel = 30;
}

// TODO: Move to navigation folder
final GlobalKey<NavigatorState> navigatorStateKey = GlobalKey();
