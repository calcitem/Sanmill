// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../generated/intl/l10n.dart';
import '../services/diagnostic_report_service.dart';
import '../services/environment_config.dart';

/// First-party report editor. The generated text is both the visible preview
/// and the exact payload copied or sent to GlitchTip.
class DiagnosticReportPage extends StatefulWidget {
  const DiagnosticReportPage({required this.draft, super.key});

  final DiagnosticReportDraft draft;

  @override
  State<DiagnosticReportPage> createState() => _DiagnosticReportPageState();
}

class _DiagnosticReportPageState extends State<DiagnosticReportPage> {
  late final TextEditingController _feedbackController;
  late bool _includeConfig;
  late bool _includeActionTrail;
  late bool _includeLogs;
  String? _bundleText;
  Object? _previewError;
  bool _sending = false;
  int _previewGeneration = 0;

  @override
  void initState() {
    super.initState();
    _feedbackController = TextEditingController(
      text: widget.draft.feedbackText ?? '',
    )..addListener(_refreshPreview);
    final DiagnosticReportSelection defaults =
        DiagnosticReportSelection.defaultsFor(widget.draft);
    _includeConfig = defaults.includeConfig;
    _includeActionTrail = defaults.includeActionTrail;
    _includeLogs = defaults.includeLogs;
    unawaited(_refreshPreview());
  }

  @override
  void dispose() {
    _feedbackController
      ..removeListener(_refreshPreview)
      ..dispose();
    super.dispose();
  }

  Future<void> _refreshPreview() async {
    final int generation = ++_previewGeneration;
    if (mounted) {
      setState(() {
        _bundleText = null;
        _previewError = null;
      });
    }
    try {
      final String bundle = await DiagnosticReportService().buildBundleText(
        widget.draft,
        DiagnosticReportSelection(
          includeConfig: _includeConfig,
          includeActionTrail: _includeActionTrail,
          includeLogs: _includeLogs,
        ),
        feedbackText: widget.draft.kind.name == 'feedback'
            ? _feedbackController.text
            : null,
      );
      if (!mounted || generation != _previewGeneration) {
        return;
      }
      setState(() {
        _bundleText = bundle;
        _previewError = null;
      });
    } on Object catch (error) {
      if (!mounted || generation != _previewGeneration) {
        return;
      }
      setState(() {
        _bundleText = null;
        _previewError = error;
      });
    }
  }

  Future<void> _copy() async {
    final String? bundle = _bundleText;
    if (bundle == null) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: bundle));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).diagnosticBundleCopied)),
      );
    }
  }

  Future<void> _copyAndOpenIssue() async {
    await _copy();
    final Uri source = Uri.parse(EnvironmentConfig.sourceUrl);
    final Uri issueUrl = source.host == 'github.com'
        ? source.replace(
            path: '${source.path.replaceFirst(RegExp(r'/$'), '')}/issues/new',
            query: '',
            fragment: '',
          )
        : Uri.parse('https://github.com/calcitem/Sanmill/issues/new');
    await launchUrl(issueUrl, mode: LaunchMode.externalApplication);
  }

  Future<void> _send() async {
    final String? bundle = _bundleText;
    if (bundle == null || _sending) {
      return;
    }
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text(S.of(context).sendDiagnosticReport),
            content: Text(
              S
                  .of(context)
                  .diagnosticSendConfirmation(
                    EnvironmentConfig.diagnosticsRecipient,
                  ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(S.of(context).cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(S.of(context).sendReport),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _sending = true);
    try {
      await DiagnosticReportService().send(bundle);
      await DiagnosticReportService().deleteDraft(widget.draft.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).diagnosticReportSent)),
        );
        Navigator.of(context).pop();
      }
    } on Object catch (error) {
      if (mounted) {
        if (!widget.draft.isCrash) {
          await DiagnosticReportService().retainFeedbackDraft(
            widget.draft,
            _feedbackController.text,
          );
        }
        if (!mounted) {
          return;
        }
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context).diagnosticSendFailed(error.toString())),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final bool remote = DiagnosticReportService().remoteSendingAvailable;
    final List<Widget> timeline = widget.draft.actionTrail.events
        .map(
          (event) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: SelectableText(
              '+${(event.elapsedMs / 1000).toStringAsFixed(1)}s / '
              '${event.actionId} / ${_payloadSummary(event.payload)} / '
              '${event.phase.name}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        )
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text(strings.diagnosticReport)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            remote
                ? strings.diagnosticRecipient(
                    EnvironmentConfig.diagnosticsRecipient,
                  )
                : strings.diagnosticLocalOnly,
          ),
          if (remote) ...<Widget>[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => launchUrl(
                  Uri.parse(EnvironmentConfig.diagnosticsPrivacyUrl),
                  mode: LaunchMode.externalApplication,
                ),
                child: Text(strings.privacyPolicy),
              ),
            ),
          ],
          if (!widget.draft.isCrash) ...<Widget>[
            const SizedBox(height: 12),
            TextField(
              controller: _feedbackController,
              maxLength: 8192,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: strings.feedback,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          CheckboxListTile(
            key: const Key('diagnostic_include_config'),
            contentPadding: EdgeInsets.zero,
            value: _includeConfig,
            title: Text(strings.diagnosticIncludeConfiguration),
            onChanged: (bool? value) {
              setState(() => _includeConfig = value ?? false);
              unawaited(_refreshPreview());
            },
          ),
          CheckboxListTile(
            key: const Key('diagnostic_include_action_trail'),
            contentPadding: EdgeInsets.zero,
            value: _includeActionTrail,
            title: Text(strings.diagnosticIncludeActionTrail),
            onChanged: (bool? value) {
              setState(() => _includeActionTrail = value ?? false);
              unawaited(_refreshPreview());
            },
          ),
          CheckboxListTile(
            key: const Key('diagnostic_include_logs'),
            contentPadding: EdgeInsets.zero,
            value: _includeLogs,
            title: Text(strings.diagnosticIncludeLogs),
            onChanged: (bool? value) {
              setState(() => _includeLogs = value ?? false);
              unawaited(_refreshPreview());
            },
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              strings.diagnosticActionTimeline(
                widget.draft.actionTrail.events.length,
              ),
            ),
            children: timeline.isEmpty
                ? <Widget>[Text(strings.diagnosticNoActionEvents)]
                : timeline,
          ),
          const SizedBox(height: 12),
          Text(strings.diagnosticExactPreview),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(minHeight: 180, maxHeight: 420),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: _previewError == null
                  ? SelectableText(
                      _bundleText ?? strings.diagnosticLoadingPreview,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                    )
                  : SelectableText(_previewError.toString()),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: _bundleText == null ? null : _copy,
                icon: const Icon(Icons.copy),
                label: Text(strings.copy),
              ),
              OutlinedButton.icon(
                onPressed: _bundleText == null ? null : _copyAndOpenIssue,
                icon: const Icon(Icons.bug_report_outlined),
                label: Text(strings.diagnosticCopyAndOpenIssue),
              ),
              if (remote)
                FilledButton.icon(
                  onPressed: _bundleText == null || _sending ? null : _send,
                  icon: const Icon(Icons.send),
                  label: Text(
                    _sending ? strings.diagnosticSending : strings.sendReport,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _payloadSummary(Map<String, Object?> payload) {
    if (payload.isEmpty) {
      return '-';
    }
    return payload.entries
        .map((MapEntry<String, Object?> entry) => '${entry.key}=${entry.value}')
        .join(', ');
  }
}
