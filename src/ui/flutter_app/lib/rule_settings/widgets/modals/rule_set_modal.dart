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

// DISCLAIMER:
// The map displayed in this application is intended solely for illustrative purposes.
// It does not represent any official stance on territorial boundaries or disputes.
// The developers of this application make no warranty as to the accuracy or completeness
// of the geographical information presented herein.

part of 'package:sanmill/rule_settings/widgets/rule_settings_page.dart';

// A modal widget to select a rule set for the game.
class _RuleSetModal extends StatefulWidget {
  const _RuleSetModal({
    required this.ruleSet,
    required this.onChanged,
  });

  final RuleSet ruleSet;
  final Function(RuleSet?)? onChanged;

  @override
  _RuleSetModalState createState() => _RuleSetModalState();
}

class _RuleSetModalState extends State<_RuleSetModal> {
  late RuleSet _selectedRuleSet;
  final Map<String, RuleSet> _countryCodeToRuleSet = <String, RuleSet>{};
  final Map<String, Color> _countryCodeToColor = <String, Color>{};

  /// List of all country codes (ISO 3166-1 alpha-2).
  final List<String> _allCountryCodes = <String>[
    'af',
    'al',
    'dz',
    'as',
    'ad',
    'ao',
    'ai',
    'aq',
    'ag',
    'ar',
    'am',
    'aw',
    'au',
    'at',
    'ax',
    'az',
    'bs',
    'bh',
    'bd',
    'bb',
    'by',
    'be',
    'bz',
    'bj',
    'bm',
    'bt',
    'bo',
    'bq',
    'ba',
    'bw',
    'bv',
    'br',
    'io',
    'bn',
    'bg',
    'bf',
    'bi',
    'cv',
    'kh',
    'cm',
    'ca',
    'ky',
    'cf',
    'td',
    'cl',
    'cn',
    'cx',
    'cc',
    'co',
    'km',
    'cg',
    'cd',
    'ck',
    'cr',
    'hr',
    'cu',
    'cw',
    'cy',
    'cz',
    'ci',
    'dk',
    'dj',
    'dm',
    'do',
    'ec',
    'eg',
    'sv',
    'gq',
    'er',
    'ee',
    'sz',
    'et',
    'fk',
    'fo',
    'fj',
    'fi',
    'fr',
    'gf',
    'pf',
    'tf',
    'ga',
    'gm',
    'ge',
    'de',
    'gh',
    'gi',
    'gr',
    'gl',
    'gd',
    'gp',
    'gu',
    'gt',
    'gg',
    'gn',
    'gw',
    'gy',
    'ht',
    'hm',
    'va',
    'hn',
    'hk',
    'hu',
    'is',
    'in',
    'id',
    'ir',
    'iq',
    'ie',
    'im',
    'il',
    'it',
    'jm',
    'jp',
    'je',
    'jo',
    'kz',
    'ke',
    'ki',
    'kp',
    'kr',
    'xk',
    'kw',
    'kg',
    'la',
    'lv',
    'lb',
    'ls',
    'lr',
    'ly',
    'li',
    'lt',
    'lu',
    'mo',
    'mg',
    'mw',
    'my',
    'mv',
    'ml',
    'mt',
    'mh',
    'mq',
    'mr',
    'mu',
    'yt',
    'mx',
    'fm',
    'md',
    'mc',
    'mn',
    'me',
    'ms',
    'ma',
    'mz',
    'mm',
    'na',
    'nr',
    'np',
    'nl',
    'nc',
    'nz',
    'ni',
    'ne',
    'ng',
    'nu',
    'nf',
    'mk',
    'mp',
    'no',
    'om',
    'pk',
    'pw',
    'ps',
    'pa',
    'pg',
    'py',
    'pe',
    'ph',
    'pn',
    'pl',
    'pt',
    'pr',
    'qa',
    'ro',
    'ru',
    'rw',
    're',
    'bl',
    'sh',
    'kn',
    'lc',
    'mf',
    'pm',
    'vc',
    'ws',
    'sm',
    'st',
    'sa',
    'sn',
    'rs',
    'sc',
    'sl',
    'sg',
    'sx',
    'sk',
    'si',
    'sb',
    'so',
    'za',
    'gs',
    'ss',
    'es',
    'lk',
    'sd',
    'sr',
    'sj',
    'se',
    'ch',
    'sy',
    'tw',
    'tj',
    'tz',
    'th',
    'tl',
    'tg',
    'tk',
    'to',
    'tt',
    'tn',
    'tr',
    'tm',
    'tc',
    'tv',
    'ug',
    'ua',
    'ae',
    'gb',
    'us',
    'uy',
    'uz',
    'vu',
    've',
    'vn',
    'vg',
    'vi',
    'wf',
    'eh',
    'ye',
    'zm',
    'zw'
  ];

