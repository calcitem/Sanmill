// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

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
      final RenderRepaintBoundary? boundary = containerKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;

      final double ratio =
          DB().generalSettings.gameScreenRecorderPixelRatio / 100;

      /// Convert boundary to image
      final ui.Image image = await boundary!.toImage(
        pixelRatio: ratio,
      );

      /// Set ImageByteFormat
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List? pngBytes = byteData?.buffer.asUint8List();
      return pngBytes;
    } catch (e) {
      logger.e(e);
      return null;
    }
  }
}
