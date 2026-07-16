// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/models/llm_analysis.dart';
import '../../shared/services/ai_chat_service.dart';
import '../../shared/services/ai_report_service.dart';

/// A game-only AI analysis surface with no arbitrary user prompt input.
class AiChatDialog extends StatefulWidget {
  const AiChatDialog({super.key});

  @override
  State<AiChatDialog> createState() => _AiChatDialogState();
}

class _AiChatDialogState extends State<AiChatDialog> {
  final AiChatService _analysisService = AiChatService();
  LlmAnalysisResult? _result;
  LlmTask? _task;
  String? _error;
  bool _loading = false;

  Future<void> _run(LlmTask task) async {
    if (_loading) {
      return;
    }
    setState(() {
      _task = task;
      _result = null;
      _error = null;
      _loading = true;
    });
    try {
      final LlmAnalysisResult result = await _analysisService.analyze(
        task: task,
        locale: Localizations.localeOf(context).toLanguageTag(),
      );
      if (mounted) {
        setState(() => _result = result);
      }
    } on LlmException catch (error) {
      if (mounted) {
        setState(() => _error = _localizedError(error.code));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = S.of(context).aiAnalysisErrorNetwork);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _localizedError(LlmErrorCode code) {
    final S strings = S.of(context);
    return switch (code) {
      LlmErrorCode.notConfigured => strings.aiAnalysisErrorNotConfigured,
      LlmErrorCode.consentRequired => strings.aiAnalysisErrorConsent,
      LlmErrorCode.unsupportedPlatform => strings.aiAnalysisErrorPlatform,
      LlmErrorCode.invalidEndpoint => strings.aiAnalysisErrorEndpoint,
      LlmErrorCode.network => strings.aiAnalysisErrorNetwork,
      LlmErrorCode.timeout => strings.aiAnalysisErrorTimeout,
      LlmErrorCode.invalidResponse => strings.aiAnalysisErrorResponse,
      LlmErrorCode.safetyBlocked => strings.aiAnalysisErrorBlocked,
    };
  }

  Future<void> _copyResult() async {
    final LlmAnalysisResult? result = _result;
    if (result == null) {
      return;
    }
    final S strings = S.of(context);
    await Clipboard.setData(
      ClipboardData(
        text: strings.aiAnalysisCopyPrefix(
          result.provider,
          result.model,
          result.answer,
        ),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.aiAnalysisCopied)));
    }
  }

