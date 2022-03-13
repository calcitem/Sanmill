// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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
import 'package:sanmill/generated/flutter_version.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/screens/license_page.dart';
import 'package:sanmill/services/environment_config.dart';
import 'package:sanmill/services/git_info.dart';
import 'package:sanmill/shared/constants.dart';
import 'package:sanmill/shared/custom_drawer/custom_drawer.dart';
import 'package:sanmill/shared/custom_spacer.dart';
import 'package:sanmill/shared/settings/settings.dart';
import 'package:sanmill/shared/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({Key? key}) : super(key: key);

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
            onTap: () => showDialog(
              context: context,
              barrierDismissible: true,
              builder: (_) => _VersionDialog(
                version: _version,
              ),
            ),
          );
        },
      ),
      SettingsListTile(
        titleString: S.of(context).feedback,
        onTap: () => _launchURL(context, Constants.issuesURL),
      ),
      SettingsListTile(
        titleString: S.of(context).eula,
        onTap: () => _launchURL(context, Constants.eulaURL),
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
        onTap: () => _launchURL(context, Constants.repoURL),
      ),
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

    return Scaffold(
      backgroundColor: AppTheme.aboutPageBackgroundColor,
      appBar: AppBar(
        leading: DrawerIcon.of(context)?.icon,
        title: Text(S.of(context).about),
      ),
      body: ListView.separated(
        itemBuilder: (_, index) => _children[index],
        separatorBuilder: (_, __) => const Divider(),
        itemCount: _children.length,
      ),
    );
  }

  Future<void> _launchURL(BuildContext context, URL url) async {
    if (!EnvironmentConfig.test) {
      if (Localizations.localeOf(context).languageCode.startsWith("zh_")) {
        await launch(url.url);
      } else {
        await launch(url.urlZh);
      }
    }
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
          FutureBuilder<GitInformation>(
            future: gitInfo,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Branch: ${snapshot.data!.branch}'),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Revision: ${snapshot.data!.revision}'),
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
          child: Text(S.of(context).more),
          onPressed: () {
            Navigator.pop(context);

            showDialog(
              context: context,
              barrierDismissible: true,
              builder: (_) => const _FLutterVersionAlert(),
            );
          },
        ),
        TextButton(
          child: Text(S.of(context).ok),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

class _FLutterVersionAlert extends StatelessWidget {
  const _FLutterVersionAlert({Key? key}) : super(key: key);

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
