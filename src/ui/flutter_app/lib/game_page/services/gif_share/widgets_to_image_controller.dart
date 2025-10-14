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
      RenderRepaintBoundary? boundary =
          containerKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;

      if (boundary == null) {
        logger.w("Boundary is null, cannot capture image");
        return null;
      }

      // Wait for the widget to finish painting if needed
      if (boundary.debugNeedsPaint) {
        logger.w("Widget needs paint, waiting for next frame");
        await WidgetsBinding.instance.endOfFrame;
        
        // Re-acquire boundary after waiting
        boundary = containerKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        
        if (boundary == null || boundary.debugNeedsPaint) {
          logger.w("Boundary still not ready after waiting");
          return null;
        }
      }

      // Respect user's pixel ratio setting (25%, 50%, 75%, or 100%)
      final double ratio =
          DB().generalSettings.gameScreenRecorderPixelRatio / 100;

      /// Convert boundary to image
      final ui.Image image = await boundary.toImage(pixelRatio: ratio);

      /// Set ImageByteFormat
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      final Uint8List? pngBytes = byteData?.buffer.asUint8List();
      
      // Dispose image to free memory immediately
      image.dispose();
      
      return pngBytes;
    } catch (e) {
      logger.e(e);
      return null;
    }
  }
}
