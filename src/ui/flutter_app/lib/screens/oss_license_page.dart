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

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/generated/oss_licenses.dart';
import 'package:url_launcher/url_launcher.dart';

// TODO: use flutters build in viewLicense function
class FlutterLicense extends LicenseEntry {
  @override
  final List<String> packages;
  @override
  final List<LicenseParagraph> paragraphs;

  FlutterLicense(this.packages, this.paragraphs);
}

/// display all used packages and their license
class OssLicensesPage extends StatelessWidget {
  static Future<List<String>> loadLicenses() async {
    Stream<LicenseEntry> licenses() async* {
      yield FlutterLicense(
        ['Sound Effects'],
        [
          const LicenseParagraph(
            'CC-0\nhttps://freesound.org/people/unfa/sounds/243749/',
            0,
          ),
        ],
      );
    }

    LicenseRegistry.addLicense(licenses);

    // merging non-dart based dependency list using LicenseRegistry.
    final ossKeys = ossLicenses.keys.toList();
    final lm = <String, List<String>>{};
    await for (final l in LicenseRegistry.licenses) {
      for (final p in l.packages) {
        if (!ossKeys.contains(p)) {
          final lp = lm.putIfAbsent(p, () => []);
          lp.addAll(l.paragraphs.map((p) => p.text));
          ossKeys.add(p);
        }
      }
    }
    for (final key in lm.keys) {
      ossLicenses[key] = {'license': lm[key]!.join('\n')};
    }
    return ossKeys..sort();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(S.of(context).ossLicenses),
        ),
        body: FutureBuilder<List<String>>(
          future: loadLicenses(),
          builder: (context, snapshot) => ListView.separated(
            itemCount: snapshot.data?.length ?? 0,
            itemBuilder: (context, index) {
              final key = snapshot.data![index];
              final ossl = ossLicenses[key] as Map<String, dynamic>;
              final version = ossl['version'];
              final desc = ossl['description'] as String?;
              return ListTile(
                title: Text('$key $version'),
                subtitle: desc != null ? Text(desc) : null,
                trailing: const Icon(FluentIcons.chevron_right_24_regular),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MiscOssLicenseSingle(name: key, json: ossl),
                  ),
                ),
              );
            },
            separatorBuilder: (context, index) => const Divider(),
          ),
        ),
      );
}

class MiscOssLicenseSingle extends StatelessWidget {
  final String name;
  final Map<String, dynamic> json;

  const MiscOssLicenseSingle({
    required this.name,
    required this.json,
  });

  String get version => json['version'] as String? ?? "";
  String? get description => json['description'] as String?;
  String get licenseText => json['license'] as String;
  String? get homepage => json['homepage'] as String?;

  String get _bodyText => licenseText.split('\n').map((line) {
        if (line.startsWith('//')) line = line.substring(2);
        return line.trim();
      }).join('\n');

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('$name $version')),
        backgroundColor: Theme.of(context).canvasColor,
        body: ListView(
          children: <Widget>[
            if (description != null)
              Padding(
                padding: const EdgeInsets.only(
                  top: 12.0,
                  left: 12.0,
                  right: 12.0,
                ),
                child: Text(
                  description!,
                  style: Theme.of(context)
                      .textTheme
                      .bodyText2!
                      .copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            if (homepage != null)
              Padding(
                padding: const EdgeInsets.only(
                  top: 12.0,
                  left: 12.0,
                  right: 12.0,
                ),
                child: InkWell(
                  child: Text(
                    homepage!,
                    style: const TextStyle(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  onTap: () => launch(homepage!),
                ),
              ),
            if (description != null || homepage != null) const Divider(),
            Padding(
              padding: const EdgeInsets.only(
                top: 12.0,
                left: 12.0,
                right: 12.0,
              ),
              child: Text(
                _bodyText,
                style: Theme.of(context).textTheme.bodyText2,
              ),
            ),
          ],
        ),
      );
}
