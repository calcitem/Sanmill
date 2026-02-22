// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// qr_scanner_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:image_picker/image_picker.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/themes/app_theme.dart';

enum _CameraState { checking, available, unavailable }

/// Full-screen camera view for scanning QR codes using flutter_zxing.
///
/// Returns the decoded QR string via [Navigator.pop] on successful scan.
/// When multiple QR codes are detected simultaneously, shows a selection
/// dialog so the user can choose which code to read.
/// Also supports picking a QR code image from the device gallery.
/// Gracefully handles devices without camera hardware by showing a fallback UI
/// that still allows importing QR codes from the gallery.
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  bool _hasPopped = false;

  /// True while processing a gallery image.
  bool _isDecoding = false;

  _CameraState _cameraState = _CameraState.checking;

  /// True while the multi-code selection dialog is showing.
  bool _isShowingDialog = false;

  bool get _isBusy => _isShowingDialog || _isDecoding || _hasPopped;

  // ── Camera multi-scan callback ──────────────────────────────────────

  /// Called by [ReaderWidget] every time the camera frame is processed in
  /// multi-scan mode and at least one code is found.
  void _onMultiScan(Codes codes) {
    if (_isBusy) {
      return;
    }

    final List<Code> valid = codes.codes
        .where((Code c) => c.isValid && c.text != null && c.text!.isNotEmpty)
        .toList();

    if (valid.isEmpty) {
      return;
    }

    if (valid.length == 1) {
      _hasPopped = true;
      Navigator.of(context).pop(valid.first.text);
      return;
    }

    _showMultiCodeDialog(valid);
  }

  // ── Multi-code selection dialog ────────────────────────────────────

  /// Shows a bottom sheet listing all detected QR code texts so the user
  /// can pick which one to import.
  Future<void> _showMultiCodeDialog(List<Code> codes) async {
    if (_isShowingDialog || _hasPopped) {
      return;
    }

    setState(() => _isShowingDialog = true);

    final S s = S.of(context);

    final String? selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Text(
                    s.multipleQrCodesDetected,
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                const Divider(),
                ...codes.asMap().entries.map((MapEntry<int, Code> entry) {
                  final int index = entry.key;
                  final String text = entry.value.text ?? '';
                  final String preview = text.length > 80
                      ? '${text.substring(0, 80)}...'
                      : text;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(
                        ctx,
                      ).colorScheme.primaryContainer,
                      child: Text('${index + 1}'),
                    ),
                    title: Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.of(ctx).pop(text),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted) {
      return;
    }

    setState(() => _isShowingDialog = false);

    if (selected != null && selected.isNotEmpty) {
      _hasPopped = true;
      Navigator.of(context).pop(selected);
    }
  }

  // ── Gallery import ──────────────────────────────────────────────────

  /// Opens the gallery image picker, analyses the selected image for QR
  /// codes, and either returns the single result or shows a selection
  /// dialog when multiple codes are found.
  Future<void> _pickFromGallery() async {
    if (_isBusy) {
      return;
    }

    setState(() => _isDecoding = true);

    try {
      final XFile? file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
      );

      if (file == null) {
        return;
      }

      final Codes codes = await zx.readBarcodesImagePath(
        file,
        DecodeParams(
          imageFormat: ImageFormat.rgb,
          format: Format.qrCode,
          isMultiScan: true,
          tryHarder: true,
          maxSize: 1920,
        ),
      );

      List<Code> valid = codes.codes
          .where((Code c) => c.isValid && c.text != null && c.text!.isNotEmpty)
          .toList();

      // Fall back to single-scan if multi-scan found nothing.
      if (valid.isEmpty) {
        final Code single = await zx.readBarcodeImagePath(
          file,
          DecodeParams(
            imageFormat: ImageFormat.rgb,
            format: Format.qrCode,
            tryHarder: true,
            maxSize: 1920,
          ),
        );
        if (single.isValid && single.text != null && single.text!.isNotEmpty) {
          valid = <Code>[single];
        }
      }

      if (!mounted) {
        return;
      }

      if (valid.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).qrCodeNotFoundInImage)),
        );
        return;
      }

      if (valid.length == 1) {
        _hasPopped = true;
        Navigator.of(context).pop(valid.first.text);
        return;
      }

      await _showMultiCodeDialog(valid);
    } finally {
      if (mounted) {
        setState(() => _isDecoding = false);
      }
    }
  }

  // ── No-camera fallback UI ───────────────────────────────────────────

  Widget _buildNoCameraBody(S s) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.no_photography_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              s.noCameraAvailable,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(s.qrCodeFromGallery),
              onPressed: _pickFromGallery,
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────

  /// The [ReaderWidget] instance is kept as a field so that it is never
  /// re-created on rebuild. This prevents Flutter from treating a new widget
  /// instance as a different widget and discarding (disposing) the old one
  /// unnecessarily.
  late final Widget _readerWidget = ReaderWidget(
    codeFormat: Format.qrCode,
    isMultiScan: true,
    showScannerOverlay: false,
    showGallery: false,
    showToggleCamera: false,
    tryHarder: true,
    scanDelay: const Duration(milliseconds: 500),
    onControllerCreated: (CameraController? controller, Exception? error) {
      if (mounted) {
        setState(() {
          _cameraState = (error != null || controller == null)
              ? _CameraState.unavailable
              : _CameraState.available;
        });
      }
    },
    onMultiScan: _onMultiScan,
    onMultiScanFailure: (_) {},
  );

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);

    // flutter_zxing's ReaderWidget has a known bug in _stopCamera(): the
    // isStreamingImages condition is inverted, so stopImageStream() is called
    // even when the camera was never streaming.  To work around this we keep
    // the ReaderWidget in the widget tree via Offstage rather than removing it
    // when the camera reports unavailability.
    final Widget body;

    if (_hasPopped) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_cameraState == _CameraState.unavailable) {
      body = Stack(
        children: <Widget>[
          Offstage(child: _readerWidget),
          if (_isDecoding)
            const Center(child: CircularProgressIndicator())
          else
            _buildNoCameraBody(s),
        ],
      );
    } else {
      body = _readerWidget;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(s.scanQrCode, style: AppTheme.appBarTheme.titleTextStyle),
        actions: <Widget>[
          if (_isDecoding)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_cameraState != _CameraState.checking)
            IconButton(
              icon: const Icon(Icons.photo_library_outlined),
              tooltip: s.qrCodeFromGallery,
              onPressed: _pickFromGallery,
            ),
        ],
      ),
      body: body,
    );
  }
}
