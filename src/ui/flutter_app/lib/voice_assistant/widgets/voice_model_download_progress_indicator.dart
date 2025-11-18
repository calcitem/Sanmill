// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// voice_model_download_progress_indicator.dart

import 'package:flutter/material.dart';

/// Custom widget that shows a circular progress indicator with percentage
/// Used to display voice model download progress in place of a Switch
class VoiceModelDownloadProgressIndicator extends StatelessWidget {
  const VoiceModelDownloadProgressIndicator({
    required this.progress,
    this.size = 48.0,
    super.key,
  });

  /// Download progress (0.0 to 1.0)
  final double progress;

  /// Size of the progress indicator
  final double size;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // Background circular progress indicator
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                colorScheme.primary,
              ),
              strokeWidth: 3.0,
            ),
          ),
          // Percentage text
          Text(
            '${(progress * 100).toInt()}%',
            style: TextStyle(
              fontSize: size * 0.25,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
