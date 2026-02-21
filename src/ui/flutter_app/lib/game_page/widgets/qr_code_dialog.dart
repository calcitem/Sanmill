// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// qr_code_dialog.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';

/// Displays a QR code containing the given [data] with options to save or
/// share the generated image.
///
/// An optional [title] can be provided to override the default dialog heading.
class QrCodeDialog extends StatefulWidget {
  const QrCodeDialog({required this.data, this.title, super.key});

  final String data;

  /// Custom dialog title. Falls back to [S.qrCodeTitle] when null.
  final String? title;

  @override
  State<QrCodeDialog> createState() => _QrCodeDialogState();
}

class _QrCodeDialogState extends State<QrCodeDialog> {
  final GlobalKey _repaintBoundaryKey = GlobalKey();

  Future<Uint8List?> _captureQrImage() async {
    final RenderRepaintBoundary? boundary =
        _repaintBoundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      return null;
    }

    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return byteData?.buffer.asUint8List();
  }

  Future<void> _saveToGallery() async {
    final Uint8List? pngBytes = await _captureQrImage();
    if (pngBytes == null) {
      return;
    }

    final dynamic result = await ImageGallerySaverPlus.saveImage(
      pngBytes,
      quality: 100,
      name: 'sanmill_qr_${DateTime.now().millisecondsSinceEpoch}',
    );

    if (!mounted) {
      return;
    }

    final bool isSuccess = result is Map && result['isSuccess'] == true;
    final String message = isSuccess
        ? S.of(context).qrCodeSaved
        : S.of(context).qrCodeSaveFailed;
    rootScaffoldMessengerKey.currentState?.showSnackBarClear(message);
  }

  Future<void> _shareQrCode() async {
    final Uint8List? pngBytes = await _captureQrImage();
    if (pngBytes == null) {
      return;
    }

    final Directory tempDir = await getTemporaryDirectory();
    final String filePath =
        '${tempDir.path}/sanmill_qr_${DateTime.now().millisecondsSinceEpoch}.png';
    final File file = File(filePath);
    await file.writeAsBytes(pngBytes);

    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(filePath)],
        subject: 'Sanmill Move List QR Code',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);

    final Size screenSize = MediaQuery.sizeOf(context);
    final double maxDialogWidth = math.min(screenSize.width * 0.92, 360.0);
    final double qrSizeUnclamped = maxDialogWidth - 80.0;
    final double qrSize = qrSizeUnclamped < 120.0
        ? 120.0
        : (qrSizeUnclamped > 280.0 ? 280.0 : qrSizeUnclamped);

    final QrPainter painter = QrPainter(
      data: widget.data,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      gapless: true,
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxDialogWidth),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        widget.title ?? s.qrCodeTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonLabel,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                RepaintBoundary(
                  key: _repaintBoundaryKey,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(16),
                    child: SizedBox.square(
                      dimension: qrSize,
                      child: CustomPaint(painter: painter),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: <Widget>[
                    TextButton.icon(
                      onPressed: _saveToGallery,
                      icon: const Icon(Icons.save_alt),
                      label: Text(s.saveToGallery),
                    ),
                    TextButton.icon(
                      onPressed: _shareQrCode,
                      icon: const Icon(Icons.share),
                      label: Text(s.shareQrCode),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
