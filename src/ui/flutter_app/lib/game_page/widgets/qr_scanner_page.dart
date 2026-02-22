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
/// When multiple QR codes are detected via the camera, freezes the frame,
/// re-analyses it and opens [QrSelectionPage] for the user to tap the code
/// they want.  When multiple codes are found in a gallery image the same
/// visual selection page is used.
/// Gracefully handles devices without camera hardware by showing a fallback UI
/// that still allows importing QR codes from the gallery.
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  bool _hasPopped = false;

  /// True while capturing a still frame and navigating to the selection page.
  bool _isCapturing = false;

  /// True while processing a gallery image.
  bool _isDecoding = false;

  _CameraState _cameraState = _CameraState.checking;

  /// Camera controller provided by [ReaderWidget.onControllerCreated].
  CameraController? _cameraController;

  bool get _isBusy => _isCapturing || _isDecoding || _hasPopped;

  // ── Camera multi-scan callback ──────────────────────────────────────

  /// Called by [ReaderWidget] every frame where at least one code is found.
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

    // Multiple codes detected – capture a still image and let the user choose.
    _captureAndSelect();
  }

  // ── Camera capture & selection flow ─────────────────────────────────

  /// Stops the image stream, takes a still picture, re-analyses it and opens
  /// [QrSelectionPage].  Stopping the stream before [takePicture] is required
  /// on Android; the stream is not restarted because the page pops after
  /// selection (or the ReaderWidget reinitialises on resume if cancelled).
  Future<void> _captureAndSelect() async {
    if (_cameraController == null || _isBusy) {
      return;
    }

    setState(() => _isCapturing = true);

    try {
      // Stop the image stream first – required on Android before takePicture.
      if (_cameraController!.value.isStreamingImages) {
        try {
          await _cameraController!.stopImageStream();
        } catch (_) {
          // Ignore; best-effort stop.
        }
      }

      late final XFile picture;
      try {
        picture = await _cameraController!.takePicture();
      } catch (e) {
        // takePicture failed – fall back to nothing.
        return;
      }

      final Uint8List imageBytes = await picture.readAsBytes();

      // Re-analyse the still to obtain accurate positions.
      late final Codes freshCodes;
      try {
        freshCodes = await zx.readBarcodesImagePath(
          picture,
          DecodeParams(
            imageFormat: ImageFormat.rgb,
            format: Format.qrCode,
            isMultiScan: true,
            tryHarder: true,
            maxSize: 1920,
          ),
        );
      } catch (_) {
        return;
      }

      final List<Code> valid = freshCodes.codes
          .where((Code c) => c.isValid && c.text != null && c.text!.isNotEmpty)
          .toList();

      if (!mounted || valid.isEmpty) {
        return;
      }

      if (valid.length == 1) {
        _hasPopped = true;
        Navigator.of(context).pop(valid.first.text);
        return;
      }

      final String? selected = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (_) => QrSelectionPage(imageBytes: imageBytes, codes: valid),
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
  /// codes, and either returns the single result or opens [QrSelectionPage]
  /// for multiple codes.
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

      // Multiple codes – show image with tappable QR highlights.
      final String? selected = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (_) => QrSelectionPage(imageBytes: imageBytes, codes: valid),
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
  /// re-created on rebuild.  This prevents Flutter from treating a new widget
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
