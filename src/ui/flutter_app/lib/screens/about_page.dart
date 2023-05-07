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

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../generated/flutter_version.dart';
import '../generated/intl/l10n.dart';
import '../services/database/database.dart';
import '../services/environment_config/environment_config.dart';
import '../services/git_info/git_info.dart';
import '../shared/constants.dart';
import '../shared/custom_drawer/custom_drawer.dart';
import '../shared/custom_spacer.dart';
import '../shared/settings/settings.dart';
import '../shared/theme/app_theme.dart';
import 'license_page.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  String? get mode {
    if (kDebugMode) {
      return "- debug";
    } else if (kProfileMode) {
      return "- profile";
    } else if (kReleaseMode) {
      return "";
    } else {
      return "-test";
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[
      FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (_, AsyncSnapshot<PackageInfo> data) {
          final String version;
          if (!data.hasData) {
            return Container();
          } else {
            final PackageInfo packageInfo = data.data!;
            if (kIsWeb ||
                Platform.isWindows ||
                Platform.isLinux ||
                Platform.isMacOS) {
              version = packageInfo.version;
            } else {
              version = "${packageInfo.version} (${packageInfo.buildNumber})";
            }
          }
          return SettingsListTile(
            titleString: S.of(context).versionInfo,
            subtitleString: "${Constants.projectName} $version $mode",
            onTap: () => showDialog(
              context: context,
              barrierDismissible: true,
              builder: (_) => _VersionDialog(
                version: version,
              ),
            ),
          );
        },
      ),
      SettingsListTile(
        titleString: S.of(context).feedback,
        onTap: () => _launchURL(context, Constants.issuesURL),
      ),
      if (kIsWeb ||
          Platform.isAndroid ||
          Platform.isWindows ||
          Platform.isLinux)
        SettingsListTile(
          titleString: S.of(context).eula,
          onTap: () => _launchURL(context, Constants.eulaURL),
        ),
      SettingsListTile(
        titleString: S.of(context).license,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute<LicenseAgreementPage>(
              builder: (BuildContext context) => const LicenseAgreementPage(),
            ),
          );
        },
      ),
      SettingsListTile(
        titleString: S.of(context).sourceCode,
        onTap: () => _launchURL(context, Constants.repoURL),
      ),
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
        SettingsListTile(
          titleString: S.of(context).privacyPolicy,
          onTap: () => _launchURL(context, Constants.privacyPolicyURL),
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
        onTap: () => _launchURL(context, Constants.helpImproveTranslateURL),
      ),
      SettingsListTile(
        titleString: S.of(context).thanks,
        onTap: () => _launchURL(context, Constants.thanksURL),
      ),
    ];

    return BlockSemantics(
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: AppTheme.aboutPageBackgroundColor,
        appBar: AppBar(
          leading: DrawerIcon.of(context)?.icon,
          title: Text(S.of(context).about),
        ),
        body: ListView.separated(
          itemBuilder: (_, int index) => children[index],
          separatorBuilder: (_, __) => const Divider(),
          itemCount: children.length,
        ),
      ),
    );
  }

  Future<void> _launchURL(BuildContext context, URL url) async {
    if (EnvironmentConfig.test) {
      return;
    }

    final String s =
        Localizations.localeOf(context).languageCode.startsWith("zh_")
            ? url.url.substring("https://".length)
            : url.urlZh.substring("https://".length);
    final String authority = s.substring(0, s.indexOf('/'));
    final String unencodedPath = s.substring(s.indexOf('/'));
    final Uri uri = Uri.https(authority, unencodedPath);

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _VersionDialog extends StatelessWidget {
  const _VersionDialog({
    required this.version,
  });

  final String version;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        S.of(context).appName,
        style: AppTheme.dialogTitleTextStyle,
        textScaleFactor: DB().displaySettings.fontScale,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            S.of(context).version(version),
            textScaleFactor: DB().displaySettings.fontScale,
          ),
          const CustomSpacer(),
          FutureBuilder<GitInformation>(
            future: gitInfo,
            builder:
                (BuildContext context, AsyncSnapshot<GitInformation> snapshot) {
              if (snapshot.hasData) {
                return Column(
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Branch: ${snapshot.data!.branch}',
                        textScaleFactor: DB().displaySettings.fontScale,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Revision: ${snapshot.data!.revision}',
                        textScaleFactor: DB().displaySettings.fontScale,
                      ),
                    ),
                  ],
                );
              } else {
                return const SizedBox.shrink();
              }
            },
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          child: Text(
            S.of(context).more,
            textScaleFactor: DB().displaySettings.fontScale,
          ),
          onPressed: () {
            Navigator.pop(context);

            showDialog(
              context: context,
              barrierDismissible: true,
              builder: (_) => const FlutterVersionAlert(),
            );
          },
        ),
        TextButton(
          child: Text(
            S.of(context).ok,
            textScaleFactor: DB().displaySettings.fontScale,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

class FlutterVersionAlert extends StatefulWidget {
  const FlutterVersionAlert({super.key});

  @override
  FlutterVersionAlertState createState() => FlutterVersionAlertState();
}

class FlutterVersionAlertState extends State<FlutterVersionAlert> {
  String flutterVersionStr = "";
  int tapCount = 0;
  DateTime startTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    flutterVersionStr = flutterVersion.toString();
    flutterVersionStr = flutterVersionStr
        .replaceAll("{", "")
        .replaceAll("}", "")
        .replaceAll(", ", "\n");
    flutterVersionStr = flutterVersionStr.substring(
        0, flutterVersionStr.indexOf("flutterRoot"));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        S.of(context).more,
        style: AppTheme.dialogTitleTextStyle,
        textScaleFactor: DB().displaySettings.fontScale,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          GestureDetector(
            onTap: () {
              setState(() {
                tapCount++;
                if (tapCount >= 10 &&
                    DateTime.now().difference(startTime).inSeconds <= 10) {
                  // Used to test whether the Catcher is working properly.
                  assert(false);
                }
              });
            },
            child: Text(
              flutterVersionStr,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          child: Text(
            S.of(context).ok,
            textScaleFactor: DB().displaySettings.fontScale,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
