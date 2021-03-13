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
import 'package:sanmill/style/colors.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatefulWidget {
  @override
  _AboutPageState createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = "";

  @override
  void initState() {
    loadVersionInfo();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    String mode = "";

    final TextStyle headerStyle =
        TextStyle(color: UIColors.crusoeColor, fontSize: 20.0);
    final TextStyle itemStyle = TextStyle(color: UIColors.crusoeColor);
    final cardColor = UIColors.floralWhiteColor;

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
          title: Text(S.of(context).about + S.of(context).appName)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            ListTile(
              title: Text(S.of(context).versionInfo, style: itemStyle),
              subtitle: Text("Sanmill " + "$_version" + " " + mode,
                  style: TextStyle(color: UIColors.secondaryColor)),
              trailing:
                  Row(mainAxisSize: MainAxisSize.min, children: <Widget>[]),
              onTap: showVersionInfo,
            ),
            _buildDivider(),
            /*
            ListTile(
              title:
                  Text(S.of(context).viewInGooglePlayStore, style: itemStyle),
              trailing:
                  Row(mainAxisSize: MainAxisSize.min, children: <Widget>[]),
              onTap: () => _launchURL(
                  'https://play.google.com/store/apps/details?id=com.calcitem.sanmill'),
            ),
            _buildDivider(),
             */
            ListTile(
              title: Text(S.of(context).feedback, style: itemStyle),
              trailing:
                  Row(mainAxisSize: MainAxisSize.min, children: <Widget>[]),
              onTap: () =>
                  _launchURL('https://github.com/calcitem/Sanmill/issues'),
            ),
            _buildDivider(),
            ListTile(
              title: Text(S.of(context).license, style: itemStyle),
              trailing:
                  Row(mainAxisSize: MainAxisSize.min, children: <Widget>[]),
              onTap: () =>
                  _launchURL('https://www.gnu.org/licenses/gpl-3.0.html'),
            ),
            _buildDivider(),
            ListTile(
              title: Text(S.of(context).sourceCode, style: itemStyle),
              trailing:
                  Row(mainAxisSize: MainAxisSize.min, children: <Widget>[]),
              onTap: () => _launchURL('https://github.com/calcitem/Sanmill'),
            ),
            _buildDivider(),
            ListTile(
              title: Text(S.of(context).privacyPolicy, style: itemStyle),
              trailing:
                  Row(mainAxisSize: MainAxisSize.min, children: <Widget>[]),
              onTap: () => _launchURL(
                  'https://github.com/calcitem/Sanmill/wiki/privacy_policy'),
            ),
            _buildDivider(),
            ListTile(
              title: Text(S.of(context).thirdPartyNotices, style: itemStyle),
              trailing:
                  Row(mainAxisSize: MainAxisSize.min, children: <Widget>[]),
              onTap: () => _launchURL(
                  'https://github.com/calcitem/Sanmill/wiki/third-party_notices'),
            ),
            _buildDivider(),
            ListTile(
              title: Text(S.of(context).thanks, style: itemStyle),
              trailing:
                  Row(mainAxisSize: MainAxisSize.min, children: <Widget>[]),
              onTap: () =>
                  _launchURL('https://github.com/calcitem/Sanmill/wiki/thanks'),
            ),
            _buildDivider(),
          ],
        ),
      ),
    );
  }

  Container _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      width: double.infinity,
      height: 1.0,
      color: UIColors.lightLineColor,
    );
  }

  loadVersionInfo() async {
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
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw 'Could not launch $url';
    }
  }

  showVersionInfo() {
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
            SizedBox(height: 5),
            Text(S.of(context).version + ": $_version",
                style: TextStyle(fontFamily: '')),
            SizedBox(height: 15),
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
