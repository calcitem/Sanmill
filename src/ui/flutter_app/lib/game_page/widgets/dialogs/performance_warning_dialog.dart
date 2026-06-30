// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// performance_warning_dialog.dart

import 'package:flutter/material.dart';

import '../../../generated/intl/l10n.dart';
import '../../../shared/config/constants.dart';
import '../../../shared/services/url.dart';
import '../../../shared/themes/app_theme.dart';

/// Dialog warning the user that the AI engine timed out, suggesting they
/// reduce the AI thinking time and offering a link to submit feedback.
///
/// Displayed at most once per app session to avoid repeated interruptions.
class PerformanceWarningDialog extends StatelessWidget {
  const PerformanceWarningDialog({super.key});

  // Suppresses repeated displays within the same app session.
  static bool _hasShownThisSession = false;

  /// Shows [PerformanceWarningDialog] unless it has already been shown during
  /// this session. Does nothing if [context] is no longer mounted.
  static Future<void> showIfNeeded(BuildContext context) async {
    if (_hasShownThisSession) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    _hasShownThisSession = true;
    await showDialog<void>(
      context: context,
      builder: (_) => const PerformanceWarningDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('performance_warning_dialog'),
      title: Text(
        S.of(context).engineTimeoutPerformanceWarningTitle,
        key: const Key('performance_warning_dialog_title'),
        style: AppTheme.dialogTitleTextStyle,
      ),
      content: Text(
        S.of(context).engineTimeoutPerformanceWarningContent,
        key: const Key('performance_warning_dialog_content'),
        style: TextStyle(
          fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('performance_warning_dialog_feedback_button'),
          child: Text(
            S.of(context).feedback,
            style: TextStyle(
              fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
            ),
          ),
          onPressed: () {
            Navigator.pop(context);
            launchURL(context, Constants.issuesURL);
          },
        ),
        TextButton(
          key: const Key('performance_warning_dialog_ok_button'),
          child: Text(
            S.of(context).ok,
            style: TextStyle(
              fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