  @override
  void initState() {
    super.initState();
    _selectedRuleSet = widget.ruleSet;
    _initializeCountryMappings();
  }

  /// Initializes mappings between country codes, rule sets, and colors.
  void _initializeCountryMappings() {
    // Assign RuleSet.nineMensMorris (blue) to Western countries, North/Central America,
    // South America, Oceania, South Asia (except Sri Lanka), North Africa, Japan, and West Asia
    final List<String> blueRegion = <String>[
      'us',
      'ca',
      'mx',
      'br',
      'ar',
      'au',
      'nz',
      'jp',
      'gb',
      'fr',
      'de',
      'it',
      'es',
      'pt',
      'in',
      'pk',
      'bd',
      'eg',
      'ma',
      'dz',
      'sa',
      'tr',
      'il',
      'ae',
      'qa',
      'kw',
      'om',
      'jo',
      'lb',
      'sy',
      'iq',
      'ye',
      'bh',
      'ly',
      'tn',
      'gt',
      'hn',
      'sv',
      'ni',
      'pa',
      've',
      'uy',
      'py',
      'bo',
      'cl',
      'co',
      'ec',
      'cr',
      'do',
      'tt',
      'bs',
      'bb',
      'ag',
      'jm',
      'gd',
      'dm',
      'kn',
      'vc',
      'lc',
      'ai',
      'bm',
      'ky',
      'bz',
      'gf',
      'gy',
      'sr',
      'ad',
      'al',
      'at',
      'aw',
      'ax',
      'be',
      'bg',
      'ch',
      'cy',
      'cz',
      'dk',
      'fi',
      'gl',
      'gr',
      'hr',
      'hu',
      'ie',
      'is',
      'li',
      'lu',
      'mc',
      'me',
      'mt',
      'nl',
      'no',
      'pl',
      'pt',
      'ro',
      'se',
      'si',
      'sk',
      'sm',
      'va',
      'pe',
      'cu',
      'pr',
      'vi',
      'vg',
      'fk',
      'ai',
      'ck',
      'cw',
      'gp',
      'mf',
      'pm',
      'sx',
      'tf',
      'as',
      'aq',
      'bt',
      'bq',
      'bv',
      'io',
      'fj',
      'gi',
      'gu',
      'ht',
      'hm',
      'mv',
      'mq',
      'mu',
      'yt',
      'np',
      'nc',
      'nu',
      'nf',
      'ps',
      're',
      'bl',
      'sh',
      'sb',
      'gs',
      'tk',
      'vi'
    ];
    _assignRuleSetToCountries(blueRegion, RuleSet.nineMensMorris, Colors.blue);

    // Assign RuleSet.twelveMensMorris (light green) to Central Africa, Philippines, Mongolia, and Central Asia
    final List<String> lightGreenRegion = <String>[
      'cd',
      'cm',
      'ci',
      'cf',
      'td',
      'ne',
      'ml',
      'ph',
      'pn',
      'mn',
      'kz',
      'kg',
      'uz',
      'tj',
      'tm',
      'et',
      'dj',
      'er',
      'so',
      'sd',
      'rw',
      'bi',
      'ug',
      'ke',
      'tz',
      'ss',
      'cg',
      'ga',
      'gq',
      'bf',
      'gm',
      'gn',
      'lr',
      'mr',
      'gw',
      'bj',
      'sj',
      'st',
      'tg',
      'eh',
      'ng',
      'gh',
      'sl',
      'sn'
    ];
    _assignRuleSetToCountries(
        lightGreenRegion, RuleSet.twelveMensMorris, Colors.lightGreen);

    // Assign RuleSet.morabaraba (Lime) to Southern Africa
    final List<String> limeRegion = <String>[
      'za',
      'zw',
      'zm',
      'na',
      'bw',
      'ls',
      'sz',
      'ao',
      'mg',
      'mw',
      'mz',
      'cv',
      'sc',
      'sh',
    ];
    _assignRuleSetToCountries(limeRegion, RuleSet.morabaraba, Colors.lime);

    // Assign RuleSet.dooz (green) to Iran, Afghanistan, and Tajikistan
    final List<String> greenRegion = <String>['ir', 'af', 'tj'];
    _assignRuleSetToCountries(greenRegion, RuleSet.dooz, Colors.green);

    // Assign RuleSet.oneTimeMill (light blue) to Russia and former Soviet states
    final List<String> lightBlueRegion = <String>[
      'ru',
      'ua',
      'by',
      'ee',
      'lt',
      'lv',
      'md',
      'ge',
      'am',
      'az',
      'tm',
      'kg',
      'kz',
      'uz',
      'xk',
      'rs',
      'ba',
      'mk',
      'al',
      'ad',
      'gg',
      'je',
      'im',
      'fo'
    ];
    _assignRuleSetToCountries(
        lightBlueRegion, RuleSet.oneTimeMill, Colors.lightBlue);

    // Assign RuleSet.chamGonu (deep yellow) to North and South Korea
    final List<String> deepYellowRegion = <String>['kp', 'kr'];
    _assignRuleSetToCountries(deepYellowRegion, RuleSet.chamGonu,
        const Color.fromARGB(255, 255, 204, 0));

    // Assign RuleSet.zhiQi (yellow) to Mainland China, Taiwan, and Southeast Asia (excluding Indonesia and Malaysia)
    final List<String> yellowRegion = <String>[
      'cn',
      'tw',
      'vn',
      'th',
      'la',
      'mm',
      'kh',
      'my',
      'id',
      'sg',
      'bn',
      'tl',
      'mo',
      'hk',
      'cc',
      'cx',
      'fm',
      'pw',
      'mp',
      'nr',
      'wf'
    ];
    _assignRuleSetToCountries(yellowRegion, RuleSet.zhiQi, Colors.yellow);

    // Assign RuleSet.mulMulan (orange) to Indonesia, Malaysia, and neighboring countries
    final List<String> orangeRegion = <String>[
      'id',
      'my',
      'sg',
      'bn',
      'tl',
      'pg',
      'vu',
      'mh',
      'to',
      'tv',
      'ki',
      'ws'
    ];
    _assignRuleSetToCountries(orangeRegion, RuleSet.mulMulan, Colors.orange);

    // Assign RuleSet.nerenchi (gold) to Sri Lanka
    final List<String> goldRegion = <String>['lk'];
    _assignRuleSetToCountries(goldRegion, RuleSet.nerenchi, Colors.amber);

    // Assign remaining countries a default rule set and grey color
    for (final String code in _allCountryCodes) {
      if (!_countryCodeToColor.containsKey(code)) {
        _countryCodeToRuleSet[code] = RuleSet.current;
        _countryCodeToColor[code] = Colors.grey;
      }
    }
  }

