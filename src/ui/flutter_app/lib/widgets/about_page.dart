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

import 'dart:io';

import 'package:devicelocale/devicelocale.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sanmill/common/constants.dart';
import 'package:sanmill/generated/flutter_version.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/style/app_theme.dart';
import 'package:sanmill/widgets/settings_list_tile.dart';
import 'package:url_launcher/url_launcher.dart';

import 'license_page.dart';
import 'list_item_divider.dart';
import 'oss_license_page.dart';

class AboutPage extends StatelessWidget {
  // String _version = "";
  final String tag = "[about] ";

  String getMode() {
    late String ret;
    if (kDebugMode) {
      ret = "- debug";
    } else if (kProfileMode) {
      ret = "- profile";
    } else if (kReleaseMode) {
      ret = "";
    } else {
      ret = "-test";
    }

    return ret;
  }

  @override
  Widget build(BuildContext context) {
    final String mode = getMode();

    return Scaffold(
      backgroundColor: AppTheme.aboutPageBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        title: Text("${S.of(context).about} ${S.of(context).appName}"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: children(context, mode),
        ),
      ),
    );
  }

  List<Widget> children(BuildContext context, String mode) {
    return <Widget>[
      FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (_, data) {
          late final String _version;
          if (!data.hasData) {
            _version = '';
          } else {
            final packageInfo = data.data!;
            if (Platform.isWindows) {
              _version = packageInfo.version; // TODO

            } else {
              _version = '${packageInfo.version} (${packageInfo.buildNumber})';
            }
          }
          return SettingsListTile(
            titleString: S.of(context).versionInfo,
            subtitleString: "${Constants.projectName} $_version $mode",
            onTap: () => _showVersionInfo(context, _version),
          );
        },
      ),
      const ListItemDivider(),
      SettingsListTile(
        titleString: S.of(context).feedback,
        onTap: _launchFeedback,
      ),
      const ListItemDivider(),
      SettingsListTile(
        titleString: S.of(context).eula,
        onTap: () {
          _launchEULA();
        },
      ),
      const ListItemDivider(),
      SettingsListTile(
        titleString: S.of(context).license,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LicenseAgreementPage(),
            ),
          );
        },
      ),
      const ListItemDivider(),
      SettingsListTile(
        titleString: S.of(context).sourceCode,
        onTap: () {
          _launchSourceCode();
        },
      ),
      const ListItemDivider(),
      SettingsListTile(
        titleString: S.of(context).privacyPolicy,
        onTap: () {
          _launchPrivacyPolicy();
        },
      ),
      const ListItemDivider(),
      SettingsListTile(
        titleString: S.of(context).ossLicenses,
        onTap: () {
          _launchThirdPartyNotices(context);
        },
      ),
      const ListItemDivider(),
      SettingsListTile(
        titleString: S.of(context).helpImproveTranslate,
        onTap: () {
          _launchHelpImproveTranslate();
        },
      ),
      const ListItemDivider(),
      SettingsListTile(
        titleString: S.of(context).thanks,
        onTap: () {
          _launchThanks();
        },
      ),
      const ListItemDivider(),
    ];
  }

  Future<void> _launchURL(String url) async {
    await launch(url);
  }

  Future<void> _launchFeedback() async {
    String? locale = "en_US";

    if (!Platform.isWindows) {
      locale = await Devicelocale.currentLocale;
    }

    debugPrint("$tag local = $locale");
    if (locale != null && locale.startsWith("zh_")) {
      _launchURL(Constants.giteeIssuesURL);
    } else {
      _launchURL(Constants.githubIssuesURL);
    }
  }

  Future<void> _launchEULA() async {
    String? locale = "en_US";

    if (!Platform.isWindows) {
      locale = await Devicelocale.currentLocale;
    }

    debugPrint("$tag local = $locale");
    if (locale != null && locale.startsWith("zh_")) {
      _launchURL(Constants.giteeEulaURL);
    } else {
      _launchURL(Constants.githubEulaURL);
    }
  }

  Future<void> _launchSourceCode() async {
    String? locale = "en_US";

    if (!Platform.isWindows) {
      locale = await Devicelocale.currentLocale;
    }

    debugPrint("$tag local = $locale");
    if (locale != null && locale.startsWith("zh_")) {
      _launchURL(Constants.giteeSourceCodeURL);
    } else {
      _launchURL(Constants.githubSourceCodeURL);
    }
  }

  Future<void> _launchThirdPartyNotices(BuildContext context) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OssLicensesPage(),
      ),
    );
    /*
    String? locale = "en_US";

    if (!Platform.isWindows) {
      locale = await Devicelocale.currentLocale;
    }

   debugPrint("$tag local = $locale");
    if (locale != null && locale.startsWith("zh_")) {
      _launchURL(Constants.giteeThirdPartyNoticesURL);
    } else {
      _launchURL(Constants.githubThirdPartyNoticesURL);
    }
    */
  }

  Future<void> _launchPrivacyPolicy() async {
    String? locale = "en_US";

    if (!Platform.isWindows) {
      locale = await Devicelocale.currentLocale;
    }

    debugPrint("$tag local = $locale");
    if (locale != null && locale.startsWith("zh_")) {
      _launchURL(Constants.giteePrivacyPolicyURL);
    } else {
      _launchURL(Constants.githubPrivacyPolicyURL);
    }
  }

  Future<void> _launchHelpImproveTranslate() async {
    String? locale = "en_US";

    if (!Platform.isWindows) {
      locale = await Devicelocale.currentLocale;
    }

    debugPrint("$tag local = $locale");
    if (locale != null && locale.startsWith("zh_")) {
      _launchURL(Constants.giteeHelpImproveTranslateURL);
    } else {
      _launchURL(Constants.githubHelpImproveTranslateURL);
    }
  }

  Future<void> _launchThanks() async {
    String? locale = "en_US";

    if (!Platform.isWindows) {
      locale = await Devicelocale.currentLocale;
    }

    debugPrint("$tag local = $locale");
    if (locale != null && locale.startsWith("zh_")) {
      _launchURL(Constants.giteeThanksURL);
    } else {
      _launchURL(Constants.githubThanksURL);
    }
  }

  void _showVersionInfo(BuildContext context, String version) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _VersionDialog(
        version: version,
      ),
    );
  }
}

class _VersionDialog extends StatelessWidget {
  const _VersionDialog({
    Key? key,
    required this.version,
  }) : super(key: key);

  final String version;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        S.of(context).appName,
        style: const TextStyle(color: AppTheme.dialogTitleColor),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text("${S.of(context).version}: $version"),
          const SizedBox(height: AppTheme.sizedBoxHeight),
          const SizedBox(height: AppTheme.sizedBoxHeight),
          Text(
            S.of(context).copyright,
            style: TextStyle(
              fontSize: AppTheme.copyrightFontSize,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          child: Text(S.of(context).more),
          onPressed: () => _showFlutterVersionInfo(context),
        ),
        TextButton(
          child: Text(S.of(context).ok),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  void _showFlutterVersionInfo(BuildContext context) {
    Navigator.of(context).pop();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _flutterVersionDialog(context),
    );
  }

  AlertDialog _flutterVersionDialog(BuildContext context) {
    return AlertDialog(
      title: Text(
        S.of(context).more,
        style: const TextStyle(color: AppTheme.dialogTitleColor),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            flutterVersion
                .toString()
                .replaceAll('{', '')
                .replaceAll('}', '')
                .replaceAll(', ', '\n'),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          child: Text(S.of(context).ok),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
