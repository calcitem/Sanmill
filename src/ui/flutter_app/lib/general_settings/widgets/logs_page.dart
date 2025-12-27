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

class LogsPage extends StatelessWidget {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Get logs and reverse them to show latest first
    final List<OutputEvent> logs = memoryOutput.logs.reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).logs),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _downloadLogs(context, logs),
            tooltip: S.of(context).downloadLogs,
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: logs.length,
        itemBuilder: (BuildContext context, int index) {
          return _LogItem(log: logs[index]);
        },
      ),
    );
  }

  Future<void> _downloadLogs(
    BuildContext context,
    List<OutputEvent> logs,
  ) async {
    final StringBuffer buffer = StringBuffer();
    for (final OutputEvent log in logs) {
      for (final String line in log.lines) {
        buffer.writeln(line);
      }
      buffer.writeln('-' * 20);
    }

    final String content = buffer.toString();
    if (content.isEmpty) {
      return;
    }

    final Directory tempDir = await getTemporaryDirectory();
    final File file = File('${tempDir.path}/sanmill_logs.txt');
    await file.writeAsString(content);

    if (context.mounted) {
      // ignore: use_build_context_synchronously
      final RenderBox? box = context.findRenderObject() as RenderBox?;

      await Share.shareXFiles(
        <XFile>[XFile(file.path)],
        text: 'Sanmill Logs',
        sharePositionOrigin: box != null
            ? box.localToGlobal(Offset.zero) & box.size
            : null,
      );
    }
  }
}

class _LogItem extends StatelessWidget {
  final OutputEvent log;

  const _LogItem({required this.log});

  @override
  Widget build(BuildContext context) {
    Color color = Colors.black;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    if (log.level == Level.error || log.level == Level.fatal) {
      color = Colors.red;
    } else if (log.level == Level.warning) {
      color = Colors.orange;
    } else if (log.level == Level.debug) {
      color = Colors.grey;
    } else {
      color = isDark ? Colors.white : Colors.black;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: SelectableText(
        log.lines.join('\n'),
        style: TextStyle(color: color, fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }
}
