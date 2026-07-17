// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// session_list_page.dart

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../game_page/services/mill.dart';
import '../../game_page/widgets/game_page.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/config/constants.dart';
import '../../shared/services/logger.dart';
import '../../shared/themes/app_theme.dart';
import '../models/recording_models.dart';
import '../services/recording_service.dart';
import '../services/replay_service.dart';

String recordingSessionNoteText(S strings, String notes) {
  return switch (notes) {
    RecordingSessionNotes.eventLimitReached =>
      strings.recordingStoppedAtEventLimit,
    RecordingSessionNotes.typedEventLimitReached =>
      strings.recordingStoppedAtDetailedEventLimit,
    RecordingSessionNotes.recordingInProgress =>
      strings.recordingStillInProgress,
    RecordingSessionNotes.replayStarted => strings.recordingStoppedForReplay,
    RecordingSessionNotes.diagnosticReplayStarted =>
      strings.recordingStoppedForDiagnosticReplay,
    RecordingSessionNotes.diagnosticReplayValidated =>
      strings.recordingDiagnosticReplayValidated,
    _ => notes,
  };
}

/// Page listing all saved recording sessions.
///
/// Each session card shows its date, duration, event count, and game mode.
/// Actions include: export (share), copy to clipboard, replay, and delete.
class SessionListPage extends StatefulWidget {
  const SessionListPage({super.key});

  @override
  State<SessionListPage> createState() => _SessionListPageState();
}

class _SessionListPageState extends State<SessionListPage> {
  static const String _logTag = '[SessionListPage]';

  List<RecordingSession> _sessions = <RecordingSession>[];
  bool _isLoading = true;

  GameMode? _tryParseGameMode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    final String v = raw.trim().toLowerCase();
    if (v.contains('humanvsai')) {
      return GameMode.humanVsAi;
    }
    if (v.contains('humanvshuman')) {
      return GameMode.humanVsHuman;
    }
    if (v.contains('aivsai')) {
      return GameMode.aiVsAi;
    }
    if (v.contains('analysis')) {
      return GameMode.analysis;
    }
    if (v.contains('humanvscloud')) {
      return GameMode.humanVsCloud;
    }
    if (v.contains('humanvslan')) {
      return GameMode.humanVsLAN;
    }
    if (v.contains('humanvsbluetooth')) {
      return GameMode.humanVsBluetooth;
    }
    if (v.contains('setupposition')) {
      return GameMode.setupPosition;
    }
    if (v.contains('puzzle')) {
      return GameMode.puzzle;
    }
    if (v.contains('testvialan')) {
      return GameMode.testViaLAN;
    }

