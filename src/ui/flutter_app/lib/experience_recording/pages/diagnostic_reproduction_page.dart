// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../game_page/services/mill.dart' show GameMode;
import '../../game_page/widgets/game_page.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/config/constants.dart';
import '../models/recording_models.dart';
import '../services/diagnostic_reproduction_service.dart';
import '../services/recording_service.dart';
import '../services/replay_service.dart';

class DiagnosticReproductionPage extends StatefulWidget {
  const DiagnosticReproductionPage({required this.result, super.key});

  final DiagnosticReproductionResult result;

  static Future<void> importFromClipboard(BuildContext context) async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) {
      return;
    }
    if (data?.text == null || data!.text!.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(S.of(context).clipboardEmpty)));
      return;
    }
    try {
      final DiagnosticReproductionResult result =
          await DiagnosticReproductionService().importAndRestore(data.text!);
      if (!context.mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/diagnosticReproduction'),
          builder: (BuildContext context) =>
              DiagnosticReproductionPage(result: result),
        ),
      );
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              S.of(context).diagnosticImportFailed(error.toString()),
            ),
          ),
        );
      }
    }
  }

  @override
  State<DiagnosticReproductionPage> createState() =>
      _DiagnosticReproductionPageState();
}

class _DiagnosticReproductionPageState
    extends State<DiagnosticReproductionPage> {
  bool _restoring = false;

  Future<void> _restoreBackup() async {
    setState(() => _restoring = true);
    try {
      final bool restored = await DiagnosticReproductionService().restoreBackup(
        widget.result.backupId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              restored
                  ? S.of(context).diagnosticBackupRestored
                  : S.of(context).diagnosticNoBackup,
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _restoring = false);
      }
    }
  }

  Future<void> _startReplay() async {
    final RecordingSession session = DiagnosticReproductionService()
        .buildReplaySession(widget.result.bundle);
    ReplayService().stop(restartRecording: false);
    await RecordingService().stopRecording(
      notes: 'Auto-stopped: diagnostic replay started',
    );
    RecordingService().isSuppressed = true;
    final NavigatorState? navigator = currentNavigatorKey.currentState;
    if (navigator == null) {
      RecordingService().isSuppressed = false;
      return;
    }
    navigator.popUntil((Route<dynamic> route) => route.isFirst);
    final GameMode mode = _parseGameMode(session.gameMode);
    navigator.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/gamePage'),
        builder: (BuildContext context) =>
            GamePage(mode, key: const Key('diagnostic_replay_game_page')),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    unawaited(ReplayService().startReplay(session));
  }

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final bundle = widget.result.bundle;
    final String prettyConfigDifferences = const JsonEncoder.withIndent(
      '  ',
    ).convert(widget.result.configDifferences);
    final String prettyGame = const JsonEncoder.withIndent(
      '  ',
    ).convert(bundle.game);
    return Scaffold(
      appBar: AppBar(title: Text(strings.diagnosticReproduction)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(strings.diagnosticStateRestored),
          const SizedBox(height: 12),
          if (bundle.errorMessage case final String error) ...<Widget>[
            Text(strings.error(error)),
            const SizedBox(height: 12),
          ],
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(strings.diagnosticConfigurationDifferences),
            children: <Widget>[
              SelectableText(
                prettyConfigDifferences,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(strings.game),
            children: <Widget>[
              SelectableText(
                prettyGame,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              strings.diagnosticActionTimeline(
                bundle.actionTrail.events.length,
              ),
            ),
            children: bundle.actionTrail.events
                .map(
                  (event) => ListTile(
                    dense: true,
                    title: Text(event.actionId),
                    subtitle: Text(
                      '+${(event.elapsedMs / 1000).toStringAsFixed(1)}s · '
                      '${event.phase.name} · ${event.replayPolicy.name}',
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          if (bundle.logs case final String logs when logs.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(strings.logs),
              children: <Widget>[
                SelectableText(
                  logs,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ],
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.icon(
                onPressed: bundle.actionTrail.checkpoint == null
                    ? null
                    : _startReplay,
                icon: const Icon(Icons.play_arrow),
                label: Text(strings.replay),
              ),
              OutlinedButton.icon(
                onPressed: _restoring ? null : _restoreBackup,
                icon: const Icon(Icons.restore),
                label: Text(strings.diagnosticRestorePreImportState),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static GameMode _parseGameMode(String? value) {
    final String normalized = value?.toLowerCase() ?? '';
    const Set<GameMode> safeModes = <GameMode>{
      GameMode.humanVsAi,
      GameMode.humanVsHuman,
      GameMode.analysis,
    };
    for (final GameMode mode in safeModes) {
      if (mode.name.toLowerCase() == normalized ||
          normalized.endsWith(mode.name.toLowerCase())) {
        return mode;
      }
    }
    return GameMode.analysis;
  }
}
