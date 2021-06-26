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

class Constants {
  static String appName = "Mill";
  static String authorAccount = "calcitem";
  static String projectName = "Sanmill";
  static String projectNameLower = projectName.toLowerCase();
  static String recipients = "$authorAccount@outlook.com";

  static String settingsFilename = "${projectNameLower}_settings.json";
  static String crashLogsFileName = "$projectName-crash-logs.txt";
  static String environmentVariablesFilename =
      "assets/files/environment_variables.txt";
  static String gplLicenseFilename = "assets/licenses/GPL-3.0.txt";

  static String defaultLanguageCodeName = "Default";

  static String feedbackSubjectPrefix = "[$appName] $projectName ";
  static String feedbackSubjectSuffix = " Feedback";

  static String githubURL = "https://github.com";
  static String giteeURL = "https://gitee.com";

  static String fullRepoName = "$authorAccount/$projectName";

  static String githubRepoURL = "$githubURL/$fullRepoName";
  static String giteeRepoURL = "$giteeURL/$fullRepoName";

  static String githubRepoWiKiURL = "$githubURL/$fullRepoName/wiki";
  static String giteeRepoWiKiURL = "$giteeURL/$fullRepoName/wikis";

  static String githubIssuesURL = "$githubRepoURL/issues";
  static String giteeIssuesURL = "$giteeRepoURL/issues";

  static String githubEulaURL = "$githubRepoWiKiURL/EULA";
  static String giteeEulaURL = "$giteeRepoWiKiURL/EULA_zh";

  static String githubSourceCodeURL = "$githubRepoURL";
  static String giteeSourceCodeURL = "$giteeRepoURL";

  static String githubThirdPartyNoticesURL =
      "$githubRepoURL/wiki/third-party_notices";
  static String giteeThirdPartyNoticesURL =
      "$giteeRepoURL/wikis/third-party_notices";

  static String githubPrivacyPolicyURL = "$githubRepoWiKiURL/privacy_policy";
  static String giteePrivacyPolicyURL = "$giteeRepoWiKiURL/privacy_policy_zh";

  static String githubThanksURL = "$githubRepoWiKiURL/thanks";
  static String giteeThanksURL = "$giteeRepoWiKiURL/thanks";
}
