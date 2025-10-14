// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// widgets_to_image_controller.dart

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../shared/database/database.dart';
import '../../../shared/services/logger.dart';

class WidgetsToImageController {
  GlobalKey containerKey = GlobalKey();

  /// To capture widget to image by GlobalKey in RenderRepaintBoundary
  Future<Uint8List?> capture() async {
    try {
      /// Boundary widget by GlobalKey
      final RenderRepaintBoundary? boundary =
          containerKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;

      if (boundary == null) {
        logger.w("Boundary is null, cannot capture image");
        return null;
      }

      // Check if the widget needs to be painted before capturing
      if (boundary.debugNeedsPaint) {
        logger.w("Widget needs paint, skipping capture to avoid assertion");
        return null;
      }

      final double ratio =
          DB().generalSettings.gameScreenRecorderPixelRatio / 100;

      /// Convert boundary to image
      final ui.Image image = await boundary.toImage(pixelRatio: ratio);

      /// Set ImageByteFormat
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      final Uint8List? pngBytes = byteData?.buffer.asUint8List();
      
      // Dispose image to free memory
      image.dispose();
      
      return pngBytes;
    } catch (e) {
      logger.e(e);
      return null;
    }
  }
}
