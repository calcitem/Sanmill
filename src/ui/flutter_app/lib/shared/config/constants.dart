// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// constants.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:catcher_2/core/catcher_2.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/environment_config.dart';

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

  static const UrlHelper staticWebpageUrl = UrlHelper(
    base: "https://$authorAccount.github.io",
    baseChinese: "https://$authorAccount.github.io",
  );

  static const UrlHelper weblateUrl = UrlHelper(
    base: "https://hosted.weblate.org",
    baseChinese: "https://hosted.weblate.org",
  );

  static final UrlHelper repositoryUrl =
      sourceControlUrl.fromSubPath(fullRepositoryName);
  static final UrlHelper issuesURL = repositoryUrl.fromSubPath("issues");
  static final UrlHelper wikiURL = repositoryUrl.fromSubPath("wiki", "wikis");
  static final UrlHelper legalURL =
      staticWebpageUrl.fromSubPath("$projectNameLower-legal");
  static final UrlHelper endUserLicenseAgreementUrl =
      legalURL.fromSubPath("eula", "eula_zh");
  static const String appleStandardEulaUrl =
      "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/";
  static final UrlHelper thirdPartyNoticesURL =
      wikiURL.fromSubPath("third-party_notices");
  static final UrlHelper privacyPolicyUrl =
      legalURL.fromSubPath("privacy-policy", "privacy-policy_zh");
  static final UrlHelper helpImproveTranslateURL =
      weblateUrl.fromSubPath("zen/$projectNameLower/flutter");
  static final UrlHelper thanksURL = wikiURL.fromSubPath("thanks");
  static final UrlHelper perfectDatabaseUrl =
      wikiURL.fromSubPath("Perfect-Database", "Perfect-Database-(Chinese)");

  static double _getWindowHeight(BuildContext context) {
    final ui.FlutterView view = View.of(context);
    final double devicePixelRatio = view.devicePixelRatio;
    final double physicalHeight = view.physicalSize.height;

    if (devicePixelRatio <= 0) {
      return physicalHeight;
    }

    // Convert to logical pixels so density does not misclassify phones as
    // "large" screens when they simply have a high resolution display.
    return physicalHeight / devicePixelRatio;
  }

  static const int screenSizeThreshold = 800;

  static bool isSmallScreen(BuildContext context) {
    return _getWindowHeight(context) <= screenSizeThreshold;
  }

  static bool isLargeScreen(BuildContext context) {
    return !isSmallScreen(context);
  }

  static const int highestSkillLevel = 30;

  static bool isAndroid10Plus = false;
}

// Keep the navigator key with the other global configuration so it is
// available during application bootstrap.
final GlobalKey<NavigatorState> navigatorStateKey = GlobalKey();

GlobalKey<NavigatorState> get currentNavigatorKey {
  if (EnvironmentConfig.catcher && !kIsWeb && !Platform.isIOS) {
    if (Catcher2.navigatorKey == null) {
      return navigatorStateKey;
    }
    return Catcher2.navigatorKey;
  } else {
    return navigatorStateKey;
  }
}
