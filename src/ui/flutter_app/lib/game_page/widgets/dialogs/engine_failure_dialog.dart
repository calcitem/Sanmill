// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// engine_failure_dialog.dart

import 'package:flutter/material.dart';

import '../../../generated/intl/l10n.dart';
import '../../../shared/models/diagnostic_bundle.dart';
import '../../../shared/services/diagnostic_report_service.dart';
import '../../../shared/themes/app_theme.dart';

/// Dialog shown when the AI engine fails to produce a move.
///
/// The static entry point freezes a local first-party report draft immediately;
/// the app then opens the shared preview page. This widget remains available
/// for callers that only need to render the failure context.
class EngineFailureDialog extends StatelessWidget {
  const EngineFailureDialog({required this.diagnosticContext, super.key});

  final String diagnosticContext;

  /// Collects the current game state into a human-readable diagnostic string.
  static String buildDiagnosticContext({
    String? fen,
    String? phase,
    String? sideToMove,
    String? zobrist,
    String? lastMove,
    String? moveList,
    String? failureDetails,
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
    if (zobrist != null) {
      buf.writeln('Zobrist: $zobrist');
    }
    if (lastMove != null) {
      buf.writeln('Last move: $lastMove');
    }
    if (moveList != null && moveList.isNotEmpty) {
      buf.writeln('Move list: $moveList');
    }
    // Precise, release-visible rejection diagnostics captured at the failure
    // site (see NativeMillGameSession._recordEngineFailure): searched-vs-live
    // FEN/Zobrist and whether the position changed under the in-flight search.
    if (failureDetails != null && failureDetails.isNotEmpty) {
      buf.writeln(failureDetails);
    }
    return buf.toString().trimRight();
  }

  /// Opens the unified report flow without an extra pre-confirmation dialog.
  static Future<void> show(
    BuildContext context, {
    required String diagnosticContext,
  }) async {
    if (!context.mounted) {
      return;
    }

    await DiagnosticReportService().captureCrash(
      error: StateError(
        'EngineNoBestMove: AI engine failed to produce a move.\n'
        '$diagnosticContext',
      ),
      stackTrace: StackTrace.current,
      kind: DiagnosticReportKind.engineFailure,
    );
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
