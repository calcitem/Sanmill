// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// qr_scanner_page.dart

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../generated/intl/l10n.dart';

/// Full-screen camera view for scanning a QR code.
///
/// Returns the decoded QR string via [Navigator.pop] on successful scan.
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: <BarcodeFormat>[BarcodeFormat.qrCode],
  );

  bool _hasPopped = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasPopped) {
      return;
    }

    for (final Barcode barcode in capture.barcodes) {
      final String? rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.isNotEmpty) {
        _hasPopped = true;
        Navigator.of(context).pop(rawValue);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(s.scanQrCode)),
      body: MobileScanner(controller: _controller, onDetect: _onDetect),
    );
  }
}
