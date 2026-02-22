// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// qr_scan_result_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/services/logger.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';

/// Returns true when [text] is a well-formed absolute URL with an http,
/// https, or ftp scheme and a non-empty host.
bool isQrContentUrl(String text) {
  final Uri? uri = Uri.tryParse(text.trim());
  if (uri == null || !uri.isAbsolute) {
    return false;
  }
  final String scheme = uri.scheme.toLowerCase();
  return (scheme == 'http' || scheme == 'https' || scheme == 'ftp') &&
      uri.hasAuthority;
}

/// Shows a dialog that presents raw [content] that could not be recognised
/// as valid game data (move list or puzzle).
///
/// The optional [title] overrides the default dialog heading.  When
/// [content] is detected as a URL an "Open in Browser" button is also shown
/// so the user can tap to open it in the system browser.
Future<void> showQrScanResultDialog(
  BuildContext context,
  String content, {
  String? title,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext ctx) =>
        _QrScanResultDialog(content: content, title: title),
  );
}

class _QrScanResultDialog extends StatelessWidget {
  const _QrScanResultDialog({required this.content, this.title});

  final String content;

  /// Optional override for the dialog title.  Falls back to
  /// [S.qrCodeUnknownContent] when null.
  final String? title;

  /// Truncated preview for display; the full text is always copied.
  static const int _kPreviewLimit = 500;

  Future<void> _openInBrowser(BuildContext context) async {
    final Uri? uri = Uri.tryParse(content.trim());
    assert(
      uri != null,
      'Expected a valid URI; isQrContentUrl should have '
      'been called before enabling this button.',
    );
    if (uri == null) {
      return;
    }
    final bool launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      logger.e('Failed to launch URL from QR scan result: $uri');
    }
  }

  Future<void> _copyToClipboard(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!context.mounted) {
      return;
    }
    rootScaffoldMessengerKey.currentState?.showSnackBarClear(
      S.of(context).copiedToClipboard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);
    final bool isLink = isQrContentUrl(content);

    // Truncate very long content so the dialog stays readable.
    final String preview = content.length > _kPreviewLimit
        ? '${content.substring(0, _kPreviewLimit)}…'
        : content;

    return AlertDialog(
      title: Text(title ?? s.qrCodeUnknownContent),
      content: SingleChildScrollView(
        child: SelectableText(
          preview,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
      actions: <Widget>[
        if (isLink)
          TextButton.icon(
            onPressed: () => _openInBrowser(context),
            icon: const Icon(Icons.open_in_browser),
            label: Text(s.qrCodeOpenInBrowser),
          ),
        TextButton.icon(
          onPressed: () => _copyToClipboard(context),
          icon: const Icon(Icons.copy_outlined),
          label: Text(s.copy),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
    );
  }
}
