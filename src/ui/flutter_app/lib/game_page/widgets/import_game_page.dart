// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../services/mill.dart';
import 'moves_list_page.dart';

class ImportGamePage extends StatefulWidget {
  const ImportGamePage({super.key});

  @override
  State<ImportGamePage> createState() => _ImportGamePageState();
}

class _ImportGamePageState extends State<ImportGamePage> {
  final TextEditingController _controller = TextEditingController();
  bool _isImporting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteAndImport() async {
    if (_isImporting) {
      return;
    }

    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String text = data?.text?.trim() ?? '';
    if (!mounted) {
      return;
    }

    if (text.isEmpty) {
      rootScaffoldMessengerKey.currentState?.showSnackBarClear(
        S.of(context).clipboardEmpty,
      );
      return;
    }

    setState(() {
      _isImporting = true;
      _controller.text = text;
    });

    final ({bool success, bool includedVariations}) importResult =
        await LoadService.importGameData(context, text);
    if (!mounted) {
      return;
    }

    if (!importResult.success) {
      setState(() {
        _isImporting = false;
      });
      return;
    }

    ImportService.recordImportEvent(
      text,
      includeVariations: importResult.includedVariations,
    );
    await LoadService.handleHistoryNavigation(
      context,
      includedVariations: importResult.includedVariations,
    );
    if (!mounted) {
      return;
    }

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const MovesListPage.analysisPanel(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      key: const Key('import_game_page_scaffold'),
      appBar: AppBar(title: Text(strings.importGame)),
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  key: const Key('import_game_paste_field'),
                  controller: _controller,
                  readOnly: true,
                  expands: true,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  onTap: _pasteAndImport,
                  decoration: InputDecoration(
                    hintText: strings.importFromClipboard,
                    alignLabelWithHint: true,
                    suffixIcon: IconButton(
                      key: const Key('import_game_paste_icon_button'),
                      icon: const Icon(FluentIcons.clipboard_paste_24_regular),
                      tooltip: strings.paste,
                      onPressed: _isImporting ? null : _pasteAndImport,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                key: const Key('import_game_from_clipboard_button'),
                onPressed: _isImporting ? null : _pasteAndImport,
                icon: _isImporting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(FluentIcons.clipboard_paste_24_regular),
                label: Text(strings.importFromClipboard),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
