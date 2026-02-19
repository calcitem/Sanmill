// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// session_list_page.dart

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/services/logger.dart';
import '../../shared/themes/app_theme.dart';
import '../models/recording_models.dart';
import '../services/recording_service.dart';
import '../services/replay_service.dart';

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
      final String path = await RecordingService().getSessionFilePath(
        session.id,
      );
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(path)],
          subject: 'Sanmill Recording ${session.id.substring(0, 8)}',
        ),
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

    // Pop the entire navigation stack back to the game page (the first/root
    // route).  This ensures that currentNavigatorKey.currentContext resolves
    // to a valid, mounted game-page context when the replay engine dispatches
    // board-tap and history-navigation events.
    Navigator.popUntil(context, (Route<dynamic> route) => route.isFirst);

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
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
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
              '${S.of(context).importSessionSuccess} '
              '(${session.events.length} ${S.of(context).sessionEventCount})',
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
              '${S.of(context).importSessionSuccess} '
              '(${session.events.length} ${S.of(context).sessionEventCount})',
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
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: S.of(context).importSession,
            onPressed: _showImportOptions,
          ),
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
    final String dateStr = _formatDate(session.startTime);
    final String durationStr = _formatDuration(session.duration);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Header row: date + game mode badge.
            Row(
              children: <Widget>[
                const Icon(
                  Icons.fiber_manual_record,
                  size: 10,
                  color: Colors.red,
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
                      session.gameMode!,
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
                _statChip(
                  Icons.timer_outlined,
                  '$durationStr ${S.of(context).sessionDuration}',
                ),
                const SizedBox(width: 12),
                _statChip(
                  Icons.list_alt,
                  '${session.events.length} '
                  '${S.of(context).sessionEventCount}',
                ),
              ],
            ),

            // Notes (if any).
            if (session.notes != null && session.notes!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                session.notes!,
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

  String _formatDate(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
        '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';
  }

  String _formatDuration(Duration d) {
    final int minutes = d.inMinutes;
    final int seconds = d.inSeconds % 60;
    return '${minutes}m ${seconds}s';
  }

  String _pad(int value) => value.toString().padLeft(2, '0');
}
