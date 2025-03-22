// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// use_perfect_database_dialog.dart

part of 'package:sanmill/general_settings/widgets/general_settings_page.dart';

class _UsePerfectDatabaseDialog extends StatelessWidget {
  const _UsePerfectDatabaseDialog();

  Future<void> _ok(BuildContext context) async {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    String description;

    if (isRuleSupportingPerfectDatabase() == true) {
      description = S.of(context).perfectDatabaseDescription;

      // TODO: Fix Twelve Men's Morris DB has draw
      if (DB().ruleSettings.piecesCount == 12) {
        description = '${S.of(context).experimental}\n\n$description';
      }
    } else {
      description = S.of(context).currentRulesNoPerfectDatabase;
    }

    return AlertDialog(
      key: const Key('use_perfect_database_dialog_alert_dialog'),
      title: Text(
        S.of(context).appName,
        key: const Key('use_perfect_database_dialog_title'),
        style: AppTheme.dialogTitleTextStyle,
      ),
      content: SingleChildScrollView(
        key: const Key('use_perfect_database_dialog_content_scroll_view'),
        child: Column(
          key: const Key('use_perfect_database_dialog_column'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            InkWell(
              key: const Key(
                  'use_perfect_database_dialog_inkwell_use_perfect_database'),
              onTap: () => launchURL(context, Constants.perfectDatabaseUrl),
              child: Padding(
                key: const Key(
                    'use_perfect_database_dialog_padding_use_perfect_database'),
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  S.of(context).usePerfectDatabase,
                  key: const Key(
                      'use_perfect_database_dialog_text_use_perfect_database'),
                  style: const TextStyle(
                    decoration: TextDecoration.underline,
                    color: Colors.blue,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              description,
              key: const Key('use_perfect_database_dialog_description_text'),
              style: TextStyle(
                  fontSize:
                      AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
            ),
            const SizedBox(height: 16),
            InkWell(
              key: const Key('use_perfect_database_dialog_inkwell_help'),
              onTap: () => launchURL(context, Constants.perfectDatabaseUrl),
              child: Padding(
                key: const Key('use_perfect_database_dialog_padding_help'),
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  S.of(context).help,
                  key: const Key('use_perfect_database_dialog_text_help'),
                  style: const TextStyle(
                    decoration: TextDecoration.underline,
                    color: Colors.blue,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('use_perfect_database_dialog_ok_button'),
          onPressed: () => _ok(context),
          child: Text(
            S.of(context).ok,
            key: const Key('use_perfect_database_dialog_ok_button_text'),
            style: TextStyle(
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
          ),
        ),
      ],
    );
  }
}
