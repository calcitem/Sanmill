// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// model_info_dialog.dart

part of '../voice_assistant_settings_page.dart';

/// Dialog showing model information
class _ModelInfoDialog extends StatelessWidget {
  const _ModelInfoDialog();

  @override
  Widget build(BuildContext context) {
    final S loc = S.of(context);
    final VoiceAssistantSettings settings = DB().voiceAssistantSettings;
    final VoiceAssistantService service = VoiceAssistantService();

    return AlertDialog(
      title: Text(loc.voiceAssistantModelInfo),
      content: FutureBuilder<String?>(
        future: service.getModelSize(),
        builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
          final String sizeInfo = snapshot.hasData
              ? '${loc.voiceAssistantModelSize}: ${snapshot.data}'
              : '${loc.voiceAssistantModelSize}: ${loc.unknown}';

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _buildInfoRow(
                  loc.voiceAssistantModelType,
                  settings.modelType.name,
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  loc.language,
                  settings.language,
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  loc.status,
                  settings.modelDownloaded
                      ? loc.voiceAssistantModelDownloaded
                      : loc.voiceAssistantModelNotDownloaded,
                ),
                const SizedBox(height: 8),
                if (settings.modelDownloaded) ...<Widget>[
                  _buildInfoRow('', sizeInfo),
                  const SizedBox(height: 8),
                  _buildInfoRow(
                    loc.voiceAssistantModelPath,
                    settings.modelPath,
                  ),
                ],
              ],
            ),
          );
        },
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(loc.close),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (label.isNotEmpty) ...<Widget>[
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }
}
