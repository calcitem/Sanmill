import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/generated/oss_licenses.dart';
import 'package:url_launcher/url_launcher.dart';

class FlutterLicense extends LicenseEntry {
  final List<String> packages;
  final List<LicenseParagraph> paragraphs;

  FlutterLicense(this.packages, this.paragraphs);
}

/// display all used packages and their license
class OssLicensesPage extends StatelessWidget {
  static Future<List<String>> loadLicenses() async {
    Stream<LicenseEntry> licenses() async* {
      yield FlutterLicense([
        'Sound Effects'
      ], [
        LicenseParagraph(
            'CC-0\nhttps://freesound.org/people/unfa/sounds/243749/', 0)
      ]);
    }

    LicenseRegistry.addLicense(licenses);

    // merging non-dart based dependency list using LicenseRegistry.
    final ossKeys = ossLicenses.keys.toList();
    final lm = <String, List<String>>{};
    await for (var l in LicenseRegistry.licenses) {
      for (var p in l.packages) {
        if (!ossKeys.contains(p)) {
          final lp = lm.putIfAbsent(p, () => []);
          lp.addAll(l.paragraphs.map((p) => p.text));
          ossKeys.add(p);
        }
      }
    }
    for (var key in lm.keys) {
      ossLicenses[key] = {'license': lm[key]!.join('\n')};
    }
    return ossKeys..sort();
  }

  static final _licenses = loadLicenses();

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).ossLicenses),
      ),
      body: FutureBuilder<List<String>>(
          future: _licenses,
          builder: (context, snapshot) => ListView.separated(
              padding: const EdgeInsets.all(0),
              itemCount: snapshot.data?.length ?? 0,
              itemBuilder: (context, index) {
                final key = snapshot.data![index];
                final ossl = ossLicenses[key];
                final version = ossl['version'];
                final desc = ossl['description'];
                return ListTile(
                    title: Text('$key ${version ?? ''}'),
                    subtitle: desc != null ? Text(desc) : null,
                    trailing: Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) =>
                            MiscOssLicenseSingle(name: key, json: ossl))));
              },
              separatorBuilder: (context, index) => const Divider())));
}

class MiscOssLicenseSingle extends StatelessWidget {
  final String name;
  final Map<String, dynamic> json;

  String get version => json['version'] == null ? "" : json['version'];
  String? get description => json['description'];
  String get licenseText => json['license'];
  String? get homepage => json['homepage'];

  MiscOssLicenseSingle({required this.name, required this.json});

  String _bodyText() => licenseText.split('\n').map((line) {
        if (line.startsWith('//')) line = line.substring(2);
        line = line.trim();
        return line;
      }).join('\n');

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('$name $version')),
        body: Container(
            color: Theme.of(context).canvasColor,
            child: ListView(children: <Widget>[
              if (description != null)
                Padding(
                    padding: const EdgeInsets.only(
                        top: 12.0, left: 12.0, right: 12.0),
                    child: Text(description!,
                        style: Theme.of(context)
                            .textTheme
                            .bodyText2!
                            .copyWith(fontWeight: FontWeight.bold))),
              if (homepage != null)
                Padding(
                    padding: const EdgeInsets.only(
                        top: 12.0, left: 12.0, right: 12.0),
                    child: InkWell(
                      child: Text(homepage!,
                          style: const TextStyle(
                              color: Colors.blue,
                              decoration: TextDecoration.underline)),
                      onTap: () => launch(homepage!),
                    )),
              if (description != null || homepage != null) const Divider(),
              Padding(
                padding:
                    const EdgeInsets.only(top: 12.0, left: 12.0, right: 12.0),
                child: Text(_bodyText(),
                    style: Theme.of(context).textTheme.bodyText2),
              ),
            ])),
      );
}