    return null;
  }

  GameMode _parseGameMode(String? raw) =>
      _tryParseGameMode(raw) ?? GameMode.humanVsAi;

  String _gameModeLabel(BuildContext context, String? raw) {
    final S strings = S.of(context);
    return switch (_tryParseGameMode(raw)) {
      GameMode.humanVsAi => strings.playAgainstComputer,
      GameMode.humanVsHuman => strings.offlineBoard,
      GameMode.aiVsAi => strings.aiVsAi,
      GameMode.setupPosition => strings.boardEditor,
      GameMode.puzzle => strings.puzzle,
      GameMode.humanVsCloud => strings.humanVsCloud,
      GameMode.humanVsLAN => strings.humanVsLAN,
      GameMode.humanVsBluetooth => strings.humanVsBluetooth,
      GameMode.testViaLAN => strings.testViaLAN,
      GameMode.analysis => strings.analysis,
      null => strings.unknown,
    };
  }

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    final List<RecordingSession> sessions = await RecordingService()
        .listSessions();
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _isLoading = false;
      });
    }
  }

  // -----------------------------------------------------------------------
  // Actions
  // -----------------------------------------------------------------------

  Future<void> _shareSession(RecordingSession session) async {
    try {
      final String subject = S
          .of(context)
          .recordingSessionShareSubject(session.id.substring(0, 8));
      final String path = await RecordingService().getSessionFilePath(
        session.id,
      );
      await SharePlus.instance.share(
        ShareParams(files: <XFile>[XFile(path)], subject: subject),
      );
    } catch (e) {
      logger.e('$_logTag Share failed: $e');
    }
  }

  Future<void> _copyToClipboard(RecordingSession session) async {
    try {
      final RecordingSession? full = await RecordingService().loadSession(
        session.id,
      );
      if (full != null) {
        final String jsonStr = jsonEncode(full.toJson());
        await Clipboard.setData(ClipboardData(text: jsonStr));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.of(context).sessionExported)),
          );
        }
      }
    } catch (e) {
      logger.e('$_logTag Copy failed: $e');
    }
  }

  Future<void> _deleteSession(RecordingSession session) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(S.of(ctx).deleteSession),
        content: Text(S.of(ctx).confirmDeleteSession),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.of(ctx).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              S.of(ctx).delete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await RecordingService().deleteSession(session.id);
      unawaited(_loadSessions());
    }
  }

  Future<void> _deleteAllSessions() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(S.of(ctx).deleteAllSessions),
        content: Text(S.of(ctx).confirmDeleteAllSessions),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.of(ctx).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              S.of(ctx).delete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await RecordingService().deleteAllSessions();
      unawaited(_loadSessions());
    }
  }

  Future<void> _replaySession(RecordingSession session) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(S.of(ctx).replay),
        content: Text(S.of(ctx).replayInProgress),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.of(ctx).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.of(ctx).ok),
          ),
        ],
      ),
    );

    if (!(confirmed ?? false)) {
      return;
    }

    // Load the full session data before closing this page.
    final RecordingSession? fullSession = await RecordingService().loadSession(
      session.id,
    );
    if (fullSession == null || !mounted) {
      return;
    }

    // Ensure any previous replay is fully stopped.
    // Do not restart auto-recording here because we are about to start replay.
    ReplayService().stop(restartRecording: false);

    // Stop any ongoing recording before navigating to the replay board.
    await RecordingService().stopRecording(
      notes: RecordingSessionNotes.replayStarted,
    );

    // Prevent GamePage from auto-starting a new recording while we are
    // navigating to the board for replay.
    RecordingService().isSuppressed = true;

    final NavigatorState? rootNav = currentNavigatorKey.currentState;
    if (rootNav == null) {
      logger.e('$_logTag Cannot start replay: root navigator is null.');
      RecordingService().isSuppressed = false;
      return;
    }

    // Pop any pushed routes (DeveloperOptionsPage, SessionListPage, etc.).
    rootNav.popUntil((Route<dynamic> route) => route.isFirst);

    // Push a dedicated GamePage route so replay is visible even when the app
    // is currently showing a non-game Home drawer screen (e.g. Settings).
    final GameMode mode = _parseGameMode(fullSession.gameMode);
    rootNav.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/gamePage'),
        builder: (_) => GamePage(mode, key: const Key('replay_game_page')),
      ),
    );

    // Wait one frame so Flutter can finish the navigation animation and rebuild
    // the game-page widget tree before events start being dispatched.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // ReplayService uses currentNavigatorKey.currentContext internally, so no
    // context argument is needed here.
    unawaited(ReplayService().startReplay(fullSession));
  }

  /// Shows a bottom sheet with import options: pick file or paste from clipboard.
  void _showImportOptions() {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: Text(
                    S.of(context).importSession,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.file_open_outlined),
                  title: Text(S.of(context).importFromFile),
                  onTap: () {
                    Navigator.pop(ctx);
                    _importFromFile();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.content_paste),
                  title: Text(S.of(context).importFromClipboard),
                  onTap: () {
                    Navigator.pop(ctx);
                    _importFromClipboard();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Imports a session from a file selected via the system file picker.
  Future<void> _importFromFile() async {
    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['json'],
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final String? filePath = result.files.single.path;
      if (filePath == null) {
        return;
      }

      final RecordingSession? session = await RecordingService()
          .importSessionFromFile(filePath);

      if (!mounted) {
        return;
      }

      if (session != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              S
                  .of(context)
                  .recordingSessionImportedWithEventCount(
                    session.events.length,
                  ),
            ),
          ),
        );
        unawaited(_loadSessions());
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).importSessionFailed)),
        );
      }
    } catch (e) {
      logger.e('$_logTag Import from file error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).importSessionFailed)),
        );
      }
    }
  }

  /// Imports a session from JSON text on the system clipboard.
  Future<void> _importFromClipboard() async {
    try {
      final ClipboardData? clipData = await Clipboard.getData(
        Clipboard.kTextPlain,
      );

      if (clipData == null || clipData.text == null || clipData.text!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(S.of(context).clipboardEmpty)));
        }
        return;
      }

      // Quick sanity check: must look like JSON.
      final String text = clipData.text!.trim();
      if (!text.startsWith('{')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.of(context).importSessionFailed)),
          );
        }
        return;
      }

      final RecordingSession? session = await RecordingService()
          .importSessionFromJsonString(text);

      if (!mounted) {
        return;
      }

      if (session != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              S
                  .of(context)
                  .recordingSessionImportedWithEventCount(
                    session.events.length,
                  ),
            ),
          ),
        );
        unawaited(_loadSessions());
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).importSessionFailed)),
        );
      }
    } catch (e) {
      logger.e('$_logTag Import from clipboard error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).importSessionFailed)),
        );
      }
    }
  }

  // -----------------------------------------------------------------------
  // Build
  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).recordingSessions),
        actions: <Widget>[
          if (_sessions.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: S.of(context).deleteAllSessions,
              onPressed: _deleteAllSessions,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showImportOptions,
        tooltip: S.of(context).importSession,
        child: const Icon(Icons.file_download),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
          ? Center(
              child: Text(
                S.of(context).noRecordingSessions,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.listTileSubtitleColor,
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadSessions,
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _sessions.length,
                separatorBuilder: (BuildContext _, int i) =>
                    const SizedBox(height: 8),
                itemBuilder: (BuildContext ctx, int index) =>
                    _buildSessionCard(ctx, _sessions[index]),
              ),
            ),
    );
  }

  Widget _buildSessionCard(BuildContext context, RecordingSession session) {
    final String dateStr = _formatDate(context, session.startTime);
    final String durationStr = _formatDuration(context, session.duration);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Header row: date + game mode badge.
            Row(
              children: <Widget>[
                Icon(
                  session.isUnsafeLegacy
                      ? Icons.warning_amber_rounded
                      : Icons.fiber_manual_record,
                  size: 10,
                  color: session.isUnsafeLegacy ? Colors.orange : Colors.red,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    dateStr,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (session.gameMode != null)
                  Chip(
                    label: Text(
                      _gameModeLabel(context, session.gameMode),
                      style: const TextStyle(fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: 6),

            // Stats row.
            Row(
              children: <Widget>[
                _statChip(Icons.timer_outlined, durationStr),
                const SizedBox(width: 12),
                _statChip(
                  Icons.list_alt,
                  S
                      .of(context)
                      .recordingSessionEventCountValue(session.events.length),
                ),
              ],
            ),

            if (session.isUnsafeLegacy) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                S.of(context).unsafeLegacyRecording,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.orange),
              ),
            ] else if (session.notes != null &&
                session.notes!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                recordingSessionNoteText(S.of(context), session.notes!),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.listTileSubtitleColor,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            const SizedBox(height: 8),

            // Action buttons.
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                if (!session.isUnsafeLegacy) ...<Widget>[
                  TextButton.icon(
                    onPressed: () => _replaySession(session),
                    icon: const Icon(Icons.replay, size: 18),
                    label: Text(S.of(context).replay),
                  ),
                  TextButton.icon(
                    onPressed: () => _shareSession(session),
                    icon: const Icon(Icons.share, size: 18),
                    label: Text(S.of(context).exportSession),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: S.of(context).copy,
                    onPressed: () => _copyToClipboard(session),
                  ),
                ],
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Colors.red,
                  ),
                  tooltip: S.of(context).deleteSession,
                  onPressed: () => _deleteSession(session),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: AppTheme.listTileSubtitleColor),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.listTileSubtitleColor,
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------------------
  // Formatting helpers
  // -----------------------------------------------------------------------

  String _formatDate(BuildContext context, DateTime dateTime) {
    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );
    final String date = localizations.formatShortDate(dateTime);
    final String time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(dateTime),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return '$date $time';
  }

  String _formatDuration(BuildContext context, Duration duration) {
    return S
        .of(context)
        .recordingSessionDurationValue(
          duration.inMinutes,
          duration.inSeconds % Duration.secondsPerMinute,
        );
  }
}
