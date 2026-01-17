// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

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
  Uint8List? bytes;

  final int frameRate = 1;

  // Maximum number of frames to prevent memory overflow.
  // Uses circular buffer: when limit is reached, oldest frames are discarded.
  // 300 frames can record approximately 300 moves, sufficient for most games.
  static const int maxFrames = 300;

  // Additional hard cap on buffered PNG bytes to prevent extreme memory growth
  // on high-resolution devices or under stress tests (e.g. Monkey).
  static const int maxBufferedBytes = 128 * 1024 * 1024; // 128 MiB

  int _bufferedBytes = 0;

  void _evictOldestFrame() {
    if (pngs.isEmpty) {
      return;
    }
    final Uint8List removed = pngs.removeAt(0);
    _bufferedBytes -= removed.length;
    if (_bufferedBytes < 0) {
      _bufferedBytes = 0;
    }
  }

  void _addFrame(Uint8List frameBytes) {
    for (int i = 0; i < frameRate; i++) {
      // Frame count cap (circular buffer).
      if (pngs.length >= maxFrames) {
        _evictOldestFrame();
      }

      pngs.add(frameBytes);
      _bufferedBytes += frameBytes.length;

      // Total bytes cap (drop oldest until under limit).
      while (pngs.isNotEmpty && _bufferedBytes > maxBufferedBytes) {
        _evictOldestFrame();
      }
    }
  }

  Future<void> captureView({bool first = false}) async {
    if (DB().generalSettings.gameScreenRecorderSupport == false) {
      return;
    }

    if (first) {
      releaseData();
    }

    final Uint8List? bytes = await controller.capture();
    if (bytes != null) {
      _addFrame(bytes);
    }
  }

  void releaseData() {
    bytes = null;
    pngs.clear();
    _bufferedBytes = 0;
  }

  /// Call when "Share GIF" is tapped.
  Future<bool> shareGif() async {
    if (DB().generalSettings.gameScreenRecorderSupport == false) {
      return false;
    }

    if (pngs.isEmpty) {
      return false;
    }

    if (pngs.isNotEmpty) {
      _evictOldestFrame(); // TODO: WAR
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

    // Release memory immediately after encoding
    final bool result;
    if (gifData != null) {
      result = await _writeGifToFile(gifData);
    } else {
      result = false;
    }

    // Clear captured frames to free memory
    releaseData();

    return result;
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
      ShareParams(files: <XFile>[XFile('${docDir.path}/$gifFileName')]),
    );
    return true;
  }
}
