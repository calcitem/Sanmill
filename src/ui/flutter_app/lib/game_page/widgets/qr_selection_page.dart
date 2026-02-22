// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// qr_selection_page.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/themes/app_theme.dart';

/// Displays a picked image overlaid with tappable bounding-box highlights
/// at each detected QR code position, so the user can tap the one to import.
///
/// Returns the selected QR code text via [Navigator.pop].
class QrSelectionPage extends StatefulWidget {
  const QrSelectionPage({
    required this.imageBytes,
    required this.codes,
    super.key,
  });

  final Uint8List imageBytes;
  final List<Code> codes;

  @override
  State<QrSelectionPage> createState() => _QrSelectionPageState();
}

class _QrSelectionPageState extends State<QrSelectionPage> {
  /// Key placed on the [Image.memory] widget so we can measure its render box.
  final GlobalKey _imageKey = GlobalKey();

  /// Key placed on the [Stack] so Positioned offsets are relative to it.
  final GlobalKey _stackKey = GlobalKey();

  /// Rect of the rendered image in the Stack's local coordinates.
  Rect? _imageRect;

  // ── Measurement ─────────────────────────────────────────────────────

  /// Compute [_imageRect] from the current layout.
  ///
  /// Called after the first frame AND whenever the image finishes decoding
  /// (via [frameBuilder]).  The Image widget is sized by [RenderImage] to
  /// exactly the scaled image dimensions (i.e., no letterboxing inside the
  /// widget itself), so [_imageRect] equals the painted image area.
  void _measure() {
    if (!mounted) {
      return;
    }

    final RenderBox? imageBox =
        _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (imageBox == null || !imageBox.hasSize) {
      return;
    }

    // Positions for Positioned children are relative to the Stack, not the
    // whole Scaffold.  Use the Stack's RenderBox as the reference frame.
    final RenderBox? stackBox =
        _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || !stackBox.hasSize) {
      return;
    }

    // Image position relative to the Stack.
    final Offset offset =
        imageBox.localToGlobal(Offset.zero) -
        stackBox.localToGlobal(Offset.zero);

    setState(() {
      _imageRect = Rect.fromLTWH(
        offset.dx,
        offset.dy,
        imageBox.size.width,
        imageBox.size.height,
      );
    });
  }

  // ── Highlight builder ────────────────────────────────────────────────

  /// Build a tappable green bounding box for one detected QR code.
  Widget _buildHighlight(Code code, int index) {
    final Position? pos = code.position;
    if (pos == null || _imageRect == null) {
      return const SizedBox.shrink();
    }

    final double srcW = pos.imageWidth.toDouble();
    final double srcH = pos.imageHeight.toDouble();
    if (srcW <= 0 || srcH <= 0) {
      return const SizedBox.shrink();
    }

    // Scale from the analyzed image space to the displayed image space.
    final double scaleX = _imageRect!.width / srcW;
    final double scaleY = _imageRect!.height / srcH;

    // Bounding box from the four corner points ZXing provides.
    final double minX = <int>[
      pos.topLeftX,
      pos.topRightX,
      pos.bottomLeftX,
      pos.bottomRightX,
    ].reduce((int a, int b) => a < b ? a : b).toDouble();
    final double maxX = <int>[
      pos.topLeftX,
      pos.topRightX,
      pos.bottomLeftX,
      pos.bottomRightX,
    ].reduce((int a, int b) => a > b ? a : b).toDouble();
    final double minY = <int>[
      pos.topLeftY,
      pos.topRightY,
      pos.bottomLeftY,
      pos.bottomRightY,
    ].reduce((int a, int b) => a < b ? a : b).toDouble();
    final double maxY = <int>[
      pos.topLeftY,
      pos.topRightY,
      pos.bottomLeftY,
      pos.bottomRightY,
    ].reduce((int a, int b) => a > b ? a : b).toDouble();

    const double pad = 6.0;
    final double left = _imageRect!.left + minX * scaleX - pad;
    final double top = _imageRect!.top + minY * scaleY - pad;
    final double boxW = (maxX - minX) * scaleX + pad * 2;
    final double boxH = (maxY - minY) * scaleY + pad * 2;

    return Positioned(
      left: left,
      top: top,
      width: boxW,
      height: boxH,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final String? text = code.text;
          if (text != null && text.isNotEmpty) {
            Navigator.of(context).pop(text);
          }
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.green, width: 3),
            borderRadius: BorderRadius.circular(8),
            color: Colors.green.withValues(alpha: 0.12),
          ),
          alignment: Alignment.topRight,
          padding: const EdgeInsets.all(2),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.selectQrCode, style: AppTheme.appBarTheme.titleTextStyle),
      ),
      body: Column(
        children: <Widget>[
          // Instruction banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              s.multipleQrCodesDetected,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Image + overlaid highlights
          Expanded(
            child: Stack(
              key: _stackKey,
              children: <Widget>[
                // The image is placed inside Center so it is centered in the
                // Stack.  RenderImage sizes itself to exactly the scaled image
                // dimensions (preserving aspect ratio within the loose
                // constraints supplied by Center), so the widget bounds
                // match the painted pixel area — no letterboxing offset.
                Center(
                  child: Image.memory(
                    widget.imageBytes,
                    key: _imageKey,
                    fit: BoxFit.contain,
                    frameBuilder:
                        (
                          BuildContext context,
                          Widget child,
                          int? frame,
                          bool wasSynchronouslyLoaded,
                        ) {
                          if (frame != null) {
                            // Image has decoded; schedule a precise measurement
                            // after the next layout pass.
                            WidgetsBinding.instance.addPostFrameCallback(
                              (_) => _measure(),
                            );
                          }
                          return child;
                        },
                  ),
                ),
                // Bounding-box tap targets, rendered only after measurement.
                if (_imageRect != null)
                  ...widget.codes.asMap().entries.map(
                    (MapEntry<int, Code> e) => _buildHighlight(e.value, e.key),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
