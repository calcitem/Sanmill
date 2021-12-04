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
import 'package:sanmill/generated/flutter_version.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/screens/license_page.dart';
import 'package:sanmill/services/environment_config.dart';
import 'package:sanmill/shared/constants.dart';
import 'package:sanmill/shared/custom_drawer/custom_drawer.dart';
import 'package:sanmill/shared/custom_spacer.dart';
import 'package:sanmill/shared/settings/settings.dart';
import 'package:sanmill/shared/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({Key? key}) : super(key: key);

  static const String _tag = "[about] ";

  String? get mode {
    if (kDebugMode) {
      return "- debug";
    } else if (kProfileMode) {
      return "- profile";
    } else if (kReleaseMode) {
      return null;
    } else {
      return "-test";
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> _children = [
      FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (_, data) {
          final String _version;
          if (!data.hasData) {
            return Container();
          } else {
            final PackageInfo packageInfo = data.data!;
            if (Platform.isWindows) {
              _version = packageInfo.version; // TODO

            } else {
              _version = "${packageInfo.version} (${packageInfo.buildNumber})";
            }
          }
          return SettingsListTile(
            titleString: S.of(context).versionInfo,
            subtitleString: "${Constants.projectName} $_version $mode",
            onTap: () => _showVersionInfo(context, _version),
          );
        },
      ),
      SettingsListTile(
        titleString: S.of(context).feedback,
        onTap: _launchFeedback,
      ),
      SettingsListTile(
        titleString: S.of(context).eula,
        onTap: _launchEULA,
      ),
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
      SettingsListTile(
        titleString: S.of(context).sourceCode,
        onTap: _launchSourceCode,
      ),
      SettingsListTile(
        titleString: S.of(context).privacyPolicy,
        onTap: _launchPrivacyPolicy,
      ),
      SettingsListTile(
        titleString: S.of(context).ossLicenses,
        onTap: () => showLicensePage(
          context: context,
          applicationName: S.of(context).appName,
        ),
      ),
      SettingsListTile(
        titleString: S.of(context).helpImproveTranslate,
        onTap: _launchHelpImproveTranslate,
      ),
      SettingsListTile(
        titleString: S.of(context).thanks,
        onTap: _launchThanks,
      ),
    ];

    return Scaffold(
      backgroundColor: AppTheme.aboutPageBackgroundColor,
      appBar: AppBar(
        leading: DrawerIcon.of(context)?.icon,
        title: Text("${S.of(context).about} ${S.of(context).appName}"),
      ),
      body: ListView.separated(
        itemBuilder: (_, index) => _children[index],
        separatorBuilder: (_, __) => const Divider(),
        itemCount: _children.length,
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    if (!EnvironmentConfig.monkeyTest) {
      await launch(url);
    }
  }

  Future<void> _launchFeedback() async {
    String? locale = "en_US";

    locale = await Devicelocale.currentLocale;

    debugPrint("$_tag local = $locale");
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

    debugPrint("$_tag local = $locale");
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

    debugPrint("$_tag local = $locale");
    if (locale != null && locale.startsWith("zh_")) {
      _launchURL(Constants.giteeSourceCodeURL);
    } else {
      _launchURL(Constants.githubSourceCodeURL);
    }
  }

  Future<void> _launchPrivacyPolicy() async {
    String? locale = "en_US";

    if (!Platform.isWindows) {
      locale = await Devicelocale.currentLocale;
    }

    debugPrint("$_tag local = $locale");
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

    debugPrint("$_tag local = $locale");
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

    debugPrint("$_tag local = $locale");
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
        style: AppTheme.dialogTitleTextStyle,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(S.of(context).version(version)),
          const CustomSpacer(),
          Text(
            S.of(context).copyright,
            style: AppTheme.copyrightTextStyle,
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
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  void _showFlutterVersionInfo(BuildContext context) {
    Navigator.pop(context);

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
        style: AppTheme.dialogTitleTextStyle,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            flutterVersion
                .toString()
                .replaceAll("{", "")
                .replaceAll("}", "")
                .replaceAll(", ", "\n"),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          child: Text(S.of(context).ok),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
