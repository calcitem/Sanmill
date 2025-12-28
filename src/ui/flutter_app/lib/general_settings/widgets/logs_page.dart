// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// logs_page.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
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
  bool _isProcessing = false;

  // Selection mode state
  bool _isSelectionMode = false;
  int? _selectionStart;
  int? _selectionEnd;

  // Scroll controller for scrolling to bottom
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _refreshLogs();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _refreshLogs() {
    setState(() {
      _logs = memoryOutput.logs.reversed.toList();
    });
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectionStart = null;
        _selectionEnd = null;
      }
    });
  }

  void _onLogTap(int index) {
    if (!_isSelectionMode) {
      return;
    }

    setState(() {
      if (_selectionStart == null) {
        // Select start point
        _selectionStart = index;
        _selectionEnd = null;
      } else if (_selectionEnd == null) {
        // Select end point
        if (index >= _selectionStart!) {
          _selectionEnd = index;
        } else {
          // If tapped before start, swap them
          _selectionEnd = _selectionStart;
          _selectionStart = index;
        }
      } else {
        // Reset and start new selection
        _selectionStart = index;
        _selectionEnd = null;
      }
    });
  }

  bool _isLogSelected(int index) {
    if (_selectionStart == null) {
      return false;
    }
    if (_selectionEnd == null) {
      return index == _selectionStart;
    }
    return index >= _selectionStart! && index <= _selectionEnd!;
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.logs, style: AppTheme.appBarTheme.titleTextStyle),
        actions: <Widget>[
          if (_isSelectionMode) ...<Widget>[
            // Copy selected button in selection mode
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: _copySelectedLogs,
              tooltip: s.copySelected,
            ),
            // Cancel selection mode
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _toggleSelectionMode,
              tooltip: s.cancel,
            ),
          ] else ...<Widget>[
            // Regular mode buttons
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: _toggleSelectionMode,
              tooltip: s.selectMode,
            ),
            IconButton(
              icon: const Icon(Icons.vertical_align_bottom),
              onPressed: _logs.isEmpty ? null : _scrollToBottom,
              tooltip: s.scrollToBottom,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshLogs,
              tooltip: s.refresh,
            ),
            IconButton(
              icon: _isProcessing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              onPressed: _isProcessing ? null : () => _downloadLogs(context),
              tooltip: s.downloadLogs,
            ),
            IconButton(
              icon: _isProcessing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.share),
              onPressed: _isProcessing ? null : () => _shareLogs(context),
              tooltip: s.shareLogs,
            ),
          ],
        ],
      ),
      body: _logs.isEmpty
          ? _buildEmptyState(s)
          : Column(
              children: <Widget>[
                if (_isSelectionMode)
                  _buildSelectionHint(s)
                else
                  _buildLogStats(s),
                Expanded(child: _buildLogsList()),
              ],
            ),
    );
  }

  Widget _buildSelectionHint(S s) {
    final String hintText;
    if (_selectionStart == null) {
      hintText = s.selectStartPoint;
    } else if (_selectionEnd == null) {
      hintText = s.selectEndPoint;
    } else {
      final int count = _selectionEnd! - _selectionStart! + 1;
      hintText = '$count logs selected';
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Row(
        children: <Widget>[
          Icon(
            Icons.info_outline,
            size: 16,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hintText,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogStats(S s) {
    final int totalLogs = _logs.length;
    final int bufferSize = memoryOutput.bufferSize;
    final bool isBufferFull = totalLogs >= bufferSize;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: isBufferFull
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: <Widget>[
          Icon(
            isBufferFull ? Icons.warning_amber : Icons.info_outline,
            size: 16,
            color: isBufferFull
                ? Theme.of(context).colorScheme.onErrorContainer
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isBufferFull
                  ? s.logsBufferFull(totalLogs, bufferSize)
                  : s.logsCount(totalLogs, bufferSize),
              style: TextStyle(
                color: isBufferFull
                    ? Theme.of(context).colorScheme.onErrorContainer
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
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
      controller: _scrollController,
      itemCount: _logs.length,
      itemBuilder: (BuildContext context, int index) {
        return _LogItem(
          log: _logs[index],
          index: index,
          isSelected: _isLogSelected(index),
          isSelectionMode: _isSelectionMode,
          onTap: () => _onLogTap(index),
        );
      },
    );
  }

  Future<void> _copySelectedLogs() async {
    final S s = S.of(context);

    if (_selectionStart == null) {
      rootScaffoldMessengerKey.currentState?.showSnackBarClear(
        s.nothingSelected,
      );
      return;
    }

    final int start = _selectionStart!;
    final int end = _selectionEnd ?? _selectionStart!;

    final StringBuffer buffer = StringBuffer();
    for (int i = start; i <= end; i++) {
      final OutputEvent log = _logs[i];
      final String levelStr = _getLevelString(log.level);
      buffer.writeln('[$levelStr]');
      log.lines.forEach(buffer.writeln);
      if (i < end) {
        buffer.writeln();
      }
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));

    if (!mounted) {
      return;
    }

    rootScaffoldMessengerKey.currentState?.showSnackBarClear(
      s.copiedToClipboard,
    );

    // Exit selection mode after copying
    _toggleSelectionMode();
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
      _isProcessing = true;
    });

    try {
      // Request storage permission on Android
      if (Platform.isAndroid) {
        final PermissionStatus status = await Permission.storage.request();
        if (!status.isGranted) {
          // Try with manageExternalStorage for Android 11+
          final PermissionStatus manageStatus = await Permission
              .manageExternalStorage
              .request();
          if (!manageStatus.isGranted) {
            if (mounted) {
              rootScaffoldMessengerKey.currentState?.showSnackBarClear(
                '${s.downloadFailed}: Storage permission denied',
              );
            }
            return;
          }
        }
      }

      final StringBuffer buffer = StringBuffer();
      buffer.writeln('${s.logs} - ${DateTime.now().toIso8601String()}');
      buffer.writeln('=' * 50);
      buffer.writeln();

      for (final OutputEvent log in _logs.reversed) {
        final String levelStr = _getLevelString(log.level);
        buffer.writeln('[$levelStr]');
        log.lines.forEach(buffer.writeln);
        buffer.writeln();
      }

      final String content = buffer.toString();

      // Get appropriate directory for each platform
      Directory? targetDir;
      if (Platform.isAndroid) {
        // Use Downloads directory on Android
        targetDir = Directory('/storage/emulated/0/Download');
        if (!targetDir.existsSync()) {
          targetDir = await getExternalStorageDirectory();
        }
      } else if (Platform.isIOS) {
        // Use app documents directory on iOS
        targetDir = await getApplicationDocumentsDirectory();
      } else {
        // Use downloads directory on desktop platforms
        targetDir = await getDownloadsDirectory();
        targetDir ??= await getApplicationDocumentsDirectory();
      }

      final String timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')[0];
      final File file = File('${targetDir!.path}/logs_$timestamp.txt');
      await file.writeAsString(content);

      if (!mounted) {
        return;
      }

      rootScaffoldMessengerKey.currentState?.showSnackBarClear(
        s.downloadSuccess(file.path),
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
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _shareLogs(BuildContext context) async {
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
      _isProcessing = true;
    });

    try {
      final StringBuffer buffer = StringBuffer();
      buffer.writeln('${s.logs} - ${DateTime.now().toIso8601String()}');
      buffer.writeln('=' * 50);
      buffer.writeln();

      for (final OutputEvent log in _logs.reversed) {
        final String levelStr = _getLevelString(log.level);
        buffer.writeln('[$levelStr]');
        log.lines.forEach(buffer.writeln);
        buffer.writeln();
      }

      final String content = buffer.toString();

      final Directory tempDir = await getTemporaryDirectory();
      final String timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')[0];
      final File file = File('${tempDir.path}/logs_$timestamp.txt');
      await file.writeAsString(content);

      if (!mounted) {
        return;
      }

      await SharePlus.instance.share(
        ShareParams(files: <XFile>[XFile(file.path)], text: s.logs),
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
          _isProcessing = false;
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
      case Level.all:
        return 'ALL';
      // ignore: deprecated_member_use
      case Level.verbose:
        return 'VERBOSE';
      // ignore: deprecated_member_use
      case Level.wtf:
        return 'WTF';
      // ignore: deprecated_member_use
      case Level.nothing:
        return 'NOTHING';
      case Level.off:
        return 'OFF';
    }
  }
}

class _LogItem extends StatelessWidget {
  const _LogItem({
    required this.log,
    required this.index,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onTap,
  });

  final OutputEvent log;
  final int index;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final Color levelColor = _getLevelColor(log.level);
    Color backgroundColor = index.isEven
        ? (isDark ? Colors.grey[900]! : Colors.grey[50]!)
        : (isDark ? Colors.grey[850] ?? Colors.grey[800]! : Colors.white);

    // Highlight selected logs
    if (isSelected) {
      backgroundColor = Theme.of(context).colorScheme.primaryContainer;
    }

    final String levelStr = _getLevelString(log.level);
    final IconData levelIcon = _getLevelIcon(log.level);

    return InkWell(
      onTap: isSelectionMode ? onTap : null,
      child: Container(
        color: backgroundColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Header with level indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: levelColor, width: 4)),
              ),
              child: Row(
                children: <Widget>[
                  Icon(levelIcon, size: 16, color: levelColor),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
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
                  if (isSelected) ...<Widget>[
                    const Spacer(),
                    Icon(
                      Icons.check_circle,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ],
              ),
            ),
            // Log content
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 12, 12),
              child: SelectableText(
                log.lines.join('\n'),
                style: TextStyle(
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : (isDark ? Colors.grey[300] : Colors.grey[800]),
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
      case Level.all:
        return Colors.blueGrey;
      // ignore: deprecated_member_use
      case Level.verbose:
        return Colors.grey;
      // ignore: deprecated_member_use
      case Level.wtf:
        return Colors.deepPurple;
      // ignore: deprecated_member_use
      case Level.nothing:
        return Colors.grey;
      case Level.off:
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
      case Level.all:
        return 'ALL';
      // ignore: deprecated_member_use
      case Level.verbose:
        return 'VERBOSE';
      // ignore: deprecated_member_use
      case Level.wtf:
        return 'WTF';
      // ignore: deprecated_member_use
      case Level.nothing:
        return 'NOTHING';
      case Level.off:
        return 'OFF';
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
      case Level.all:
        return Icons.list_alt;
      // ignore: deprecated_member_use
      case Level.verbose:
        return Icons.article_outlined;
      // ignore: deprecated_member_use
      case Level.wtf:
        return Icons.whatshot_outlined;
      // ignore: deprecated_member_use
      case Level.nothing:
        return Icons.block;
      case Level.off:
        return Icons.block;
    }
  }
}
