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
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/style/app_theme.dart';
import 'package:sanmill/widgets/settings_list_tile.dart';
import 'package:url_launcher/url_launcher.dart';

import 'license_page.dart';
import 'list_item_divider.dart';
import 'oss_license_page.dart';

class AboutPage extends StatefulWidget {
  @override
  _AboutPageState createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = "";
  final String tag = "[about] ";

  @override
  void initState() {
    _loadVersionInfo();
    super.initState();
  }

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
    String mode = getMode();

    return Scaffold(
      backgroundColor: AppTheme.aboutPageBackgroundColor,
      appBar: AppBar(
          centerTitle: true,
          title: Text(S.of(context).about + " " + S.of(context).appName)),
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
      SettingsListTile(
        context: context,
        titleString: S.of(context).versionInfo,
        subtitleString: "Sanmill " + "$_version" + " " + mode,
        onTap: _showVersionInfo,
      ),
      ListItemDivider(),
      SettingsListTile(
        context: context,
        titleString: S.of(context).feedback,
        onTap: () {
          _launchFeedback();
        },
      ),
      ListItemDivider(),
      SettingsListTile(
        context: context,
        titleString: S.of(context).eula,
        onTap: () {
          _launchEULA();
        },
      ),
      ListItemDivider(),
      SettingsListTile(
        context: context,
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
      ListItemDivider(),
      SettingsListTile(
        context: context,
        titleString: S.of(context).sourceCode,
        onTap: () {
          _launchSourceCode();
        },
      ),
      ListItemDivider(),
      SettingsListTile(
        context: context,
        titleString: S.of(context).privacyPolicy,
        onTap: () {
          _launchPrivacyPolicy();
        },
      ),
      ListItemDivider(),
      SettingsListTile(
        context: context,
        titleString: S.of(context).ossLicenses,
        onTap: () {
          _launchThirdPartyNotices();
        },
      ),
      ListItemDivider(),
      SettingsListTile(
        context: context,
        titleString: S.of(context).thanks,
        onTap: () {
          _launchThanks();
        },
      ),
      ListItemDivider(),
    ];
  }

  _loadVersionInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();

    if (Platform.isWindows) {
      setState(() {
        _version = '${packageInfo.version}'; // TODO
      });
    } else {
      setState(() {
        _version = '${packageInfo.version} (${packageInfo.buildNumber})';
      });
    }
  }

  _launchURL(String url) async {
    await launch(url);
  }

  _launchFeedback() async {
    String? locale = "en_US";

    if (!Platform.isWindows) {
      locale = await Devicelocale.currentLocale;
    }

    print("$tag local = $locale");
    if (locale != null && locale.startsWith("zh_")) {
      _launchURL('https://gitee.com/calcitem/Sanmill/issues');
    } else {
      _launchURL('https://github.com/calcitem/Sanmill/issues');
    }
  }

  _launchEULA() async {
    String? locale = "en_US";

    if (!Platform.isWindows) {
      locale = await Devicelocale.currentLocale;
    }

    print("$tag local = $locale");
    if (locale != null && locale.startsWith("zh_")) {
      _launchURL('https://gitee.com/calcitem/Sanmill/wikis/EULA_zh');
    } else {
      _launchURL('https://github.com/calcitem/Sanmill/wiki/EULA');
    }
  }

  _launchSourceCode() async {
    String? locale = "en_US";

    if (!Platform.isWindows) {
      locale = await Devicelocale.currentLocale;
    }

    print("$tag local = $locale");
    if (locale != null && locale.startsWith("zh_")) {
      _launchURL('https://gitee.com/calcitem/Sanmill');
    } else {
      _launchURL('https://github.com/calcitem/Sanmill');
    }
  }

  _launchThirdPartyNotices() async {
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OssLicensesPage(),
        ));
    /*
    String? locale = "en_US";

    if (!Platform.isWindows) {
      locale = await Devicelocale.currentLocale;
    }

    print("$tag local = $locale");
    if (locale != null && locale.startsWith("zh_")) {
      _launchURL(
          'https://gitee.com/calcitem/Sanmill/wikis/third-party_notices');
    } else {
      _launchURL(
          'https://github.com/calcitem/Sanmill/wiki/third-party_notices');
    }
    */
  }

  _launchPrivacyPolicy() async {
    String? locale = "en_US";

    if (!Platform.isWindows) {
      locale = await Devicelocale.currentLocale;
    }

    print("$tag local = $locale");
    if (locale != null && locale.startsWith("zh_")) {
      _launchURL('https://gitee.com/calcitem/Sanmill/wikis/privacy_policy_zh');
    } else {
      _launchURL('https://github.com/calcitem/Sanmill/wiki/privacy_policy');
    }
  }

  _launchThanks() async {
    String? locale = "en_US";

    if (!Platform.isWindows) {
      locale = await Devicelocale.currentLocale;
    }

    print("$tag local = $locale");
    if (locale != null && locale.startsWith("zh_")) {
      _launchURL('https://gitee.com/calcitem/Sanmill/wikis/thanks');
    } else {
      _launchURL('https://github.com/calcitem/Sanmill/wiki/thanks');
    }
  }

  _showVersionInfo() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => versionDialog(context),
    );
  }

  AlertDialog versionDialog(BuildContext context) {
    return AlertDialog(
      title: Text(
        S.of(context).appName,
        style: TextStyle(color: AppTheme.dialogTitleColor),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(S.of(context).version + ": $_version"),
          SizedBox(height: AppTheme.sizedBoxHeight),
          SizedBox(height: AppTheme.sizedBoxHeight),
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
          onPressed: () => _showFlutterVersionInfo(),
        ),
        TextButton(
          child: Text(S.of(context).ok),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  _showFlutterVersionInfo() {
    Navigator.of(context).pop();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => flutterVersionDialog(context),
    );
  }

  AlertDialog flutterVersionDialog(BuildContext context) {
    return AlertDialog(
      title: Text(
        S.of(context).more,
        style: TextStyle(color: AppTheme.dialogTitleColor),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            "${flutterVersion.toString().replaceAll('{', '').replaceAll('}', '').replaceAll(', ', '\n')}",
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
