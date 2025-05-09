// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// gif_share.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../shared/database/database.dart';
import 'widgets_to_image_controller.dart';

class GifShare {
  factory GifShare() => _instance ?? GifShare._internal();

  GifShare._internal() {
    _instance = this;
  }

  static GifShare? _instance;

  final WidgetsToImageController controller = WidgetsToImageController();
  final List<Uint8List> pngs = <Uint8List>[];
  final List<img.Image> images = <img.Image>[];
  Uint8List? bytes;

  final int frameRate = 1;

  Future<void> captureView({bool first = false}) async {
    if (DB().generalSettings.gameScreenRecorderSupport == false) {
      return;
    }

    if (first) {
      releaseData();
    }
    final Uint8List? bytes = await controller.capture();
    if (bytes != null) {
      for (int i = 0; i < frameRate; i++) {
        pngs.add(bytes);
      }
    }
  }

  void releaseData() {
    bytes = null;
    pngs.clear();
    images.clear();
  }

  /// Call when "Share GIF" is tapped.
  Future<bool> shareGif() async {
    if (DB().generalSettings.gameScreenRecorderSupport == false) {
      return false;
    }

    if (pngs.isNotEmpty) {
      pngs.removeRange(0, 1); // TODO: WAR
    }

    final img.GifEncoder encoder = img.GifEncoder(
      repeat: DB().generalSettings.gameScreenRecorderDuration,
      samplingFactor: 160,
    );

    for (final Uint8List data in pngs) {
      final img.Image? decodeImage = img.decodeImage(data);
      if (decodeImage != null) {
        encoder.addFrame(decodeImage);
      }
    }

    final Uint8List? gifData = encoder.finish();
    if (gifData != null) {
      return _writeGifToFile(gifData);
    } else {
      return false;
    }
  }

  Future<bool> _writeGifToFile(List<int> gif) async {
    if (DB().generalSettings.gameScreenRecorderSupport == false) {
      return false;
    }

    final String time = DateTime.now().millisecondsSinceEpoch.toString();
    final String gifFileName = "Mill-$time.gif";
    final Directory docDir = await getApplicationDocumentsDirectory();
    final File imgGif = File('${docDir.path}/$gifFileName');
    await imgGif.writeAsBytes(gif);
    SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile('${docDir.path}/$gifFileName')],
      ),
    );
    return true;
  }
}
