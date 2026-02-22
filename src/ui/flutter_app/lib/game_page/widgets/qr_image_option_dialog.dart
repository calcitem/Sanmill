// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// qr_image_option_dialog.dart

import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';

/// The user's choice for what image to embed in the exported QR code.
enum QrImageOption {
  /// No embedded image — plain QR code.
  none,

  /// Embed the current board position.
  board,

  /// Pick a custom image from the device gallery.
  custom,
}

/// A dialog that lets the user choose whether to embed an image in the
/// exported QR code before it is generated.
///
/// Returns [QrImageOption] via [Navigator.pop], or `null` if dismissed.
///
/// When [canEmbed] is `false` (the QR data exceeds the capacity for error
/// correction level H), the board and custom options are disabled and a
/// hint is displayed explaining why.
class QrImageOptionDialog extends StatelessWidget {
  const QrImageOptionDialog({required this.canEmbed, super.key});

  /// Whether the data is small enough to embed an image (≤ 1273 bytes).
  final bool canEmbed;

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);
    final ThemeData theme = Theme.of(context);

    return SimpleDialog(
      title: Text(s.exportQrCode),
      children: <Widget>[
        // Option 1: No image (always enabled)
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(QrImageOption.none),
          child: _OptionTile(
            icon: Icons.qr_code_2,
            label: s.qrImageOptionNone,
            enabled: true,
            theme: theme,
          ),
        ),

        // Option 2: Current board
        SimpleDialogOption(
          onPressed: canEmbed
              ? () => Navigator.of(context).pop(QrImageOption.board)
              : null,
          child: _OptionTile(
            icon: Icons.grid_on,
            label: s.qrImageOptionBoard,
            enabled: canEmbed,
            theme: theme,
          ),
        ),

        // Option 3: Custom image
        SimpleDialogOption(
          onPressed: canEmbed
              ? () => Navigator.of(context).pop(QrImageOption.custom)
              : null,
          child: _OptionTile(
            icon: Icons.image_outlined,
            label: s.qrImageOptionCustom,
            enabled: canEmbed,
            theme: theme,
          ),
        ),

        // Hint when embedding is disabled
        if (!canEmbed)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 8.0,
            ),
            child: Text(
              s.qrImageOptionDataTooLong,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

/// A single option row with an icon and large label text.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final double opacity = enabled ? 1.0 : 0.38;

    return Opacity(
      opacity: opacity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 28, color: theme.colorScheme.onSurface),
            const SizedBox(width: 16),
            Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
          ],
        ),
      ),
    );
  }
}
