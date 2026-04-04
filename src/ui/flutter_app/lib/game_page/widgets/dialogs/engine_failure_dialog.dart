// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// engine_failure_dialog.dart

import 'package:catcher_2/catcher_2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../generated/intl/l10n.dart';
import '../../../shared/themes/app_theme.dart';

/// Dialog shown when the AI engine fails to produce a move.
///
/// Displays diagnostic context (FEN, phase, side to move) and offers the user
/// a choice: dismiss, or send a diagnostic report via [Catcher2] which will
/// trigger the configured email handler with stack trace and game state.
class EngineFailureDialog extends StatelessWidget {
  const EngineFailureDialog({required this.diagnosticContext, super.key});

  final String diagnosticContext;

  /// Collects the current game state into a human-readable diagnostic string.
  static String buildDiagnosticContext({
    String? fen,
    String? phase,
    String? sideToMove,
    String? lastMove,
  }) {
    final StringBuffer buf = StringBuffer();
    if (fen != null) {
      buf.writeln('FEN: $fen');
    }
    if (phase != null) {
      buf.writeln('Phase: $phase');
    }
    if (sideToMove != null) {
      buf.writeln('Side to move: $sideToMove');
    }
    if (lastMove != null) {
      buf.writeln('Last move: $lastMove');
    }
    return buf.toString().trimRight();
  }

  /// Shows the dialog and, if the user consents, reports the error via
  /// [Catcher2] so the configured handlers (file log + email) are invoked.
  static Future<void> show(
    BuildContext context, {
    required String diagnosticContext,
  }) async {
    if (!context.mounted) {
      return;
    }

    final bool? shouldReport = await showDialog<bool>(
      context: context,
      builder: (_) => EngineFailureDialog(diagnosticContext: diagnosticContext),
    );

    if (shouldReport ?? false) {
      _reportError(diagnosticContext);
    }
  }

  static void _reportError(String diagnosticContext) {
    final StateError error = StateError(
      'EngineNoBestMove: AI engine failed to produce a move.\n'
      '$diagnosticContext',
    );

    if (!kIsWeb) {
      Catcher2.reportCheckedError(error, StackTrace.current);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('engine_failure_dialog'),
      title: Text(
        S.of(context).engineFailureTitle,
        key: const Key('engine_failure_dialog_title'),
        style: AppTheme.dialogTitleTextStyle,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              S.of(context).engineFailureContent,
              key: const Key('engine_failure_dialog_content'),
              style: TextStyle(
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
              ),
            ),
            if (diagnosticContext.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SelectableText(
                  diagnosticContext,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: AppTheme.textScaler.scale(
                      AppTheme.defaultFontSize - 2,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('engine_failure_dialog_send_button'),
          child: Text(
            S.of(context).sendReport,
            style: TextStyle(
              fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
            ),
          ),
          onPressed: () => Navigator.pop(context, true),
        ),
        TextButton(
          key: const Key('engine_failure_dialog_ok_button'),
          child: Text(
            S.of(context).ok,
            style: TextStyle(
              fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
            ),
          ),
          onPressed: () => Navigator.pop(context, false),
        ),
      ],
    );
  }
}
