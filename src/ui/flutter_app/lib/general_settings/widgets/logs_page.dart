// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// logs_page.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/services/logger.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  List<OutputEvent> _logs = <OutputEvent>[];
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _refreshLogs();
  }

  void _refreshLogs() {
    setState(() {
      _logs = memoryOutput.logs.reversed.toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.logs, style: AppTheme.appBarTheme.titleTextStyle),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshLogs,
            tooltip: s.refresh,
          ),
          IconButton(
            icon: _isDownloading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            onPressed: _isDownloading ? null : () => _downloadLogs(context),
            tooltip: s.downloadLogs,
          ),
        ],
      ),
      body: _logs.isEmpty ? _buildEmptyState(s) : _buildLogsList(),
    );
  }

  Widget _buildEmptyState(S s) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.article_outlined,
              size: 80,
              color: Theme.of(context).disabledColor,
            ),
            const SizedBox(height: 16),
            Text(
              s.noLogsAvailable,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).disabledColor,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              s.noLogsDescription,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).disabledColor,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _refreshLogs,
              icon: const Icon(Icons.refresh),
              label: Text(s.refresh),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogsList() {
    return ListView.builder(
      itemCount: _logs.length,
      itemBuilder: (BuildContext context, int index) {
        return _LogItem(log: _logs[index], index: index);
      },
    );
  }

  Future<void> _downloadLogs(BuildContext context) async {
    if (!mounted) {
      return;
    }

    final S s = S.of(context);

    if (_logs.isEmpty) {
      rootScaffoldMessengerKey.currentState?.showSnackBarClear(
        s.noLogsToDownload,
      );
      return;
    }

    setState(() {
      _isDownloading = true;
    });

    try {
      final StringBuffer buffer = StringBuffer();
      buffer.writeln('Sanmill Logs - ${DateTime.now().toIso8601String()}');
      buffer.writeln('=' * 50);
      buffer.writeln();

      for (final OutputEvent log in _logs.reversed) {
        final String levelStr = _getLevelString(log.level);
        buffer.writeln('[$levelStr]');
        for (final String line in log.lines) {
          buffer.writeln(line);
        }
        buffer.writeln();
      }

      final String content = buffer.toString();

      final Directory tempDir = await getTemporaryDirectory();
      final String timestamp =
          DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final File file = File('${tempDir.path}/sanmill_logs_$timestamp.txt');
      await file.writeAsString(content);

      if (!mounted) {
        return;
      }

      final RenderBox? box = context.findRenderObject() as RenderBox?;

      await Share.shareXFiles(
        <XFile>[XFile(file.path)],
        text: 'Sanmill Logs',
        sharePositionOrigin:
            box != null ? box.localToGlobal(Offset.zero) & box.size : null,
      );
    } catch (e) {
      if (mounted) {
        rootScaffoldMessengerKey.currentState?.showSnackBarClear(
          '${s.downloadFailed}: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  String _getLevelString(Level level) {
    switch (level) {
      case Level.trace:
        return 'TRACE';
      case Level.debug:
        return 'DEBUG';
      case Level.info:
        return 'INFO';
      case Level.warning:
        return 'WARN';
      case Level.error:
        return 'ERROR';
      case Level.fatal:
        return 'FATAL';
      default:
        return 'LOG';
    }
  }
}

class _LogItem extends StatelessWidget {
  final OutputEvent log;
  final int index;

  const _LogItem({required this.log, required this.index});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final Color levelColor = _getLevelColor(log.level);
    final Color backgroundColor = index.isEven
        ? (isDark ? Colors.grey[900]! : Colors.grey[50]!)
        : (isDark ? Colors.grey[850] ?? Colors.grey[800]! : Colors.white);

    final String levelStr = _getLevelString(log.level);
    final IconData levelIcon = _getLevelIcon(log.level);

    return Container(
      color: backgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Header with level indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: levelColor, width: 4),
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(levelIcon, size: 16, color: levelColor),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: levelColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    levelStr,
                    style: TextStyle(
                      color: levelColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Log content
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 12, 12),
            child: SelectableText(
              log.lines.join('\n'),
              style: TextStyle(
                color: isDark ? Colors.grey[300] : Colors.grey[800],
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: Theme.of(context).dividerColor,
          ),
        ],
      ),
    );
  }

  Color _getLevelColor(Level level) {
    switch (level) {
      case Level.trace:
        return Colors.grey;
      case Level.debug:
        return Colors.blue;
      case Level.info:
        return Colors.green;
      case Level.warning:
        return Colors.orange;
      case Level.error:
        return Colors.red;
      case Level.fatal:
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _getLevelString(Level level) {
    switch (level) {
      case Level.trace:
        return 'TRACE';
      case Level.debug:
        return 'DEBUG';
      case Level.info:
        return 'INFO';
      case Level.warning:
        return 'WARN';
      case Level.error:
        return 'ERROR';
      case Level.fatal:
        return 'FATAL';
      default:
        return 'LOG';
    }
  }

  IconData _getLevelIcon(Level level) {
    switch (level) {
      case Level.trace:
        return Icons.manage_search;
      case Level.debug:
        return Icons.bug_report_outlined;
      case Level.info:
        return Icons.info_outline;
      case Level.warning:
        return Icons.warning_amber;
      case Level.error:
        return Icons.error_outline;
      case Level.fatal:
        return Icons.dangerous_outlined;
      default:
        return Icons.article_outlined;
    }
  }
}