  /// Assigns a rule set and color to a list of country codes.
  void _assignRuleSetToCountries(
      List<String> countries, RuleSet ruleSet, Color color) {
    for (final String code in countries) {
      _countryCodeToRuleSet[code] = ruleSet;
      _countryCodeToColor[code] = color;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Rule Set',
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Radio button for selecting the current rule set
            RadioListTile<RuleSet>(
              title: Text(S.of(context).currentRule),
              groupValue: _selectedRuleSet,
              value: RuleSet.current,
              onChanged: (RuleSet? value) {
                setState(() {
                  _selectedRuleSet = value!;
                });
                widget.onChanged?.call(value);
              },
            ),
            // Radio button for selecting the Nine Men's Morris rule set
            RadioListTile<RuleSet>(
              title: Text(S.of(context).nineMensMorris),
              groupValue: _selectedRuleSet,
              value: RuleSet.nineMensMorris,
              onChanged: (RuleSet? value) {
                setState(() {
                  _selectedRuleSet = value!;
                });
                widget.onChanged?.call(value);
              },
            ),
            // Radio button for selecting the Twelve Men's Morris rule set
            RadioListTile<RuleSet>(
              title: Text(S.of(context).twelveMensMorris),
              groupValue: _selectedRuleSet,
              value: RuleSet.twelveMensMorris,
              onChanged: (RuleSet? value) {
                setState(() {
                  _selectedRuleSet = value!;
                });
                widget.onChanged?.call(value);
              },
            ),
            // Radio button for selecting the Morabaraba rule set
            RadioListTile<RuleSet>(
              title: Text(S.of(context).morabaraba),
              groupValue: _selectedRuleSet,
              value: RuleSet.morabaraba,
              onChanged: (RuleSet? value) {
                setState(() {
                  _selectedRuleSet = value!;
                });
                widget.onChanged?.call(value);
              },
            ),
            // Radio button for selecting the Dooz rule set
            RadioListTile<RuleSet>(
              title: Text(S.of(context).dooz),
              groupValue: _selectedRuleSet,
              value: RuleSet.dooz,
              onChanged: (RuleSet? value) {
                setState(() {
                  _selectedRuleSet = value!;
                });
                widget.onChanged?.call(value);
              },
            ),
            // Radio button for selecting the Lasker Morris rule set
            RadioListTile<RuleSet>(
              title: Text(S.of(context).laskerMorris),
              groupValue: _selectedRuleSet,
              value: RuleSet.laskerMorris,
              onChanged: (RuleSet? value) {
                setState(() {
                  _selectedRuleSet = value!;
                });
                widget.onChanged?.call(value);
              },
            ),
            // Radio button for selecting the One Time Mill rule set
            RadioListTile<RuleSet>(
              title: Text(S.of(context).oneTimeMill),
              groupValue: _selectedRuleSet,
              value: RuleSet.oneTimeMill,
              onChanged: (RuleSet? value) {
                setState(() {
                  _selectedRuleSet = value!;
                });
                widget.onChanged?.call(value);
              },
            ),
            // Radio button for selecting the Cham Gonu rule set
            RadioListTile<RuleSet>(
              title: Text(S.of(context).chamGonu),
              groupValue: _selectedRuleSet,
              value: RuleSet.chamGonu,
              onChanged: (RuleSet? value) {
                setState(() {
                  _selectedRuleSet = value!;
                });
                widget.onChanged?.call(value);
              },
            ),
            // Radio button for selecting the Zhi Qi rule set
            RadioListTile<RuleSet>(
              title: Text(S.of(context).zhiQi),
              groupValue: _selectedRuleSet,
              value: RuleSet.zhiQi,
              onChanged: (RuleSet? value) {
                setState(() {
                  _selectedRuleSet = value!;
                });
                widget.onChanged?.call(value);
              },
            ),
            // Radio button for selecting the Cheng San Qi rule set
            RadioListTile<RuleSet>(
              title: Text(S.of(context).chengSanQi),
              groupValue: _selectedRuleSet,
              value: RuleSet.chengSanQi,
              onChanged: (RuleSet? value) {
                setState(() {
                  _selectedRuleSet = value!;
                });
                widget.onChanged?.call(value);
              },
            ),
            // Radio button for selecting the Da San Qi rule set
            RadioListTile<RuleSet>(
              title: Text(S.of(context).daSanQi),
              groupValue: _selectedRuleSet,
              value: RuleSet.daSanQi,
              onChanged: (RuleSet? value) {
                setState(() {
                  _selectedRuleSet = value!;
                });
                widget.onChanged?.call(value);
              },
            ),
            // Radio button for selecting the Mul Mulan rule set
            RadioListTile<RuleSet>(
              title: Text(S.of(context).mulMulan),
              groupValue: _selectedRuleSet,
              value: RuleSet.mulMulan,
              onChanged: (RuleSet? value) {
                setState(() {
                  _selectedRuleSet = value!;
                });
                widget.onChanged?.call(value);
              },
            ),
            // Radio button for selecting the Nerenchi rule set
            RadioListTile<RuleSet>(
              title: Text(S.of(context).nerenchi),
              groupValue: _selectedRuleSet,
              value: RuleSet.nerenchi,
              onChanged: (RuleSet? value) {
                setState(() {
                  _selectedRuleSet = value!;
                });
                widget.onChanged?.call(value);
              },
            ),
            // Radio button for selecting a rule set from the map
            RadioListTile<RuleSet>(
              title: const Text('Select from map'),
              groupValue: _selectedRuleSet,
              value: RuleSet.selectFromMap,
              onChanged: (RuleSet? value) {
                setState(() {
                  _selectedRuleSet = value!;
                });
              },
            ),
            if (_selectedRuleSet == RuleSet.selectFromMap) _buildMap(),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return SizedBox(
      height: 400,
      child: InteractiveViewer(
        maxScale: 75.0,
        child: SimpleMap(
          instructions: SMapWorld.instructions,
          defaultColor: Colors.grey,
          colors: _countryCodeToColor,
          callback: (String id, String name, TapUpDetails tapDetails) {
            final String countryCode = id.toLowerCase();
            final RuleSet? ruleSet = _countryCodeToRuleSet[countryCode];
            if (ruleSet != null) {
              setState(() {
                _selectedRuleSet = ruleSet;
              });
              widget.onChanged?.call(ruleSet);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Selected country is not supported')),
              );
            }
          },
        ),
      ),
    );
  }
}
