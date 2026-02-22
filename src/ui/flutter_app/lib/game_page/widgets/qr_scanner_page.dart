// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// qr_scanner_page.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:image_picker/image_picker.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/themes/app_theme.dart';
import 'qr_selection_page.dart';

enum _CameraState { checking, available, unavailable }

/// Full-screen camera view for scanning QR codes using flutter_zxing.
///
/// Returns the decoded QR string via [Navigator.pop] on successful scan.
/// When multiple QR codes are detected simultaneously, navigates to
/// [QrSelectionPage] so the user can choose which code to read.
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

  /// True while capturing a still image and navigating to the selection page.
  bool _isCapturing = false;

  /// True while processing a gallery image.
  bool _isDecoding = false;

  _CameraState _cameraState = _CameraState.checking;

  /// Camera controller provided by [ReaderWidget.onControllerCreated].
  CameraController? _cameraController;

  bool get _isBusy => _isCapturing || _isDecoding || _hasPopped;

  // ── Camera multi-scan callback ──────────────────────────────────────

  /// Called by [ReaderWidget] every time the camera frame is processed in
  /// multi-scan mode.
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
      // Single QR code detected – return immediately (same as before).
      _hasPopped = true;
      Navigator.of(context).pop(valid.first.text);
      return;
    }

    // Multiple QR codes detected – capture a still image and let the user
    // choose which one to read.
    _captureAndSelect();
  }

  // ── Capture & select flow (camera) ──────────────────────────────────

  /// Takes a picture from the camera, re-analyses it for QR codes (to get
  /// accurate positions on the still image), and navigates to the selection
  /// page when more than one code is found.
  Future<void> _captureAndSelect() async {
    if (_isCapturing || _hasPopped || _cameraController == null) {
      return;
    }

    setState(() => _isCapturing = true);

    try {
      final XFile picture = await _cameraController!.takePicture();
      final Uint8List imageBytes = await picture.readAsBytes();

      // Re-analyse the captured still to obtain accurate positions.
      final Codes freshCodes = await zx.readBarcodesImagePath(
        picture,
        DecodeParams(
          imageFormat: ImageFormat.rgb,
          format: Format.qrCode,
          isMultiScan: true,
          tryHarder: true,
        ),
      );

      final List<Code> validFresh = freshCodes.codes
          .where((Code c) => c.isValid && c.text != null && c.text!.isNotEmpty)
          .toList();

      if (!mounted) {
        return;
      }

      if (validFresh.isEmpty) {
        // Edge case: the still captured between frames missed the codes.
        return;
      }

      if (validFresh.length == 1) {
        _hasPopped = true;
        Navigator.of(context).pop(validFresh.first.text);
        return;
      }

      // Navigate to the selection page.
      final String? selected = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (BuildContext context) =>
              QrSelectionPage(imageBytes: imageBytes, codes: validFresh),
        ),
      );

      if (selected != null && selected.isNotEmpty && mounted) {
        _hasPopped = true;
        Navigator.of(context).pop(selected);
      }
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  // ── Gallery import ──────────────────────────────────────────────────

  /// Opens the gallery image picker, analyses the selected image for QR
  /// codes, and either returns the single result or navigates to the
  /// selection page when multiple codes are found.
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

      final Uint8List imageBytes = await file.readAsBytes();

      final Codes codes = await zx.readBarcodesImagePath(
        file,
        DecodeParams(
          imageFormat: ImageFormat.rgb,
          format: Format.qrCode,
          isMultiScan: true,
          tryHarder: true,
        ),
      );

      final List<Code> valid = codes.codes
          .where((Code c) => c.isValid && c.text != null && c.text!.isNotEmpty)
          .toList();

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

      // Multiple codes – let the user choose.
      final String? selected = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (BuildContext context) =>
              QrSelectionPage(imageBytes: imageBytes, codes: valid),
        ),
      );

      if (selected != null && selected.isNotEmpty && mounted) {
        _hasPopped = true;
        Navigator.of(context).pop(selected);
      }
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
      _cameraController = controller;
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

    // Build the camera/fallback body.
    //
    // flutter_zxing's ReaderWidget has a known bug in _stopCamera(): the
    // isStreamingImages condition is inverted, so stopImageStream() is called
    // even when the camera was never streaming.  Because stopImageStream() is
    // declared `async`, the exception it throws becomes an unhandled Future
    // rejection.  To work around this we keep the ReaderWidget in the widget
    // tree via Offstage rather than removing it the moment the camera reports
    // unavailability; this prevents the premature dispose() call that triggers
    // the bug on the scanner page itself.
    final Widget body;

    if (_hasPopped) {
      // Camera is being torn down after a successful scan.
      body = const Center(child: CircularProgressIndicator());
    } else if (_cameraState == _CameraState.unavailable) {
      // Camera unavailable: overlay the fallback UI on top of the ReaderWidget
      // that is kept offstage.  Keeping it alive avoids disposing it while the
      // camera controller is still in a partially-initialised state.
      body = Stack(
        children: <Widget>[
          Offstage(child: _readerWidget),
          _isDecoding
              ? const Center(child: CircularProgressIndicator())
              : _buildNoCameraBody(s),
        ],
      );
    } else {
      // checking or available – show the live scanner.
      body = _readerWidget;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(s.scanQrCode, style: AppTheme.appBarTheme.titleTextStyle),
        actions: <Widget>[
          if (_isDecoding || _isCapturing)
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
