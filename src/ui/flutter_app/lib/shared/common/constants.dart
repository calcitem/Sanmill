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

class Constants {
  const Constants._();
  static const String appName = "Mill";
  static const String authorAccount = "calcitem";
  static const String projectName = "Sanmill";
  static String projectNameLower = projectName.toLowerCase();
  static const String recipients = "$authorAccount@outlook.com";

  static String settingsFilename = "${projectNameLower}_settings.json";
  static const String crashLogsFileName = "$projectName-crash-logs.txt";
  static const String environmentVariablesFilename =
      "assets/files/environment_variables.txt";
  static const String gplLicenseFilename = "assets/licenses/GPL-3.0.txt";

  static const String defaultLanguageCodeName = "Default";

  static const String feedbackSubjectPrefix = "[$appName] $projectName ";
  static const String feedbackSubjectSuffix = " Feedback";

  static const String githubURL = "https://github.com";
  static const String giteeURL = "https://gitee.com";

  static const String fullRepoName = "$authorAccount/$projectName";

  static const String githubRepoURL = "$githubURL/$fullRepoName";
  static const String giteeRepoURL = "$giteeURL/$fullRepoName";

  static const String githubRepoWiKiURL = "$githubURL/$fullRepoName/wiki";
  static const String giteeRepoWiKiURL = "$giteeURL/$fullRepoName/wikis";

  static const String githubIssuesURL = "$githubRepoURL/issues";
  static const String giteeIssuesURL = "$giteeRepoURL/issues";

  static const String githubEulaURL = "$githubRepoWiKiURL/EULA";
  static const String giteeEulaURL = "$giteeRepoWiKiURL/EULA_zh";

  static const String githubSourceCodeURL = githubRepoURL;
  static const String giteeSourceCodeURL = giteeRepoURL;

  static const String githubThirdPartyNoticesURL =
      "$githubRepoWiKiURL/third-party_notices";
  static const String giteeThirdPartyNoticesURL =
      "$giteeRepoWiKiURL/wikis/third-party_notices";

  static const String githubPrivacyPolicyURL =
      "$githubRepoWiKiURL/privacy_policy";
  static const String giteePrivacyPolicyURL =
      "$giteeRepoWiKiURL/privacy_policy_zh";

  static const String githubHelpImproveTranslateURL =
      "$githubRepoWiKiURL/Translation-and-Localization";
  static const String giteeHelpImproveTranslateURL =
      "$giteeRepoWiKiURL/Translation-and-Localization";

  static const String githubThanksURL = "$githubRepoWiKiURL/thanks";
  static const String giteeThanksURL = "$giteeRepoWiKiURL/thanks";

  static final windowWidth = window.physicalSize.width;
  static final windowHeight = window.physicalSize.height;
  static final windowAspectRatio = windowHeight / windowWidth;
}

bool get isSmallScreen => Constants.windowHeight <= 800;

bool get isLargeScreen => !isSmallScreen;
