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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info/package_info.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/style/app_theme.dart';
import 'package:sanmill/style/colors.dart';
import 'package:url_launcher/url_launcher.dart';

import 'license_page.dart';
import 'list_item_divider.dart';

class AboutPage extends StatefulWidget {
  @override
  _AboutPageState createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = "";

  @override
  void initState() {
    _loadVersionInfo();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    String mode = "";

    final TextStyle itemStyle = TextStyle(color: UIColors.crusoeColor);

    if (kDebugMode) {
      mode = "- debug";
    } else if (kProfileMode) {
      mode = "- profile";
    } else if (kReleaseMode) {
      mode = "";
    } else {
      mode = "-test";
    }

    return Scaffold(
      backgroundColor: UIColors.lightBackgroundColor,
      appBar: AppBar(
          centerTitle: true,
          title: Text(S.of(context).about + " " + S.of(context).appName)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            ListTile(
              title: Text(S.of(context).versionInfo,
                  style: AppTheme.switchListTileTitleStyle),
              subtitle: Text("Sanmill " + "$_version" + " " + mode,
                  style: TextStyle(color: UIColors.secondaryColor)),
              onTap: _showVersionInfo,
            ),
            ListItemDivider(),
            /*
            ListTile(
              title:
                  Text(S.of(context).viewInGooglePlayStore, style: AppTheme.switchListTileTitleStyle),
              onTap: () => _launchURL(
                  'https://play.google.com/store/apps/details?id=com.calcitem.sanmill'),
            ),
            ListItemDivider(),
             */
            ListTile(
              title: Text(S.of(context).feedback,
                  style: AppTheme.switchListTileTitleStyle),
              onTap: () =>
                  _launchURL('https://github.com/calcitem/Sanmill/issues'),
            ),
            ListItemDivider(),
            ListTile(
                title: Text(S.of(context).license,
                    style: AppTheme.switchListTileTitleStyle),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LicenseAgreementPage(),
                    ),
                  );
                }),
            ListItemDivider(),
            ListTile(
              title: Text(S.of(context).sourceCode,
                  style: AppTheme.switchListTileTitleStyle),
              onTap: () => _launchURL('https://github.com/calcitem/Sanmill'),
            ),
            ListItemDivider(),
            ListTile(
              title: Text(S.of(context).privacyPolicy,
                  style: AppTheme.switchListTileTitleStyle),
              onTap: () => _launchURL(
                  'https://github.com/calcitem/Sanmill/wiki/privacy_policy'),
            ),
            ListItemDivider(),
            ListTile(
              title: Text(S.of(context).thirdPartyNotices,
                  style: AppTheme.switchListTileTitleStyle),
              onTap: () => _launchURL(
                  'https://github.com/calcitem/Sanmill/wiki/third-party_notices'),
            ),
            ListItemDivider(),
            ListTile(
              title: Text(S.of(context).thanks,
                  style: AppTheme.switchListTileTitleStyle),
              onTap: () =>
                  _launchURL('https://github.com/calcitem/Sanmill/wiki/thanks'),
            ),
            ListItemDivider(),
          ],
        ),
      ),
    );
  }

  _loadVersionInfo() async {
    if (Platform.isWindows) {
      setState(() {
        _version = 'Unknown version';
      });
    } else {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _version = '${packageInfo.version} (${packageInfo.buildNumber})';
      });
    }
  }

  _launchURL(String url) async {
    await launch(url);
  }

  _showVersionInfo() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(S.of(context).appName,
            style: TextStyle(color: UIColors.primaryColor)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(S.of(context).version + ": $_version",
                style: TextStyle(fontFamily: '')),
            AppTheme.sizedBox,
            AppTheme.sizedBox,
            Text(S.of(context).copyright,
                style: TextStyle(fontFamily: '', fontSize: 12)),
          ],
        ),
        actions: <Widget>[
          TextButton(
              child: Text(S.of(context).ok),
              onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}
