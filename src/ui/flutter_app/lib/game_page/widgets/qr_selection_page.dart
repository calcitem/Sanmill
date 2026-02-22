// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// qr_selection_page.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/themes/app_theme.dart';

/// Indicator size for the green circle overlay markers.
const double _kIndicatorSize = 48.0;

/// Displays a captured or picked image overlaid with tappable indicators at
/// each detected QR code position, allowing the user to choose which QR code
/// to read when multiple codes are present.
///
/// Returns the selected QR code text via [Navigator.pop].
class QrSelectionPage extends StatefulWidget {
  const QrSelectionPage({
    required this.imageBytes,
    required this.codes,
    super.key,
  });

  /// Raw bytes of the image containing QR codes.
  final Uint8List imageBytes;

  /// Detected QR codes with position data.
  final List<Code> codes;

  @override
  State<QrSelectionPage> createState() => _QrSelectionPageState();
}

class _QrSelectionPageState extends State<QrSelectionPage> {
  /// Key used to measure the actual rendered size of the image widget.
  final GlobalKey _imageKey = GlobalKey();

  /// Rendered image area dimensions and offset within the layout, computed
  /// after the first frame.
  Rect? _imageRect;

  @override
  void initState() {
    super.initState();
    // Schedule a post-frame callback to measure the image layout.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureImage());
  }

  /// Measure the rendered image widget to determine display coordinates.
  void _measureImage() {
    final RenderBox? box =
        _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return;
    }

    final Size imageSize = box.size;
    final Offset imageOffset = box.localToGlobal(Offset.zero);

    // Find the Stack's RenderBox to compute relative offset.
    final RenderBox? stackBox = context.findRenderObject() as RenderBox?;
    final Offset stackOffset =
        stackBox?.localToGlobal(Offset.zero) ?? Offset.zero;

    if (mounted) {
      setState(() {
        _imageRect = Rect.fromLTWH(
          imageOffset.dx - stackOffset.dx,
          imageOffset.dy - stackOffset.dy,
          imageSize.width,
          imageSize.height,
        );
      });
    }
  }

  /// Compute the center point of a QR code in image coordinates.
  Offset _qrCenter(Position pos) {
    final double cx = (pos.topLeftX + pos.topRightX + pos.bottomLeftX +
            pos.bottomRightX) /
        4.0;
    final double cy = (pos.topLeftY + pos.topRightY + pos.bottomLeftY +
            pos.bottomRightY) /
        4.0;
    return Offset(cx, cy);
  }

  /// Build the green-circle-with-white-arrow indicator positioned at the
  /// center of a detected QR code.
  Widget _buildIndicator(Code code) {
    final Position? pos = code.position;
    if (pos == null || _imageRect == null) {
      return const SizedBox.shrink();
    }

    final Offset center = _qrCenter(pos);

    // Scale from image coordinates to display coordinates.
    final double scaleX = _imageRect!.width / pos.imageWidth;
    final double scaleY = _imageRect!.height / pos.imageHeight;

    final double displayX =
        _imageRect!.left + center.dx * scaleX - _kIndicatorSize / 2;
    final double displayY =
        _imageRect!.top + center.dy * scaleY - _kIndicatorSize / 2;

    return Positioned(
      left: displayX,
      top: displayY,
      child: GestureDetector(
        onTap: () {
          final String? text = code.text;
          if (text != null && text.isNotEmpty) {
            Navigator.of(context).pop(text);
          }
        },
        child: Container(
          width: _kIndicatorSize,
          height: _kIndicatorSize,
          decoration: BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.arrow_forward,
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);

    return Scaffold(
      appBar: AppBar(
        title:
            Text(s.selectQrCode, style: AppTheme.appBarTheme.titleTextStyle),
      ),
      body: Column(
        children: <Widget>[
          // Instruction banner
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              s.multipleQrCodesDetected,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Image with overlaid QR code indicators
          Expanded(
            child: Stack(
              children: <Widget>[
                // The captured / picked image
                Center(
                  child: Image.memory(
                    widget.imageBytes,
                    key: _imageKey,
                    fit: BoxFit.contain,
                  ),
                ),
                // Green circle indicators for each detected QR code
                if (_imageRect != null)
                  ...widget.codes.map(_buildIndicator),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
