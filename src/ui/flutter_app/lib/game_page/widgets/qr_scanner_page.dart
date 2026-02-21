// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// qr_scanner_page.dart

import 'package:flutter/material.dart';
import 'package:qr_code_dart_scan/qr_code_dart_scan.dart';

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
  bool _hasPopped = false;

  void _onCapture(Result result) {
    if (_hasPopped) {
      return;
    }

    final String text = result.text;
    if (text != null && text.isNotEmpty) {
      _hasPopped = true;
      Navigator.of(context).pop(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(s.scanQrCode)),
      body: QRCodeDartScanView(
        formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
        onCapture: _onCapture,
      ),
    );
  }
}
