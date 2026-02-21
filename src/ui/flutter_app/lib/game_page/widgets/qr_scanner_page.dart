// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// qr_scanner_page.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:qr_code_dart_decoder/qr_code_dart_decoder.dart';
import 'package:qr_code_dart_scan/qr_code_dart_scan.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/themes/app_theme.dart';

enum _CameraState { checking, available, unavailable }

/// Full-screen camera view for scanning a QR code.
///
/// Returns the decoded QR string via [Navigator.pop] on successful scan.
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

  bool _isDecoding = false;

  _CameraState _cameraState = _CameraState.checking;

  // When true the scanner widget is removed from the tree so the camera
  // package can tear down without racing against pending async operations
  // (lockCaptureOrientation, buildPreview, etc.).
  bool get _scannerActive =>
      !_isDecoding && !_hasPopped && _cameraState == _CameraState.available;

  @override
  void initState() {
    super.initState();
    _checkCameraAvailability();
  }

  Future<void> _checkCameraAvailability() async {
    try {
      final List<CameraDescription> cameras = await availableCameras();
      if (mounted) {
        setState(() {
          _cameraState = cameras.isNotEmpty
              ? _CameraState.available
              : _CameraState.unavailable;
        });
      }
    } on Exception {
      if (mounted) {
        setState(() => _cameraState = _CameraState.unavailable);
      }
    }
  }

  void _onCapture(Result result) {
    if (_hasPopped) {
      return;
    }

    final String text = result.text;
    if (text.isNotEmpty) {
      _hasPopped = true;
      Navigator.of(context).pop(text);
    }
  }

  // Remove the scanner from the widget tree first, wait one frame so the
  // camera controller is fully disposed, then actually pop the route. This
  // avoids CameraController-use-after-dispose crashes from in-flight async
  // operations such as lockCaptureOrientation.
  Future<void> _safePopPage() async {
    if (_hasPopped) {
      return;
    }
    setState(() => _hasPopped = true);
    if (_cameraState == _CameraState.available) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isDecoding || _hasPopped) {
      return;
    }

    // Remove QRCodeDartScanView from the tree BEFORE opening the gallery
    // picker. ImagePicker causes the app to go inactive, which makes the
    // package dispose its CameraController. If the scanner widget is still
    // mounted, CameraPreview's ValueListenableBuilder may try to call
    // buildPreview() on the disposed controller during a pending frame.
    setState(() => _isDecoding = true);

    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );

    if (file == null) {
      if (mounted) {
        setState(() => _isDecoding = false);
      }
      return;
    }

    try {
      final Uint8List bytes = await file.readAsBytes();

      // qr_code_dart_decoder's toLuminanceSourceFromBytes reads 4 bytes per
      // pixel (j += 4, assuming RGBA). image v4 decodes JPEG as 3-channel RGB
      // (3 bytes/pixel), causing byte-offset misalignment and wrong luminance
      // values for every pixel. Convert to RGBA and re-encode as PNG so that
      // decodeFile's internal decodeImage call always yields 4 channels.
      final img.Image? decodedImg = img.decodeImage(bytes);
      final Uint8List decodeInput =
          (decodedImg != null && decodedImg.numChannels != 4)
          ? Uint8List.fromList(
              img.encodePng(decodedImg.convert(numChannels: 4)),
            )
          : bytes;

      final Result? result = await QrCodeDartDecoder(
        formats: <BarcodeFormat>[BarcodeFormat.qrCode],
      ).decodeFile(decodeInput);

      if (!mounted) {
        return;
      }

      if (result != null && result.text.isNotEmpty) {
        _hasPopped = true;
        Navigator.of(context).pop(result.text);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).qrCodeNotFoundInImage)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDecoding = false);
      }
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);

    final Widget body;
    switch (_cameraState) {
      case _CameraState.checking:
        body = const Center(child: CircularProgressIndicator());
      case _CameraState.unavailable:
        body = _isDecoding
            ? const Center(child: CircularProgressIndicator())
            : _buildNoCameraBody(s);
      case _CameraState.available:
        body = _scannerActive
            ? QRCodeDartScanView(
                formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
                onCapture: _onCapture,
              )
            : const Center(child: CircularProgressIndicator());
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) {
          _safePopPage();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.scanQrCode, style: AppTheme.appBarTheme.titleTextStyle),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _safePopPage,
          ),
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
            else if (_cameraState == _CameraState.available)
              IconButton(
                icon: const Icon(Icons.photo_library_outlined),
                tooltip: s.qrCodeFromGallery,
                onPressed: _pickFromGallery,
              ),
          ],
        ),
        body: body,
      ),
    );
  }
}
