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

/// Full-screen camera view for scanning a QR code.
///
/// Returns the decoded QR string via [Navigator.pop] on successful scan.
/// Also supports picking a QR code image from the device gallery.
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  bool _hasPopped = false;

  // True while an image picked from the gallery is being decoded.
  bool _isDecoding = false;

  // Called by the live camera scanner when a QR code is detected.
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

  // Lets the user pick an image from the gallery and attempts to decode a QR
  // code from it using the pure-Dart ZXing decoder.
  Future<void> _pickFromGallery() async {
    if (_isDecoding || _hasPopped) {
      return;
    }

    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );

    if (file == null) {
      return;
    }

    setState(() => _isDecoding = true);

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

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);

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
          else
            IconButton(
              icon: const Icon(Icons.photo_library_outlined),
              tooltip: s.qrCodeFromGallery,
              onPressed: _pickFromGallery,
            ),
        ],
      ),
      body: QRCodeDartScanView(
        formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
        onCapture: _onCapture,
      ),
    );
  }
}
