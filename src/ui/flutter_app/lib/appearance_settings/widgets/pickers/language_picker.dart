// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// language_picker.dart

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

class _LanguagePicker extends StatefulWidget {
  const _LanguagePicker({
    required this.currentLanguageLocale,
  });

  final Locale? currentLanguageLocale;

  @override
  _LanguagePickerState createState() => _LanguagePickerState();
}

class _LanguagePickerState extends State<_LanguagePicker> {
  Locale? _selectedLocale;

  @override
  void initState() {
    super.initState();
    _selectedLocale = widget.currentLanguageLocale;
  }

  @override
  Widget build(BuildContext context) {
    final Column languageColumn = Column(
      key: const Key('language_picker_column'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        RadioListTile<Locale?>(
          key: const Key('language_picker_radio_default'),
          title: Text(
            S.of(context).defaultLanguage,
            key: const Key('language_picker_radio_default_title'),
            style: TextStyle(
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
          ),
          groupValue: _selectedLocale,
          value: null,
          onChanged: (Locale? locale) {
            setState(() {
              _selectedLocale = locale;
            });
            Navigator.pop(context, _selectedLocale);
          },
        ),
        const Divider(
          key: Key('language_picker_divider'),
        ),
        for (final Locale locale in localeToLanguageName.keys)
          RadioListTile<Locale>(
            key: Key('language_picker_radio_$locale'),
            title: Text(
              localeToLanguageName[locale]!,
              key: Key(
                  'language_picker_radio_${locale.languageCode}_${locale.countryCode}_title'),
              style: TextStyle(
                  fontSize:
                      AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
            ),
            groupValue: _selectedLocale,
            value: locale,
            onChanged: (Locale? locale) {
              setState(() {
                _selectedLocale = locale;
              });
              Navigator.pop(context, _selectedLocale);
            },
          ),
      ],
    );

    return AlertDialog(
      key: const Key('language_picker_alert_dialog'),
      scrollable: true,
      content: languageColumn,
    );
  }
}
