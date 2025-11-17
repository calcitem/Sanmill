// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// download_model_dialog.dart

part of '../voice_assistant_settings_page.dart';

/// Dialog to confirm model download
class _DownloadModelDialog extends StatelessWidget {
  const _DownloadModelDialog();

  @override
  Widget build(BuildContext context) {
    final S loc = S.of(context);
    final VoiceAssistantSettings settings = DB().voiceAssistantSettings;
    final String modelName = settings.modelType.name;

    return AlertDialog(
      title: Text(loc.voiceAssistantDownloadModel),
      content: Text(
        '${loc.voiceAssistantDownloadModelMessage}\n\n'
        '${loc.model}: $modelName\n'
        '${loc.language}: ${settings.language}',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(loc.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(loc.download),
        ),
      ],
    );
  }
}

/// Dialog showing download progress
class _DownloadProgressDialog extends StatefulWidget {
  const _DownloadProgressDialog({required this.service});

  final VoiceAssistantService service;

  @override
  State<_DownloadProgressDialog> createState() =>
      _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  late final ModelDownloader _downloader;
  bool _isDownloading = true;

  @override
  void initState() {
    super.initState();
    _downloader = widget.service.modelDownloader;
    _startDownload();
  }

  Future<void> _startDownload() async {
    final bool success = await widget.service.downloadModel(context);

    if (mounted) {
      setState(() {
        _isDownloading = false;
      });

      // Close dialog after a short delay
      await Future<void>.delayed(const Duration(seconds: 1));

      if (mounted) {
        Navigator.pop(context);

        // Show result message
        SnackBarService.showMessage(
          context,
          success
              ? S.of(context).voiceAssistantModelDownloadSuccess
              : S.of(context).voiceAssistantModelDownloadFailed,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final S loc = S.of(context);

    return PopScope(
      canPop: !_isDownloading,
      child: AlertDialog(
        title: Text(loc.voiceAssistantDownloading),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ValueListenableBuilder<double>(
              valueListenable: _downloader.downloadProgress,
              builder: (BuildContext context, double progress, Widget? child) {
                return Column(
                  children: <Widget>[
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 16),
                    Text('${(progress * 100).toStringAsFixed(1)}%'),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<String>(
              valueListenable: _downloader.downloadStatus,
              builder: (BuildContext context, String status, Widget? child) {
                return Text(status);
              },
            ),
          ],
        ),
        actions: <Widget>[
          if (!_isDownloading)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(loc.close),
            ),
        ],
      ),
    );
  }
}
