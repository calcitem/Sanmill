// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

import '../generated/intl/l10n.dart';
import '../shared/services/in_app_log_buffer.dart';

class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  final TextEditingController _filterController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _autoScroll = true;

  @override
  void dispose() {
    _filterController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _copyLogs(BuildContext context) async {
    final String text = InAppLogBuffer.instance.exportText(
      contains: _filterController.text,
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(S.of(context).copiedToClipboard)));
  }

  void _clearLogs(BuildContext context) {
    InAppLogBuffer.instance.clear();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(S.of(context).logViewerCleared)));
  }

  static Color _levelColor(ThemeData theme, Level level) {
    switch (level) {
      case Level.trace:
        return theme.colorScheme.onSurface.withValues(alpha: 0.65);
      // ignore: deprecated_member_use
      case Level.verbose:
        return theme.colorScheme.onSurface.withValues(alpha: 0.7);
      case Level.debug:
        return theme.colorScheme.onSurface.withValues(alpha: 0.8);
      case Level.info:
        return theme.colorScheme.onSurface;
      case Level.warning:
        return theme.colorScheme.tertiary;
      case Level.error:
      case Level.fatal:
        return theme.colorScheme.error;
      // ignore: deprecated_member_use
      case Level.wtf:
        return theme.colorScheme.error;
      case Level.all:
        return theme.colorScheme.onSurface;
      case Level.off:
        return theme.colorScheme.onSurface.withValues(alpha: 0.5);
      // ignore: deprecated_member_use
      case Level.nothing:
        return theme.colorScheme.onSurface.withValues(alpha: 0.5);
    }
  }

  void _maybeAutoScroll() {
    if (!_autoScroll) {
      return;
    }
    if (!_scrollController.hasClients) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).logViewerTitle),
        actions: <Widget>[
          IconButton(
            tooltip: S.of(context).copy,
            onPressed: () => _copyLogs(context),
            icon: const Icon(Icons.copy),
          ),
          IconButton(
            tooltip: S.of(context).logViewerClear,
            onPressed: () => _clearLogs(context),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Text(
              S.of(context).logViewerPrivacyHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _filterController,
                    decoration: InputDecoration(
                      hintText: S.of(context).logViewerFilterHint,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: S.of(context).clearFilter,
                        onPressed: () {
                          _filterController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: S.of(context).logViewerAutoScroll,
                  onPressed: () => setState(() => _autoScroll = !_autoScroll),
                  icon: Icon(_autoScroll ? Icons.arrow_downward : Icons.pause),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: InAppLogBuffer.instance.revision,
              builder: (BuildContext context, int _, Widget? child) {
                final List<InAppLogLine> lines =
                    InAppLogBuffer.instance.linesSnapshot;
                final String q = _filterController.text.trim();
                final bool hasQuery = q.isNotEmpty;

                final List<InAppLogLine> filtered = hasQuery
                    ? lines
                          .where((InAppLogLine l) => l.message.contains(q))
                          .toList(growable: false)
                    : lines;

                _maybeAutoScroll();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      S.of(context).logViewerEmpty,
                      style: theme.textTheme.bodyMedium,
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (BuildContext context, int index) {
                    final InAppLogLine line = filtered[index];
                    final Color color = _levelColor(theme, line.level);
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: SelectableText(
                        '${line.time.toIso8601String()} ${line.message}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: color,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