  Future<void> _showReportDialog() async {
    final LlmAnalysisResult? result = _result;
    final LlmTask? task = _task;
    if (result == null || task == null) {
      return;
    }
    final AiReportService reportService = AiReportService();
    if (!reportService.isAvailable) {
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text(S.of(context).aiReportTitle),
          content: Text(S.of(context).aiReportUnavailable),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(S.of(context).ok),
            ),
          ],
        ),
      );
      return;
    }

    final AiReportReceipt? receipt = await showDialog<AiReportReceipt>(
      context: context,
      builder: (BuildContext context) =>
          _AiReportDialog(service: reportService, task: task, result: result),
    );
    if (receipt == null || !mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(S.of(dialogContext).aiReportTitle),
        content: Text(
          S
              .of(dialogContext)
              .aiReportSuccess(
                receipt.reportId,
                MaterialLocalizations.of(
                  dialogContext,
                ).formatMediumDate(receipt.expiresAt.toLocal()),
              ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              try {
                await reportService.delete(receipt.reportId);
                if (!mounted || !dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(S.of(context).aiReportDeleted)),
                );
              } catch (_) {
                if (!mounted || !dialogContext.mounted) {
                  return;
                }
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text(S.of(context).aiReportFailed)),
                );
              }
            },
            child: Text(S.of(dialogContext).aiReportDelete),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.of(dialogContext).ok),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    return FractionallySizedBox(
      heightFactor: 0.86,
      child: Material(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            children: <Widget>[
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.auto_graph),
                title: Text(strings.aiAnalysisTitle),
                subtitle: Text(strings.aiAnalysisDisclosure),
                trailing: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: strings.close,
                  icon: const Icon(Icons.close),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    Text(
                      strings.aiAnalysisSelectTask,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _TaskButton(
                          icon: Icons.analytics_outlined,
                          label: strings.aiAnalysisTaskPosition,
                          selected: _task == LlmTask.positionAnalysis,
                          onPressed: _loading
                              ? null
                              : () => _run(LlmTask.positionAnalysis),
                        ),
                        _TaskButton(
                          icon: Icons.undo,
                          label: strings.aiAnalysisTaskLastMove,
                          selected: _task == LlmTask.explainLastMove,
                          onPressed: _loading
                              ? null
                              : () => _run(LlmTask.explainLastMove),
                        ),
                        _TaskButton(
                          icon: Icons.fact_check_outlined,
                          label: strings.aiAnalysisTaskReview,
                          selected: _task == LlmTask.gameReview,
                          onPressed: _loading
                              ? null
                              : () => _run(LlmTask.gameReview),
                        ),
                        _TaskButton(
                          icon: Icons.menu_book_outlined,
                          label: strings.aiAnalysisTaskRules,
                          selected: _task == LlmTask.explainRules,
                          onPressed: _loading
                              ? null
                              : () => _run(LlmTask.explainRules),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (_loading)
                      Semantics(
                        liveRegion: true,
                        label: strings.aiAnalysisLoading,
                        child: Column(
                          children: <Widget>[
                            const CircularProgressIndicator(),
                            const SizedBox(height: 12),
                            Text(strings.aiAnalysisLoading),
                          ],
                        ),
                      ),
                    if (_error != null)
                      Semantics(
                        liveRegion: true,
                        child: Card(
                          color: colors.errorContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _error!,
                              style: TextStyle(color: colors.onErrorContainer),
                            ),
                          ),
                        ),
                      ),
                    if (_result case final LlmAnalysisResult result)
                      Semantics(
                        liveRegion: true,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Chip(
                                  avatar: const Icon(
                                    Icons.smart_toy_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    strings.aiAnalysisProvenance(
                                      result.provider,
                                      result.model,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SelectableText(result.answer),
                                const SizedBox(height: 12),
                                Text(
                                  strings.aiAnalysisDisclosure,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: <Widget>[
                                    TextButton.icon(
                                      onPressed: _copyResult,
                                      icon: const Icon(Icons.copy),
                                      label: Text(strings.copy),
                                    ),
                                    TextButton.icon(
                                      onPressed: _showReportDialog,
                                      icon: const Icon(Icons.flag_outlined),
                                      label: Text(strings.aiReportTitle),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskButton extends StatelessWidget {
  const _TaskButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return selected
        ? FilledButton.tonalIcon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          );
  }
}

class _AiReportDialog extends StatefulWidget {
  const _AiReportDialog({
    required this.service,
    required this.task,
    required this.result,
  });

  final AiReportService service;
  final LlmTask task;
  final LlmAnalysisResult result;

  @override
  State<_AiReportDialog> createState() => _AiReportDialogState();
}

class _AiReportDialogState extends State<_AiReportDialog> {
  AiReportCategory _category = AiReportCategory.incorrect;
  late final TextEditingController _answerController;
  bool _includeAnswer = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _answerController = TextEditingController(text: widget.result.answer);
  }

  String _categoryLabel(S strings, AiReportCategory category) {
    return switch (category) {
      AiReportCategory.harmful => strings.aiReportHarmful,
      AiReportCategory.hate => strings.aiReportHate,
      AiReportCategory.sexual => strings.aiReportSexual,
      AiReportCategory.selfHarm => strings.aiReportSelfHarm,
      AiReportCategory.privacy => strings.aiReportPrivacy,
      AiReportCategory.offTopic => strings.aiReportOffTopic,
      AiReportCategory.incorrect => strings.aiReportIncorrect,
      AiReportCategory.other => strings.aiReportOther,
    };
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final String locale = Localizations.localeOf(context).toLanguageTag();
      final String reviewedAnswer = _answerController.text.trim();
      final PackageInfo package = await PackageInfo.fromPlatform();
      final AiReportReceipt receipt = await widget.service.submit(
        category: _category,
        task: widget.task,
        provider: widget.result.provider,
        model: widget.result.model,
        appVersion: '${package.version}+${package.buildNumber}',
        platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
        locale: locale,
        includedAnswer: _includeAnswer && reviewedAnswer.isNotEmpty
            ? reviewedAnswer
            : null,
      );
      if (mounted) {
        Navigator.of(context).pop(receipt);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(S.of(context).aiReportFailed)));
      }
    }
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    return AlertDialog(
      title: Text(strings.aiReportTitle),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(strings.aiReportPrivacyNotice),
              const SizedBox(height: 16),
              DropdownButtonFormField<AiReportCategory>(
                initialValue: _category,
                decoration: InputDecoration(
                  labelText: strings.aiReportCategory,
                  border: const OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<AiReportCategory>>[
                  for (final AiReportCategory category
                      in AiReportCategory.values)
                    DropdownMenuItem<AiReportCategory>(
                      value: category,
                      child: Text(_categoryLabel(strings, category)),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (AiReportCategory? value) {
                        if (value != null) {
                          setState(() => _category = value);
                        }
                      },
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _includeAnswer,
                onChanged: _submitting
                    ? null
                    : (bool? value) =>
                          setState(() => _includeAnswer = value ?? false),
                title: Text(strings.aiReportIncludeAnswer),
              ),
              if (_includeAnswer)
                TextField(
                  controller: _answerController,
                  minLines: 4,
                  maxLines: 10,
                  maxLength: 16384,
                  decoration: InputDecoration(
                    labelText: strings.aiReportAnswerPreview,
                    border: const OutlineInputBorder(),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(strings.aiReportSubmit),
        ),
      ],
    );
  }
}
