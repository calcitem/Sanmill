// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:convert' show utf8;

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../experience_recording/models/recording_models.dart';
import '../../experience_recording/services/recording_service.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../services/mill.dart';
import 'moves_list_page.dart';
import 'qr_scan_result_dialog.dart';
import 'qr_scanner_page.dart';

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
      _controller.text = text;
    });

    await _importText(text, recordAsLoad: false);
  }

  Future<void> _pickFileAndImport() async {
    if (_isImporting) {
      return;
    }

    final FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['pgn'],
    );
    if (!mounted || result == null) {
      return;
    }

    assert(result.files.length == 1, 'Expected exactly one PGN file.');
    final PlatformFile file = result.files.single;
    final String text = utf8.decode(
      await file.readAsBytes(),
      allowMalformed: true,
    );
    if (!mounted) {
      return;
    }

    if (text.trim().isEmpty) {
      rootScaffoldMessengerKey.currentState?.showSnackBarClear(
        S.of(context).importFailed,
      );
      return;
    }

    setState(() {
      _controller.text = text.trim();
    });

    await _importText(text.trim(), recordAsLoad: true);
  }

  Future<bool> _importText(String text, {required bool recordAsLoad}) async {
    setState(() {
      _isImporting = true;
    });

    final ({bool success, bool includedVariations}) importResult =
        await LoadService.importGameData(context, text);
    if (!mounted) {
      return false;
    }

    if (!importResult.success) {
      setState(() {
        _isImporting = false;
      });
      return false;
    }

    if (recordAsLoad) {
      RecordingService().recordEvent(
        RecordingEventType.gameLoad,
        <String, dynamic>{
          'pgnContent': text,
          'includeVariations': importResult.includedVariations,
        },
      );
    } else {
      ImportService.recordImportEvent(
        text,
        includeVariations: importResult.includedVariations,
      );
    }
    await LoadService.handleHistoryNavigation(
      context,
      includedVariations: importResult.includedVariations,
    );
    if (!mounted) {
      return false;
    }

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const MovesListPage(),
      ),
    );
    return true;
  }

  Future<void> _scanQrCodeAndImport() async {
    if (_isImporting) {
      return;
    }

    final String? scannedData = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (BuildContext context) => const QrScannerPage(),
      ),
    );

    if (!mounted) {
      return;
    }

    final String text = scannedData?.trim() ?? '';
    if (text.isEmpty) {
      rootScaffoldMessengerKey.currentState?.showSnackBarClear(
        S.of(context).qrCodeScanNoData,
      );
      return;
    }

    setState(() {
      _controller.text = text;
    });

    final bool imported = await _importText(text, recordAsLoad: false);
    if (!imported && mounted) {
      await showQrScanResultDialog(context, text);
    }
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: OutlinedButton.icon(
                key: const Key('import_game_from_file_button'),
                onPressed: _isImporting ? null : _pickFileAndImport,
                icon: const Icon(FluentIcons.folder_open_24_regular),
                label: Text(strings.importFromFile),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: OutlinedButton.icon(
                key: const Key('import_game_scan_qr_button'),
                onPressed: _isImporting ? null : _scanQrCodeAndImport,
                icon: const Icon(FluentIcons.scan_camera_24_regular),
                label: Text(strings.scanQrCode),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
