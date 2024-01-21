// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
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

import 'package:catcher/core/catcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../custom_drawer/custom_drawer.dart';
import '../generated/flutter_version.dart';
import '../generated/intl/l10n.dart';
import '../shared/config/constants.dart';
import '../shared/services/git_info.dart';
import '../shared/services/url.dart';
import '../shared/themes/app_theme.dart';
import '../shared/widgets/custom_spacer.dart';
import '../shared/widgets/settings/settings.dart';
import 'license_agreement_page.dart';

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
    final List<Widget> settingsItems = <Widget>[
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
                appVersion: version,
              ),
            ),
          );
        },
      ),
      SettingsListTile(
        titleString: S.of(context).feedback,
        onTap: () => launchURL(context, Constants.issuesURL),
      ),
      if (kIsWeb ||
          Platform.isAndroid ||
          Platform.isWindows ||
          Platform.isLinux)
        SettingsListTile(
          titleString: S.of(context).eula,
          onTap: () => launchURL(context, Constants.endUserLicenseAgreementUrl),
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
        onTap: () => launchURL(context, Constants.repositoryUrl),
      ),
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
        SettingsListTile(
          titleString: S.of(context).privacyPolicy,
          onTap: () => launchURL(context, Constants.privacyPolicyUrl),
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
        onTap: () {
          final String locale = Localizations.localeOf(context).languageCode;
          final UrlHelper url =
              Constants.helpImproveTranslateURL.fromSubPath(locale);
          launchURL(context, url);
        },
      ),
      SettingsListTile(
        titleString: S.of(context).thanks,
        onTap: () => launchURL(context, Constants.thanksURL),
      ),
    ];

    return BlockSemantics(
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: AppTheme.aboutPageBackgroundColor,
        appBar: AppBar(
          leading: CustomDrawerIcon.of(context)?.drawerIcon,
          title: Text(
            S.of(context).about,
            style: AppTheme.appBarTheme.titleTextStyle,
          ),
        ),
        body: ListView.separated(
          itemBuilder: (_, int index) => settingsItems[index],
          separatorBuilder: (_, __) => const Divider(),
          itemCount: settingsItems.length,
        ),
      ),
    );
  }
}

class _VersionDialog extends StatelessWidget {
  const _VersionDialog({
    required this.appVersion,
  });

  final String appVersion;

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
          Text(
            S.of(context).version(appVersion),
            style: TextStyle(
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
          ),
          const CustomSpacer(),
          FutureBuilder<GitInfo>(
            future: gitInfo,
            builder: (BuildContext context, AsyncSnapshot<GitInfo> snapshot) {
              if (snapshot.hasData) {
                return Column(
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Branch: ${snapshot.data!.branch}',
                        style: TextStyle(
                            fontSize: AppTheme.textScaler
                                .scale(AppTheme.defaultFontSize)),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Revision: ${snapshot.data!.revision}',
                        style: TextStyle(
                            fontSize: AppTheme.textScaler
                                .scale(AppTheme.defaultFontSize)),
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
            style: TextStyle(
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
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
            style: TextStyle(
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
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
  String formattedFlutterVersion = "";
  int tapCount = 0;
  DateTime startTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    formattedFlutterVersion = flutterVersion.toString();
    formattedFlutterVersion = formattedFlutterVersion
        .replaceAll("{", "")
        .replaceAll("}", "")
        .replaceAll(", ", "\n");
    formattedFlutterVersion = formattedFlutterVersion.substring(
        0, formattedFlutterVersion.indexOf("flutterRoot"));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        S.of(context).more,
        style: AppTheme.dialogTitleTextStyle,
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
                  Catcher.sendTestException();
                }
              });
            },
            child: Text(
              formattedFlutterVersion,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          child: Text(
            S.of(context).ok,
            style: TextStyle(
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
