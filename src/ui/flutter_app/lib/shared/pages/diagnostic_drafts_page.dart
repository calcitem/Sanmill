// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../models/diagnostic_bundle.dart';
import '../services/diagnostic_report_service.dart';
import 'diagnostic_report_page.dart';

/// Lists locally retained crash and failed-feedback drafts.
class DiagnosticDraftsPage extends StatelessWidget {
  const DiagnosticDraftsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.diagnosticSavedDrafts)),
      body: ValueListenableBuilder<List<DiagnosticReportDraft>>(
        valueListenable: DiagnosticReportService().drafts,
        builder:
            (
              BuildContext context,
              List<DiagnosticReportDraft> drafts,
              Widget? child,
            ) {
              if (drafts.isEmpty) {
                return Center(child: Text(strings.diagnosticNoSavedDrafts));
              }
              return ListView.separated(
                itemCount: drafts.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (BuildContext context, int index) {
                  final DiagnosticReportDraft draft = drafts[index];
                  return ListTile(
                    key: ValueKey<String>('diagnostic_draft_${draft.id}'),
                    leading: Icon(
                      draft.isCrash
                          ? Icons.bug_report
                          : Icons.feedback_outlined,
                    ),
                    title: Text(_kindLabel(strings, draft.kind)),
                    subtitle: Text(draft.createdAtUtc.toLocal().toString()),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        settings: const RouteSettings(
                          name: '/diagnosticReport',
                        ),
                        builder: (BuildContext context) =>
                            DiagnosticReportPage(draft: draft),
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: strings.delete,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await DiagnosticReportService().deleteDraft(draft.id);
                      },
                    ),
                  );
                },
              );
            },
      ),
    );
  }

  static String _kindLabel(S strings, DiagnosticReportKind kind) {
    return switch (kind) {
      DiagnosticReportKind.crash => strings.diagnosticCrashDraft,
      DiagnosticReportKind.feedback => strings.feedback,
      DiagnosticReportKind.engineFailure => strings.engineFailureTitle,
    };
  }
}
