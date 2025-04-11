// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// reset_settings_alert_dialog.dart

part of 'package:sanmill/general_settings/widgets/general_settings_page.dart';

class _ResetSettingsAlertDialog extends StatelessWidget {
  const _ResetSettingsAlertDialog();

  void _cancel(BuildContext context) => Navigator.pop(context);

  Future<void> _restore(BuildContext context) async {
    rootScaffoldMessengerKey.currentState!
        .showSnackBarClear(S.of(context).reopenToTakeEffect);

    Navigator.pop(context);

    // TODO: Seems to need to close and reopen the program for it to work.
    await DB.reset();

    GameController().reset(force: true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('reset_settings_alert_dialog_alert_dialog'),
      title: Text(
        S.of(context).restore,
        key: const Key('reset_settings_alert_dialog_title'),
        style: AppTheme.dialogTitleTextStyle,
      ),
      content: SingleChildScrollView(
        key: const Key('reset_settings_alert_dialog_content_scroll_view'),
        child: Text(
          "${S.of(context).restoreDefaultSettings}?",
          key: const Key('reset_settings_alert_dialog_content_text'),
          style: TextStyle(
              fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('reset_settings_alert_dialog_ok_button'),
          onPressed: () => _restore(context),
          child: Text(
            S.of(context).ok,
            key: const Key('reset_settings_alert_dialog_ok_button_text'),
            style: TextStyle(
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
          ),
        ),
        TextButton(
          key: const Key('reset_settings_alert_dialog_cancel_button'),
          onPressed: () => _cancel(context),
          child: Text(
            S.of(context).cancel,
            key: const Key('reset_settings_alert_dialog_cancel_button_text'),
            style: TextStyle(
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
          ),
        ),
      ],
    );
  }
}
